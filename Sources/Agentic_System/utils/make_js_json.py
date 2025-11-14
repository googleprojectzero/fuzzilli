import os
import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm
import sys  

folder = "regressions"
json_file = "regressions.json"

# file name : { "js": "js code", "Fuzzilli": "Fuzzilli code", "execution_data": "bytecode and graphs" }

if not os.getenv('D8_PATH'):
    print("D8_PATH is not set")
    sys.exit(1)
if not os.getenv('FUZZILLI_TOOL_BIN'):
    print("FUZZILLI_TOOL_BIN is not set")
    sys.exit(1)

D8_PATH = os.getenv('D8_PATH')
FUZZILLI_TOOL_BIN = os.getenv('FUZZILLI_TOOL_BIN')
def collect_js_files(root_dir):
    files = []
    for r, _, names in os.walk(root_dir):
        for n in names:
            if n.endswith('.js'):
                files.append(os.path.join(r, n))
    return files

def parse_fuzzil_from_output(text):
    start_seen = False
    out_lines = []
    for line in (text or "").splitlines():
        if not start_seen:
            if line.strip().startswith("v") or line.strip().startswith("const") or line.strip().startswith("function"):
                start_seen = True
                out_lines.append(line)
            continue
        if line.startswith("FuzzIL program written to"):
            break
        out_lines.append(line)
    return "\n".join(out_lines).strip()

files_data = {}
js_files = collect_js_files(folder)
total = len(js_files)
print(f"Discovered {total} JavaScript files under '{folder}' (recursive)")

