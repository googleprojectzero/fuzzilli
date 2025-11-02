import os
import json
import subprocess
import re
import sys

TEMP_JS_FILE = "/tmp/temp-js-file.js"
TEMP_FZIL_FILE = "/tmp/temp-fzil-file.fzil"

folder = "templates"
json_file = "templates.json"

files_data = {}

templates_directory = b"../../Corpus/lifted_templates/"
swift_program_templates = ['../../Sources/Fuzzilli/CodeGen/ProgramTemplates.swift', '../../Sources/FuzzilliCli/Profiles/V8CommonProfile.swift']

if not os.getenv('D8_PATH'):
    print("D8_PATH is not set")
    sys.exit(1)
if not os.getenv('FUZZILLI_TOOL_BIN'):
    print("FUZZILLI_TOOL_BIN is not set")
    sys.exit(1)
D8_PATH = os.getenv('D8_PATH')
FUZZILLI_TOOL_BIN = os.getenv('FUZZILLI_TOOL_BIN')

swift_templates = {}
def get_swift_templates(swift_content: str) -> None:
    regex = r'(Program|WasmProgram)Template\("(?P<name>[^"]+)"\)\s*\{(?P<code>.*?)\n\s*\},?'
    for match in re.finditer(regex, swift_content, re.DOTALL):
        name = match.group('name').strip()
        code = match.group('code').strip()
        swift_templates[name] = code
    #print(swift_templates)
    #return swift_templates

for path in swift_program_templates:
    with open(path, "r") as f:
        swift_content = f.read()
    get_swift_templates(swift_content)

for file in os.listdir(templates_directory):
    data = { "ProgramTemplateName": "", 
            "ProgramTemplateSwift": "", 
            "ProgramTemplateFuzzIL": "", 
            "ProgramTemplateJS": "", 
            "ProgramTemplateExecution": ""
    }

    with open(templates_directory + file, "rb") as f:
        content = f.read()

    content = str(content.decode('utf-8')) 
    first_newline_index = content.find('\n')
    if first_newline_index != -1:
        template_line = content[:first_newline_index]
        _, template_name = template_line.split(': ', 1)
        data["ProgramTemplateName"] = template_name

    program_marker = 'Program:\n'
    program_start_index = content.find(program_marker) + len(program_marker)
    if program_start_index - len(program_marker) != -1:
        lifted_program = content[program_start_index:]
        data["ProgramTemplateJS"] = lifted_program

    if template_name in swift_templates:
        data["ProgramTemplateSwift"] = swift_templates[template_name]

    js_path = f"{templates_directory.decode("utf-8")}{file.decode("utf-8")}"

    fuzz = subprocess.run([FUZZILLI_TOOL_BIN, "--compile", js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) 
    data["ProgramTemplateFuzzIL"] = fuzz.stdout or ""
    
    d8 = subprocess.Popen([D8_PATH, "--allow-natives-syntax", 
                                "--print-bytecode", 
                                "--print-maglev-code", 
                                "--print-maglev-graphs", 
                                "--maglev-print-feedback",
                                "--print-flag-values",
                                "--print-scopes",
                                "--print-opt-source",
                                "--turboshaft-trace-reduction",
                                "--turboshaft-trace-typing",
                                "--trace-deopt",
                                "--trace-opt-verbose",
                                "--trace-opt-status",
                                "--trace-opt",
                                "--trace-gc-verbose",
                                "--trace-wasm",
                                "--trace-turbolev-graph-building",
                                "--trace-store-elimination",
                                "--trace-turbo-load-elimination",
                                "--trace-turbo-escape",
                                "--trace-osr",
                                "--trace-maglev-object-tracking",
                                "--trace-generalization",
                                "--trace-migration",
                                "--trace-protector-invalidation",
                                "--trace-pretenuring",
                                js_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    d8_stdout, d8_stderr = d8.communicate()
    data["ProgramTemplateExecution"] = d8_stdout.decode("utf-8", errors="ignore") or ""

    files_data[template_name] = data

try:
    os.makedirs(folder)
except FileExistsError:
    pass

with open(f"{folder}/{json_file}", "w") as f:
    json.dump(files_data, f, indent=2)
