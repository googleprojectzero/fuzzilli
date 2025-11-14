import subprocess
import os
import sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import rises_the_fog as fog

# script_dir = Path(__file__).parent
# print(script_dir)
# fog_module_path = script_dir /  "rises-the-fog.py"
# spec = importlib.util.spec_from_file_location("rises_the_fog", fog_module_path)
# fog = importlib.util.module_from_spec(spec)
# spec.loader.exec_module(fog)

#export V8_PATH=/usr/share/vrigatoni/v8_2/v8/out/
#export D8_PATH=/usr/share/vrigatoni/v8_2/v8/out/fuzzbuild/d8
#export FUZZILLI_TOOL_BIN=/mnt/vdb/fuzzillai/.build/x86_64-unknown-linux-gnu/debug/FuzzILTool
#export FUZZILLI_PATH=/mnt/vdb/fuzzilla

with ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(fog.run, force_logging=True) for _ in range(16)]
    for i, future in enumerate(futures):
        print(f"started: {i}")
        future.result()

# def revert_to_original():
#     script_dir = os.path.dirname(os.path.abspath(__file__))
#     a = os.path.join(script_dir, "Agentic_System/orginals/ProgramTemplateWeights.swift")
#     b = os.path.join(script_dir, "Fuzzilli/CodeGen/ProgramTemplateWeights.swift")
#     os.rename(a, b)
#     a = os.path.join(script_dir, "Agentic_System/orginals/ProgramTemplates.swift")
#     b = os.path.join(script_dir, "Fuzzilli/CodeGen/ProgramTemplates.swift")
#     os.rename(a, b)


# def write_sql(reuslt: bool):
#     if reuslt:
#         with open("sql.sql", "r") as f:
#             sql = f.read()
#     else:
#         with open("sql.sql", "r") as f:
#             sql = f.read()

#     return sql

# result = subprocess.run(["swift", "build"], capture_output=True, text=True)
# if result.returncode == 0:
#     write_sql(True)
#     print("Build templates succeeded")
# else:
#     write_sql(False)
#     revert_to_original()
#     print("Build templates failed")
#     print(result.stdout)
#     print(result.stderr)
#     r2 = subprocess.run(["swift", "build"], capture_output=True, text=True)
#     if r2.returncode == 0:
#         print("Build reverted succeeded")
#     else:
#         print("safety revert failed")
#         print(r2.stdout)
#         print(r2.stderr)
#         exit(1)