def process_one(js_path):
    rel = os.path.relpath(js_path, folder)
    key = rel[:-3] if rel.endswith('.js') else rel
    data = { "js": "", "Fuzzilli": "", "execution_data": "" }
    with open(js_path, 'r') as f:
        data["js"] = f.read()
    fuzz = subprocess.run([FUZZILLI_TOOL_BIN, "--compile", js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    combined = (fuzz.stdout or "")
    data["Fuzzilli"] = parse_fuzzil_from_output(combined)
    d8 = subprocess.Popen([D8_PATH, "--allow-natives-syntax", 
                                "--print-bytecode", 
                                "--print-maglev-code", 
                                "--print-maglev-graphs", 
                                "--maglev-print-feedback",
                               # "--maglev-print-inlined",
                               # "--print-maglev-deopt-verbose",
                               # "--print-deopt-stress",
                               # "--print-wasm-code",
                               # "--print-wasm-stub-code",
                               # "--print-all-exceptions",
                                "--print-flag-values",
                               # #"--print-feature-flags-json",
                               # "--print-ast",
                                "--print-scopes",
                               # "--gc-verbose",
                               # "--print-handles",
                               # "--print-global-handles",
                               # "--print-break-location",
                                "--print-opt-source",
                               # "--print-builtin-size",
                               # #"--print-opt-code",
                               # #"--print-code-verbose",
                               # #"--print-builtin-code",
                               # #"--print-regexp-code",
                               # "--turboshaft-trace-load-elimination",
                               # "--turboshaft-trace-peeling",
                               # "--turboshaft-trace-unrolling",
                               # "--turboshaft-trace-emitted",
                               # "--turboshaft-trace-intermediate-reductions",
                                "--turboshaft-trace-reduction",
                                "--turboshaft-trace-typing",
                               # #"--trace-creation-allocation-sites",
                               # #"--trace-elements-transitions",
                               # "--trace-isolates",
                               # "--trace-lazy",
                               # "--trace-normalization",
                               # "--trace-module-status",
                               # "--trace-contexts",
                               # "--trace-minor-ms-parallel-marking",
                               # "--trace-read-only-promotion-verbose",
                               # "--trace-read-only-promotion",
                               # "--trace-experimental-regexp-engine",
                               # "--trace-regexp-graph",
                               # "--trace-regexp-tier-up",
                               # "--trace-regexp-parser",
                               # "--trace-regexp-assembler",
                               # "--trace-regexp-bytecodes",
                               # "--trace-regexp-peephole-optimization",
                               # "--trace-deserialization",
                               # "--trace-code-range-allocation",
                               # "--trace-rail",
                               # "--trace-for-in-enumerate",
                               # "--trace-prototype-users",
                               # "--trace-side-effect-free-debug-evaluate",
                               # "--trace-compiler-dispatcher",
                               # "--trace-serializer",
                               # #"--trace-file-names",
                               # "--trace-deopt-verbose",
                                "--trace-deopt",
                               # "--trace-opt-stats",
                                "--trace-opt-verbose",
                                "--trace-opt-status",
                                "--trace-opt",
                               # "--trace",
                               # "--trace-memory-balancer",
                               # "--trace-context-disposal",
                               # "--trace-flush-code",
                               # "--trace-detached-contexts",
                               # "--trace-backing-store",
                               # "--trace-zone-type-stats",
                               # "--trace-zone-stats",
                               # "--trace-gc-object-stats",
                               # "--trace-stress-scavenge",
                               # "--trace-stress-marking",
                               # "--trace-incremental-marking",
                               # "--trace-concurrent-marking",
                               # "--trace-parallel-scavenge",
                               # "--trace-unmapper",
                               # "--trace-mutator-utilization",
                               # "--trace-evacuation",
                               # "--trace-fragmentation-verbose",
                               # "--trace-fragmentation",
                               # #"--trace-duplicate-threshold-kb",
                               # #"--trace-allocation-stack-interval",
                               # "--trace-pending-allocations",
                               # "--trace-evacuation-candidates",
                               # "--trace-gc-heap-layout-ignore-minor-gc",
                               # "--trace-gc-heap-layout",
                               # "--trace-gc-freelists-verbose",
                               # "--trace-gc-freelists",
                                "--trace-gc-verbose",
                               # "--trace-memory-reducer",
                               # "--trace-gc-ignore-scavenger",
                               # "--trace-gc-nvp",
                               # "--trace-gc",
                               # "--trace-wasm-revectorize",
                               # "--trace-wasm-instances",
                                "--trace-wasm",
                               # "--trace-wasm-code-gc",
                               # "--trace-wasm-lazy-compilation",
                               # "--trace-wasm-loop-peeling",
                               # "--trace-wasm-typer",
                               # "--trace-wasm-inlining",
                               # "--trace-asm-parser",
                               # "--trace-asm-scanner",
                               # "--trace-asm-time",
                               # "--trace-wasm-globals",
                               # "--trace-wasm-memory",
                               # "--trace-liftoff",
                               # "--trace-wasm-stack-switching",
                               # "--trace-wasm-streaming",
                               # "--trace-wasm-compiler",
                               # "--trace-wasm-decoder",
                               # "--trace-wasm-compilation-times",
                               # "--trace-wasm-serialization",
                               # "--trace-wasm-offheap-memory",
                               # "--trace-wasm-native-heap",
                                "--trace-turbolev-graph-building",
                                "--trace-store-elimination",
                                "--trace-turbo-load-elimination",
                                "--trace-turbo-escape",
                               # "--trace-environment-liveness",
                                "--trace-osr",
                                "--trace-maglev-object-tracking",
                               # "--trace-maglev-escape-analysis",
                               # "--trace-turbo-inlining",
                               # "--trace-verify-csa",
                               # "--trace-turbo-stack-accesses",
                               # #"--trace-representation",
                               # #"--trace-all-uses",
                               # #"--trace-turbo-alloc",
                               # #"--trace-turbo-loop",
                               # #"--trace-turbo-ceq",
                               # #"--trace-turbo-jt",
                               # #"--trace-turbo-trimming",
                               # "--trace-turbo-bailouts",
                               # "--trace-turbo-reduction",
                               # "--trace-turbo-scheduler",
                               # "--trace-turbo-types",
                               # "--trace-turbo-scheduled",
                               # "--trace-turbo-graph",
                               # "--trace-heap-broker-verbose",
                               # "--trace-concurrent-recompilation",
                               # "--trace-baseline-batch-compilation",
                               # "--trace-baseline",
                                "--trace-generalization",
                                "--trace-migration",
                               # "--trace-track-allocation-sites",
                               # "--trace-ignition-codegen",
                                "--trace-protector-invalidation",
                               # "--trace-block-coverage",
                               # "--trace-resize-large-object",
                               # "--trace-pretenuring-statistics",
                                "--trace-pretenuring",
                               # "--trace-page-promotions",
                               # "--trace-compilation-dependencies",
                               # "--trace-number-string-cache",
                               # "--trace-maglev-regalloc",
                               # "--trace-maglev-phi-untagging",
                               # "--trace-maglev-kna-processor",
                               # "--trace-maglev-inlining",
                               # "--trace-maglev-loop-speeling",
                               # "--trace-maglev-graph-building",
                               # "--trace-temporal",
                                js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    d8_stdout, d8_stderr = d8.communicate()
    data["execution_data"] = d8_stdout.decode("utf-8", errors="ignore")
    return key, data

started_all = time.time()
max_workers = min(8, max(2, (os.cpu_count() or 4)))
with ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures = [executor.submit(process_one, p) for p in js_files]
    for future in tqdm(as_completed(futures), total=total, desc="Processing", unit="file"):
        key, data = future.result()
        files_data[key] = data

print(f"Completed in {time.time()-started_all:.2f}s. Writing {json_file} with {len(files_data)} entries")
with open(json_file, 'w') as f:
    json.dump(files_data, f, indent=2)