import os
import json
import subprocess
import re

folder = "../templates"
json_file = "templates.json"

files_data = {}

templates_directory = b"../../../Corpus/lifted_templates/"
swift_program_templates = ['../../../Sources/Fuzzilli/CodeGen/ProgramTemplates.swift', '../../../Sources/FuzzilliCli/Profiles/V8CommonProfile.swift']

swift_templates = {}
def get_swift_templates(swift_content: str) -> None:
    regex = r'(Program|WasmProgram)Template\("(?P<name>[^"]+)"\)\s*\{(?P<code>.*?)\n\s*\},?'
    for match in re.finditer(regex, swift_content, re.DOTALL):
        name = match.group('name').strip()
        code = match.group('code').strip()
        swift_templates[name] = code
    print(swift_templates)
    #return swift_templates

for path in swift_program_templates:
    with open(path, "r") as f:
        swift_content = f.read()
    get_swift_templates(swift_content)

for file in os.listdir(templates_directory):
    data = { "ProgramTemplateName": "", "ProgramTemplateSwift": "", "ProgramTemplateFuzzIL": ""}

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
        data["ProgramTemplateFuzzIL"] = lifted_program

    if template_name in swift_templates:
        data["ProgramTemplateSwift"] = swift_templates[template_name]
    files_data[template_name] = data

try:
    os.makedirs(folder)
except FileExistsError:
    pass

#print(files_data)
with open(f"{folder}/{json_file}", "w") as f:
    json.dump(files_data, f, indent=2)
