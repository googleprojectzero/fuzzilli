// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Collections

public class ContextGraph {
    // This is an edge, it holds all Generators that provide the `to` context at some point.
    // Another invariant is that each Generator will keep the original context, i.e. it will return to the `from` conetxt.
    struct EdgeKey: Hashable {
        let from: Context
        let to: Context

        public init(from: Context, to: Context) {
            self.from = from
            self.to = to
        }
    }

    // This struct describes the value of an edge in this ContextGraph.
    // It holds all `CodeGenerator`s that go from one context to another in a direct transition.
    public struct GeneratorEdge {
        var generators: [CodeGenerator] = []

        // Adds a generator to this Edge.
        public mutating func addGenerator(_ generator: CodeGenerator) {
            generators.append(generator)
        }
    }

    // This is a Path that goes from one Context to another via (usually more than one) `GeneratorEdge`. It is a full path in the Graph.
    // Every Edge in a path may be provided by various CodeGenerators.
    public struct Path {
        let edges: [GeneratorEdge]

        // For each edge, pick a random Generator that provides that edge.
        public func randomConcretePath() -> [CodeGenerator] {
            edges.map { edge in
                chooseUniform(from: edge.generators)
            }
        }
    }

    // This is the Graph, each pair of from and to, maps to a `GeneratorEdge`.
    var edges: [EdgeKey: GeneratorEdge] = [:]

    public init(for generators: WeightedList<CodeGenerator>, withLogger logger: Logger) {
        // Technically we don't need any generator to emit the .javascript context, as this is provided by the toplevel.
        var providedContexts = Set<Context>([.javascript])
        var requiredContexts = Set<Context>()

        for generator in generators {
            generator.providedContexts.forEach { ctx in
                providedContexts.insert(ctx)
            }

            requiredContexts.insert(generator.requiredContext)
        }

        // Check that every part that provides something is used by the next part of the Generator. This is a simple consistency check.
        for generator in generators where generator.parts.count > 1 {
            var currentContext = Context(generator.parts[0].providedContext)

            for i in 1..<generator.parts.count {
                let stub = generator.parts[i]

                guard stub.requiredContext.matches(currentContext) ||
                (stub.requiredContext.isJavascript && currentContext.isEmpty) ||
                // If the requiredContext is more than two, we should never provide a context.
                // See `CodeGenerator` for details.
                (!stub.requiredContext.isSingle && currentContext.isEmpty) else {
                    fatalError("Inconsistent requires/provides Contexts for \(generator.name)")
                }

                currentContext = Context(stub.providedContext)
            }
        }

        for generator in generators {
            // Now check which generators don't have providers
            if !providedContexts.contains(generator.requiredContext) {
                logger.warning("Generator \(generator.name) cannot be run as it doesn't have a Generator that can provide this context.")

            }

            // All provided contexts must be required by some generator.
            if !generator.providedContexts.allSatisfy({
                requiredContexts.contains($0)
            }) {
                logger.warning("Generator \(generator.name) provides a context that is never required by another generator \(generator.providedContexts)")
            }
        }

        // One can still try to build in a context that doesn't have generators, this will be caught in the build function, if we fail to find any suitable generator.
        // Otherwise we could assert here that the sets are equal.
        // One example is a GeneratorStub that opens a context, then calls build manually without it being split into two stubs where we have a yield point to assemble a synthetic generator.
        self.edges = [:]

        for generator in generators {
            for providableContext in generator.providedContexts {
                let edge = EdgeKey(from: generator.requiredContext, to: providableContext)
                self.edges[edge, default: GeneratorEdge()].addGenerator(generator)
            }
        }
    }

    /// Gets all possible paths from the `from` Context to the `to` Context.
    /// TODO: Do this initially and cache all results?
    func getAllPaths(from src: Context, to dst: Context) -> [[EdgeKey]] {
        // Do simple BFS to find all possible paths.
        var queue: Deque<[Context]> = [[src]]
        var paths: [[Context]] = []
        var seenNodes = Set<Context>([src])

        while !queue.isEmpty {
            // use popFirst here from the deque.
            let currentPath = queue.popFirst()!

            let currentNode = currentPath.last!

            if currentNode == dst {
                paths.append(currentPath)
            }

            // Get all possible edges from here on and push all of those to the queue.
            for edge in self.edges where edge.key.from == currentNode && !seenNodes.contains(edge.key.to) {
                // Prevent cycles, we don't care about complicated paths, but rather simple direct paths.
                seenNodes.insert(edge.key.to)
                queue.append(currentPath + [edge.key.to])
            }
        }

        if paths.isEmpty {
            return []
        }

        // Reduce this to Edges structs that we can easily look up.
        var edgePaths: [[EdgeKey]] = []
        for path in paths {
            var edgePath: [EdgeKey] = []
            for i in 0..<(path.count - 1) {
                let edge = EdgeKey(from: path[i], to: path[i+1])
                edgePath.append(edge)
            }
            edgePaths.append(edgePath)
        }

        return edgePaths
    }

    func getGenerators(from src: Context, to dst: Context) -> GeneratorEdge? {
        self.edges[EdgeKey(from: src, to: dst)]
    }

    // TODO(cffsmith) implement this to filter for generators that are actually reachable, we can use this to avoid picking a .javascript generator when we're in .wasmFunction context for example.
    // This is needed since we cannot close Contexts or go back in time yet. This essentially calculates all reachable destinations from `src`.
    // The caller can then use `fuzzer.codeGenerators.filter { $0.requiredContext.contains(<any reachable>) }` and pick a random one from that subset.
    func getReachableContexts(from src: Context) -> [Context] {
        // Do simple BFS to find all possible paths.
        var queue: Deque<[Context]> = [[src]]
        var paths: [[Context]] = []
        var seenNodes = Set<Context>([src])

        while !queue.isEmpty {
            let currentPath = queue.popFirst()!

            let currentNode = currentPath.last!

            var stillExploring = false

            // Get all possible edges from here on and push all of those to the queue.
            for edge in self.edges where edge.key.from == currentNode && !seenNodes.contains(edge.key.to) {
                // Prevent cycles, we don't care about complicated paths, but rather simple direct paths.
                stillExploring = true
                seenNodes.insert(edge.key.to)
                queue.append(currentPath + [edge.key.to])
            }

            // If we haven't added another node, it means we have found an "end".
            if !stillExploring {
                paths.append(currentPath)
            }
        }

        if paths.isEmpty {
            return []
        }

        // Map to all reachable contexts. so all that are on the path.
        let contextSet = paths.reduce(Set()) { res, path in
            res.union(path)
        }
        return Array(contextSet)
    }

    // The return value is a list of possible Paths.
    // A Path is a possible way from one context to another.
    public func getCodeGeneratorPaths(from src: Context, to dst: Context) -> [Path]? {

        let paths = getAllPaths(from: src, to: dst)

        if paths.isEmpty {
            return nil
        }

        return paths.map { edges in
            Path(edges: edges.map { edge in
                self.edges[edge]!
            })
        }
    }
}
