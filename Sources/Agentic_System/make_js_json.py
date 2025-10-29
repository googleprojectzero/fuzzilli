import os
import json
import subprocess
PATH = "/usr/share/vrigatoni/fuzzillai/v8/v8/out/fuzzbuild/d8"
folder = "regressions"
json_file = "regressions.json"

# file name : { "js": "js code", "Fuzzilli": "Fuzzilli code", "execution_count": "execution count" }

files_data = {}
for file in os.listdir(folder):
    if file.endswith(".js"):
        data = { "js": "", "Fuzzilli": "", "ProgramTemplate": "", "execution_count": 0 }
        with open(os.path.join(folder, file), 'r') as f:
            data["js"] = f.read()

        with open(os.path.join(folder, file.replace(".js", ".fuzzilli")), 'r') as f:
            # swift run FuzzILTool --compile <file> > <file>.fuzzilli
            result = subprocess.run(["swift", "run", "FuzzILTool", "--compile", os.path.join(folder, file)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            data["Fuzzilli"] = result.stdout.decode('utf-8')

        with open(os.path.join(folder, file.replace(".js", ".execution_count")), 'r') as f:
            # d8  --print-bytecode --print-maglev-code --print-maglev-graphs 
            result  = subprocess.run([PATH,"--print-bytecode", "--print-maglev-code", "--print-maglev-graphs", os.path.join(folder, file)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            data["execution_count"] = result.stdout.decode('utf-8')    
        files_data[file[:-3]] = data

with open(json_file, 'w') as f:
    json.dump(files_data, f, indent=2)