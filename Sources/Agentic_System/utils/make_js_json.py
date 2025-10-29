import os
import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

PATH = "/usr/share/vrigatoni/v8_2/v8/out.gn/x64.release/d8"
folder = "regressions"
json_file = "regressions.json"

# file name : { "js": "js code", "Fuzzilli": "Fuzzilli code", "execution_data": "bytecode and graphs" }

FUZZIL_BIN = "/usr/share/vrigatoni/fuzzillai/.build/x86_64-unknown-linux-gnu/debug/FuzzILTool"

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
    fuzz = subprocess.run([FUZZIL_BIN, "--compile", js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    combined = (fuzz.stdout or "")
    data["Fuzzilli"] = parse_fuzzil_from_output(combined)
    d8 = subprocess.run([PATH, "--print-bytecode", "--print-maglev-code", "--print-maglev-graphs", js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    data["execution_data"] = d8.stdout.decode('utf-8', errors='ignore')
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