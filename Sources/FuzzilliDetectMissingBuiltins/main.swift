import Foundation
import Fuzzilli

// Static list of excluded paths.
// If any other engines / profiles are interested in using this executable, this should probably be
// incorporated into the Profile, for now it's just being maintained locally here.
let exclusionList : [String: [String]] = [
  "v8": [
    // The shell arguments are stored in a global `arguments` if not called with --no-arguments.
    // Note: This is completely unrelated to JS's Function.prototype.arguments or the arguments
    // variable inside a function!
    "arguments",
    // Helper for tests, not exposed in production and should not be fuzzed.
    "d8",
    // Things to make d8 a more useful repl, not exposed in production and not fuzzable.
    "print", "printErr", "read", "readbuffer", "readline", "version", "write",
    // Things that exist in Chrome but have separate implementations in d8 and are therefore
    // probably not very interesting for fuzzing.
    "console", "performance",
    // TODO(mliedtke): https://crbug.com/488072252.
    "Realm",
  ]
]

// Disable most logging. The JavaScriptEnvironment prints warning when trying to fetch types for
// builtins it doesn't know about. This is what this script wants to do, so printing warningis for
// it isn't helpful.
Logger.defaultLogLevelWithoutFuzzer = .error

// Helper function that prints out an error message, then exits the process.
func configError(_ msg: String) -> Never {
    print(msg)
    exit(-1)
}

let args = Arguments.parse(from: CommandLine.arguments)

let helpRequested = args["-h"] != nil || args["--help"] != nil
if helpRequested || args.numPositionalArguments != 1 {
    print("""
    Usage:
    \(args.programName) [options] --profile=<profile> /path/to/jsshell

    Options:
        --profile=name               : Select one of several preconfigured profiles.
                                       Available profiles: \(profiles.keys).
        --no-args                    : Invoke the shell without any additional arguments from the profile.
    """)
    exit(helpRequested ? 0 : -1)
}

guard let profileName = args["--profile"], let profile = profiles[profileName] else {
    configError("Please provide a valid profile with --profile=profile_name. Available profiles: \(profiles.keys)")
}

let jsshellArguments = args.has("--no-args") ? [] : profile.processArgs(false)
let runner = JavaScriptExecutor(withExecutablePath: args[0], arguments: jsshellArguments, env: [])
let jsProg = """
(function() {
  const maxDepth = 10; // Limit the maximum recursion depth.
  const seenObjects = new Map();
  let idCounter = 0;
  const flatGraph = {};

  function walk(currentObj, currentDepth) {
    const isObjectOrFunction = currentObj !== null
        && (typeof currentObj === 'object' || typeof currentObj === 'function');

    // Deduplicate objects that appear multiple times in the graph.
    if (seenObjects.has(currentObj)) {
      return seenObjects.get(currentObj);
    }

    // Store current object for deduplication.
    const currentId = idCounter++;
    seenObjects.set(currentObj, currentId);
    let typeLabel = typeof currentObj;
    if (currentObj === null) typeLabel = "null";
    else if (Array.isArray(currentObj)) typeLabel = "array";

    const node = {
      type: typeLabel,
      properties: {}
    };

    flatGraph[currentId] = node;

    if (!isObjectOrFunction) return currentId;
    if (currentDepth >= maxDepth) return currentId;

    let properties = [];
    try {
      properties = Object.getOwnPropertyNames(currentObj);
    } catch (e) {
      return currentId;
    }

    for (const prop of properties) {
      let isGetter = typeof(Object.getOwnPropertyDescriptor(currentObj, prop).get) === 'function';
      let value;
      try {
        value = currentObj[prop];
      } catch (e) {
        const errorId = idCounter++;
        flatGraph[errorId] = { type: "error", properties: {} };
        node.properties[prop] = { id: errorId, isGetter };
        continue;
      }

      node.properties[prop] = {
        id: walk(value, currentDepth + 1),
        isGetter: isGetter
      };
    }
    return currentId;
  }

  walk(globalThis, 0); // Start traversal.
  const flatJSONData = JSON.stringify(flatGraph, null, 2);
  console.log(flatJSONData);
})();
"""

let result = try runner.executeScript(jsProg, withTimeout: 10)
guard result.isSuccess else {
    fatalError("Execution failed: \(result.error)\n\(result.output)")
}

let jsEnvironment = JavaScriptEnvironment(additionalBuiltins: profile.additionalBuiltins, additionalObjectGroups: profile.additionalObjectGroups, additionalEnumerations: profile.additionalEnumerations)
let jsonString = result.output

struct PropertyReference: Codable {
    let id: Int
    let isGetter: Bool
}

struct JSPropertyNode: Decodable {
    let type: String
    let properties: [String: PropertyReference]
}

let data = jsonString.data(using: .utf8)!
let graph: [Int: JSPropertyNode]
do {
    graph = try JSONDecoder().decode([Int: JSPropertyNode].self, from: data)
} catch {
    fatalError("DECODE ERROR: \(error)")
}

var visited = Set<Int>()
var missingBuiltins = [String]()
var potentiallyBroken = [String]()

func checkNode(_ nodeId: Int, path: [String]) {
    if visited.contains(nodeId) { return }
    visited.insert(nodeId)

    guard let node = graph[nodeId] else { return }
    // Calculate the IL type for the current object.
    var type = path.first.map(jsEnvironment.type(ofBuiltin:))
    if type != nil {
        for propertyName in path.dropFirst() {
            type = jsEnvironment.type(ofProperty: propertyName, on: type!)
        }
    }

    let propertyData = node.properties.filter {
      // Each function has a name and a length property. We don't really care about them, so filter
      // them out.
      (($0.key != "name" && $0.key != "length") || node.type != "function")
      // These conversion functions exist on a large amount of objects. The interesting part is
      // calling them during type coercion which will happen automatically.
      && $0.key != "valueOf" && $0.key != "toString"
    }
    for (prop, propertyRef) in propertyData {
        let (childId, isGetter) = (propertyRef.id, propertyRef.isGetter)

        // Skip any `*.prototype.<property>` if <property> is a getter. These getters are meant to
        // be used on an instance of the given object, registering them on the original prototype
        // object doesn't help Fuzzilli in generating interesting programs.
        if path.last == "prototype" && isGetter {
            continue
        }

        var newPath = path
        newPath.append(prop)
        // Skip paths that are considered uninteresting (e.g. test-only builtins).
        let pathString = newPath.joined(separator: ".")
        let isExcluded = exclusionList[profileName]?.contains {
          pathString == $0 || pathString.starts(with: "\($0).")
        } ?? false
        if isExcluded {
            continue
        }

        let isRegistered: Bool
        if let type {
            isRegistered = jsEnvironment.type(ofProperty: prop, on: type) != .jsAnything
        } else {
            assert(path.isEmpty)
            isRegistered = jsEnvironment.hasBuiltin(prop)
        }

        // Some properties exist but aren't "accessible", e.g. a lot of getters exist on the
        // prototype but they can only be called on a receiver, e.g.
        // DisposableStack.prototype.disposed.
        let isAccessible = graph[childId]?.type != "error"

        if !isRegistered && isAccessible {
            missingBuiltins.append(pathString)
        } else if isRegistered && !isAccessible {
            potentiallyBroken.append(pathString)
        }

        checkNode(childId, path: newPath)
    }
}

checkNode(0, path: [])
print(missingBuiltins.sorted().joined(separator: "\n"))
if !potentiallyBroken.isEmpty {
    print("\nPotentially inaccessible but registered builtins: ")
    print(potentiallyBroken.sorted().joined(separator: "\n"))
}
