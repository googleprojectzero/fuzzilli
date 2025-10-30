from smolagents import tool
from tools.common_tools import * 
from fuzzywuzzy import fuzz
import json
import os
import subprocess
import re
import random
import time
from pathlib import Path

# FUZZILTOOL_BIN = f"/usr/share/vrigatoni/fuzzillai/.build/x86_64-unknown-linux-gnu/debug/FuzzILTool"
OUTPUT_DIRECTORY = "/tmp/fog-d8-records" 
RAG_DB_DIR = (Path(__file__).parent.parent / "rag_db").resolve()

# Cached regressions.json data to avoid reloading on every tool call
_REGRESSIONS_PATH = (Path(__file__).parent.parent / "regressions.json").resolve()
_REGRESSIONS_CACHE = None
_TEMPLATES_PATH = (Path(__file__).parent.parent / "templates" / "templates.json").resolve()
_TEMPLATES_CACHE = None


if not os.getenv('D8_PATH'):
    print("D8_path is not set")
    sys.exit(1)
if not os.getenv('FUZZILLI_TOOL_BIN'):
    print("FUZZILLI_TOOL_BIN is not set")
    sys.exit(1)
D8_PATH = os.getenv('D8_PATH')
FUZZILLI_TOOL_BIN = os.getenv('FUZZILLI_TOOL_BIN')

def _load_regressions_once():
    global _REGRESSIONS_CACHE
    if _REGRESSIONS_CACHE is not None:
        return _REGRESSIONS_CACHE
    try:
        with open(_REGRESSIONS_PATH, "r") as f:
            _REGRESSIONS_CACHE = json.load(f)
    except Exception:
        _REGRESSIONS_CACHE = {}
    return _REGRESSIONS_CACHE

def _load_templates_once():
    global _TEMPLATES_CACHE
    if _TEMPLATES_CACHE is not None:
        return _TEMPLATES_CACHE
    try:
        with open(_TEMPLATES_PATH, "r") as f:
            _TEMPLATES_CACHE = json.load(f)
    except Exception:
        _TEMPLATES_CACHE = {}
    return _TEMPLATES_CACHE

def _rag_db_path(rag_db_id: str) -> Path:
    return (RAG_DB_DIR / f"{rag_db_id}.json").resolve()

def _ensure_rag_db_initialized(rag_db_id: str) -> None:
    RAG_DB_DIR.mkdir(parents=True, exist_ok=True)
    path = _rag_db_path(rag_db_id)
    if not path.exists():
        with open(path, "w") as f:
            json.dump({}, f)

def _load_rag_db(rag_db_id: str) -> dict:
    _ensure_rag_db_initialized(rag_db_id)
    path = _rag_db_path(rag_db_id)
    try:
        with open(path, "r") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return data
            return {}
    except Exception:
        return {}

def _save_rag_db(rag_db_id: str, data: dict) -> None:
    _ensure_rag_db_initialized(rag_db_id)
    path = _rag_db_path(rag_db_id)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def _parse_rag_entry(raw: str):
    """
    Accepts either a JSON object string with an "id" field, or a
    "<ID>:{...}" pattern where the right side is JSON.
    Returns (item_id:str, payload:dict) or (None, None) on failure.
    """
    if not isinstance(raw, str):
        return None, None
    s = raw.strip()
    # Try as pure JSON first
    try:
        obj = json.loads(s)
        if isinstance(obj, dict):
            item_id = obj.get("id") or obj.get("ID")
            payload = {k: v for k, v in obj.items() if k not in ("id", "ID")}
            if item_id and isinstance(payload, dict):
                return str(item_id), payload
    except Exception:
        pass
    # Try the "ID:{...}" pattern
    try:
        # split on the first occurrence of ":{"
        idx = s.find(":{")
        if idx == -1:
            idx = s.find(": {")
        if idx != -1:
            item_id = s[:idx].strip()
            json_part = s[idx+1:].strip()
            payload = json.loads(json_part)
            if item_id and isinstance(payload, dict):
                return item_id, payload
    except Exception:
        pass
    return None, None
#
#@tool
#def web_search(query: str) -> str:
#    """
#    Search the internet for information about a given query.
#    
#    Args:
#        query (str): The search query to look up online.
#    
#    Returns:
#        str: Search results and relevant information from the web.
#    """
#    return tool.web_search()


@tool
def run_python(code: str) -> str:
    """
    Execute Python code using the Python interpreter.
    
    Args:
        code (str): The Python code to execute.
    
    Returns:
        str: The output from executing the Python code, including stdout and stderr.
    """
    return get_output(run_command(f"python3 -c '{code}'"))


@tool
def get_v8_path() -> str:
    """
    Get the V8 source code directory

    Args:

    Returns:
        str: The V8 source code directory.
    """
    return V8_PATH

@tool 
def get_realpath(path: str) -> str:
    """
    Get the realpath of a given path

    Args:
        path (str): The path to get the realpath of.
    Returns:
        str: The realpath of the given path.
    """
    return get_output(run_command(f"realpath {path}"))

@tool
def tree(options: str = "") -> str:
    """
    Display directory structure using tree command to explore the v8 code base layout. 
    command structure: cd {V8_PATH} && tree {options}

    Args:
        options (str): Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix
    
    Returns:
        str: Tree structure showing directories and files in the v8 code base.
    """
    return get_output(run_command(f"cd {V8_PATH} && tree {options}"))

@tool
def ripgrep(pattern: str, options: str = "") -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
    command: cd {V8_PATH} && rg {options} '{pattern}'
    Args:
        pattern (str): The text or regular expression pattern to search for.
            Example: `"TODO"` → searches for the string "TODO" in files.

        options (str): Additional ripgrep command-line options.
            You can use any of the following commonly used flags:

            --files: List all files that would be searched, without searching inside them. 
                Example: `rg --files src/` → lists all files under `src/`.

            --type: Limit search to specific file types. 
                    Example: `rg --type py "def " src/` → search only Python files.

            --glob: Include or exclude paths by glob pattern. 
                    Example: `rg --glob '!tests/*' "<pattern>"` → skip `tests` folder.

            --ignore-case: Match text case-insensitively. 
                        Example: `rg --ignore-case "error"` → matches `Error`, `ERROR`, etc.

            --no-heading: Suppress file name headings in results. 
                        Example: `rg --no-heading "main"` → cleaner, machine-parsable output.

            --line-number: Show line numbers in matches. 
                        Example: `rg --line-number "main"` → outputs `file:line:match`.

            --vimgrep: Output in `file:line:column:match` format for easy parsing. 
                    Example: `rg --vimgrep "init"` → structured grep-like output.

            --json: Emit results as structured JSON. 
                    Example: `rg --json "<pattern>"` → machine-readable output for parsing.

            --max-depth: Limit recursion depth when searching directories. 
                        Example: `rg --max-depth 2 "class"` → search only two levels deep.
            --context=NUM: Displays NUM lines of context both before and after each match.
                        Example: `rg --context=2 "<pattern>"` → shows 2 lines of context before and after each match.
    Returns:
        str: Search results showing matching lines with context.
    """
    return get_output(run_command(f"cd {V8_PATH} && rg {options} '{pattern}'"))

@tool
def fuzzy_finder(pattern: str, options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching.

    command: cd {V8_PATH} && fzf {options} '{pattern}'
    Args:
        pattern (str): The search pattern to match against files and content.
        options (str): Additional fzf command-line options:
            --filter: Run non-interactively; outputs only matching lines. 
                  Example: `ls | fzf --filter .py` → lists only Python files.

            --exact: Match the query exactly (not fuzzily). 
                    Example: `echo "main.c\nmain.cpp" | fzf --exact --filter main.c` → returns only `main.c`.

            --delimiter: Define field separator for structured input. 
                        Example: `cat results.txt | fzf --delimiter : --nth 1` → searches only filenames in `file:line:match`.

            --nth: Limit searchable fields to specific columns. 
                Example: `ps aux | fzf --nth 2` → searches only in the command field.

            --bind: Map keys or events to actions (e.g. reload, execute). 
                    Example: `fzf --bind "enter:execute(cat {V8_PATH}/{{}})"` → runs `cat` on selected file.
    Returns:
        str: Fuzzy search results showing files and content that approximately match the pattern.
    """
    return get_output(run_command(f"cd {V8_PATH} && fzf {options} '{pattern}'"))

@tool
def lift_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to lift a FuzzIL protobuf to a JavaScript program

    Args:
        target (str): The path to the target FuzzIL program identified by .fzil to be lifted to JS

    Returns:
        str: The lifted JS program from the given FuzzIL
    """
    return get_output(run_command(f"{FUZZILLI_TOOL_BIN} --liftToFuzzIL {target}"))

@tool
def compile_js_to_fuzzil(target: str) -> str:
    """
    Use FuzzILTool to compile a JavaScript program to a FuzzIl program (requires Node.js)

    Args:
        target (str): The path to the the JavaScript program to compile to FuzzIL

    Returns:
        str: The compiled FuzzIL program the given JS program
    """
    return get_output(run_command(f"{FUZZILLI_TOOL_BIN} --compile {target}"))

@tool 
def run_d8(target: str, options: str = "") -> str:
    """
    Run the target program using d8 to test for syntactical correctness
    and test for coverage. 

    Args:
        target (str): The path to the JavaScript program to run with d8.
        options (str): Additional d8 command-line options:
            --print-maglev-code (print maglev code)
            --trace-maglev-graph-building (trace maglev graph building)
            --print-maglev-graph (print the final maglev graph)
            --print-maglev-graphs (print maglev graph across all phases)
            --maglev-stats (print Maglev statistics)
            --jit-fuzzing (Set JIT tiering thresholds suitable for JIT fuzzing)
            --print-bytecode (print bytecode generated by ignition interpreter)
            --trace-turbo (trace generated TurboFan IR)
            --trace-turbo-path (directory to dump generated TurboFan IR to) 
                Ex: --trace-turbo-path=/tmp/turbofan_ir
            --trace-turbo-graph (trace generated TurboFan graphs)
            --turbo-stats (print TurboFan statistics)
            --trace-wasm-compiler (trace compiling of wasm code)
            --trace-wasm (trace wasm function calls)

            AT ANY POINT IN TIME YOU CAN ONLY PICK UP TO 4 OF THESE OPTIONS.

            WHENEVER --trace-turbo-graph is passed MAKE SURE --trace-turbo-path is ALSO passed in
            IF --trace-turbo-path is passed, MAKE SURE the output directory is /tmp/fog-d8-records/{target}

    Returns:
        str: The output from running the JavaScript program with d8.
    """ 
    completed_process = run_command(f"{V8_PATH}/out/fuzzbuild/d8 {target} {options}")
    if not completed_process:
        return

    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)

    with open(f"{OUTPUT_DIRECTORY}/{target}.out", "w") as file:
        file.write(completed_process.stdout or "")

    with open(f"{OUTPUT_DIRECTORY}/{target}.err", "w") as file:
        file.write(completed_process.stderr or "")


@tool
def search_js_file_name_by_pattern(pattern: str) -> str:
    """
    Search the regressions.json file for a given pattern and return the file names that match the pattern
    
    Args:
        pattern (str): The pattern to search for in the regressions.json file
    Returns:
        str: The file names that match the pattern
    """
    data = _load_regressions_once()
    found = []

    for key, value in data.items():
        if pattern.lower() in key.lower():
            found.append(key)
    if found:
        return "\n".join(found)
    else:
        return "No results found"




@tool
def get_js_entry_data_by_name(file_name: str) -> str:
    """
    Get the entry data for a given JS file name from the regressions.json file

    Args:
        file_name (str): The name of the JS file to get the entry data for

    Returns:
        str: The entry data for the given JS file
    """
    data = _load_regressions_once()
    return json.dumps(data.get(file_name, {})) if data.get(file_name) else "No results found for " + file_name




@tool
def search_regex_js(regex: str) -> str:
    """
    Search the regressions.json JS files for a given regex (as a real regex pattern),
    and return matching JS code snippets (with file names).

    Args:
        regex (str): The regex pattern to search for in the regressions.json JS files.
    Returns:
        str: The results of the regex search, or "No matches found".
    """
    start_time = time.time()
    pattern = re.compile(regex, re.MULTILINE)
    results = []
    data = _load_regressions_once()
    for key, value in data.items():
        js_code = value.get("js", "")
        if pattern.search(js_code):
            results.append(f"this is js code for {key}\n{js_code}\n")
    if results:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_js")
        return "\n".join(results)
    else:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_js")
        return "No matches found"

@tool
def search_regex_fuzzilli(regex: str) -> str:
    """
    Search the regressions.json Fuzzilli files for a given regex (as a real regex pattern),
    and return matching Fuzzilli code snippets (with file names).
    
    Args:
        regex (str): The regex pattern to search for in the regressions.json Fuzzilli files.
    Returns:
        str: The results of the regex search, or "No matches found".
    """
    start_time = time.time()
    pattern = re.compile(regex, re.MULTILINE)
    results = []
    data = _load_regressions_once()
    for key, value in data.items():
        fuzzilli_code = value.get("Fuzzilli", "")
        if pattern.search(fuzzilli_code):
            results.append(f"this is fuzzilli code for {key}\n{fuzzilli_code}\n")
    if results:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_fuzzilli")
        return "\n".join(results)
    else:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_fuzzilli")
        return "No matches found"


@tool
def search_regex_execution_data(regex: str) -> str:
    """
    Search the regressions.json execution data files for a given regex (as a real regex pattern),
    and return matching execution data snippets (with file names).
    
    Args:
        regex (str): The regex pattern to search for in the regressions.json execution data files.
    Returns:
        str: The results of the regex search, or "No matches found".
    """
    start_time = time.time()
    pattern = re.compile(regex, re.MULTILINE)
    results = []
    data = _load_regressions_once()
    for key, value in data.items():
        execution_data = value.get("execution_data", "")
        if pattern.search(execution_data):
            results.append(f"this is execution data for {key}\n{execution_data}\n")
    if results:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_execution_data")
        return "\n".join(results)
    else:
        end_time = time.time()
        print(f"Time taken: {end_time - start_time} seconds for search_regex_execution_data")
        return "No matches found"

@tool
def get_random_entry_data() -> str:
    """
    Get a random entry data from the regressions.json file
    
    Returns:
        str: The random entry data
    """
    data = _load_regressions_once()
    key = random.choice(list(data.keys()))
    return "this is entry data for " + key + "\n" + json.dumps(data[key])

@tool 
def simliar_js_code(JS_File_Name: str) -> str:
    """
    Find the most similar JS code to the given JS code
    
    Args:
        JS_File_Name (str): The name of the JS file/key to find the most similar code to
    Returns:
        str: The most similar JS code
    """
    data = _load_regressions_once()
    simlair_js_code = []
    for key, value in data.items():
        if key == JS_File_Name:
            continue
        fuzz_score = fuzz.ratio(data[JS_File_Name]["js"], value["js"])
        if fuzz_score > 80: # 80% similarity
            simlair_js_code.append((key, fuzz_score))
    simlair_js_code.sort(key=lambda x: x[1], reverse=True)
    return "the most similar JS code to " + JS_File_Name + " are " + str(simlair_js_code)

@tool 
def simliar_fuzzilli_code(JS_File_Name: str) -> str:
    """
    Find the most similar Fuzzilli code to the given Fuzzilli code
    
    Args:
        JS_File_Name (str): The name of the JS file/key to find the most similar Fuzzilli code to
    Returns:
        str: The most similar Fuzzilli code
    """
    data = _load_regressions_once()
    simlair_fuzzilli_code = []
    for key, value in data.items():
        if key == JS_File_Name:
            continue
        fuzz_score = fuzz.ratio(data[JS_File_Name]["Fuzzilli"], value["Fuzzilli"])
        if fuzz_score > 80: # 80% similarity
            simlair_fuzzilli_code.append((key, fuzz_score))
    simlair_fuzzilli_code.sort(key=lambda x: x[1], reverse=True)
    return "the most similar Fuzzilli code to " + JS_File_Name + " are " + str(simlair_fuzzilli_code)

@tool
def simliar_execution_data(JS_File_Name: str) -> str:
    """
    Find the most similar execution data to the given execution data
    
    Args:
        JS_File_Name (str): The name of the JS file/key to find the most similar execution data to
    Returns:
        str: The most similar execution data
    """
    data = _load_regressions_once()
    simlair_execution_data = []
    for key, value in data.items():
        if key == JS_File_Name:
            continue
        fuzz_score = fuzz.ratio(data[JS_File_Name]["execution_data"], value["execution_data"])
        if fuzz_score > 60: # 60% similarity
            simlair_execution_data.append((key, fuzz_score))
    simlair_execution_data.sort(key=lambda x: x[1], reverse=True)
    return "the most similar execution data to " + JS_File_Name + " are " + str(simlair_execution_data)


@tool
def get_all_js_file_names() -> str:
    """
    Get all JS file names from the regressions.json file
    
    Returns:
        str: All JS file names
    """
    data = _load_regressions_once()
    return list(data.keys())


@tool
def get_js_file_by_name(file_name: str) -> str: 
    """
    Get a JS file by name from the regressions.json file
    
    Args:
        file_name (str): The name of the JS file to get
    Returns:
        str: The JS file
    """
    data = _load_regressions_once()
    entry = data.get(file_name)
    if entry is None:
        return "No results found"
    return "this is data for " + file_name + "\n" + json.dumps(entry)


# =============================
# templates.json query helpers
# =============================

@tool
def search_template_file_json(pattern: str, return_topic: int = 0) -> str:
    """
    Search templates.json for a given key pattern.

    Args:
        pattern (str): Substring to match against template key.
        return_topic (int): 0 full entry, 1 ProgramTemplateSwift, 2 ProgramTemplateFuzzIL, 3 ProgramTemplateName
    """
    data = _load_templates_once()
    for key, value in data.items():
        if pattern in key:
            if return_topic == 0:
                return json.dumps(value)
            elif return_topic == 1:
                return value.get("ProgramTemplateSwift", "")
            elif return_topic == 2:
                return value.get("ProgramTemplateFuzzIL", "")
            elif return_topic == 3:
                return value.get("ProgramTemplateName", "")
    return "No results found"

@tool
def search_regex_template_swift(regex: str) -> str:
    """

    Regex search over ProgramTemplateSwift in templates.json.
    Returns matching snippets with template names.
    Args:
        regex (str): The regex pattern to search for in the templates.json ProgramTemplateSwift files.
    Returns:
        str: The results of the regex search, or "No matches found".
    """
    start_time = time.time()
    pattern = re.compile(regex, re.MULTILINE)
    results = []
    data = _load_templates_once()
    for key, value in data.items():
        txt = value.get("ProgramTemplateSwift", "")
        if pattern.search(txt):
            results.append(f"this is swift template for {key}\n{txt}\n")
    end_time = time.time()
    print(f"Time taken: {end_time - start_time} seconds for search_regex_template_swift ")
    return "\n".join(results) if results else "No matches found"

@tool
def search_regex_template_fuzzil(regex: str) -> str:
    """
    Regex search over ProgramTemplateFuzzIL in templates.json.
    Returns matching snippets with template names.
    
    Args:
        regex (str): The regex pattern to search for in the templates.json ProgramTemplateFuzzIL fields.
    Returns:
        str: The results of the regex search, or "No matches found".
    """
    pattern = re.compile(regex, re.MULTILINE)
    results = []
    data = _load_templates_once()
    for key, value in data.items():
        txt = value.get("ProgramTemplateFuzzIL", "")
        if pattern.search(txt):
            results.append(f"this is fuzzil template for {key}\n{txt}\n")
    return "\n".join(results) if results else "No matches found"

@tool
def get_random_template_swift() -> str:
    """Return a random ProgramTemplateSwift from templates.json."""
    data = _load_templates_once()
    keys = list(data.keys())
    if not keys:
        return "No matches found"
    name = random.choice(keys)
    return "this is swift template for " + name + "\n" + data[name].get("ProgramTemplateSwift", "")

@tool
def get_random_template_fuzzil() -> str:
    """Return a random ProgramTemplateFuzzIL from templates.json."""
    data = _load_templates_once()
    keys = list(data.keys())
    if not keys:
        return "No matches found"
    name = random.choice(keys)
    return "this is fuzzil template for " + name + "\n" + data[name].get("ProgramTemplateFuzzIL", "")

@tool
def similar_template_swift(template_name: str) -> str:
    """
    Find similar ProgramTemplateSwift entries to the given template key.
    
    Args:
        template_name (str): The template key to compare against.
    Returns:
        str: A list of similar template names with scores, or a no-results message.
    """
    data = _load_templates_once()
    if template_name not in data:
        return "No results found"
    base = data[template_name].get("ProgramTemplateSwift", "")
    sims = []
    for key, value in data.items():
        if key == template_name:
            continue
        score = fuzz.ratio(base, value.get("ProgramTemplateSwift", ""))
        if score > 80:
            sims.append((key, score))
    sims.sort(key=lambda x: x[1], reverse=True)
    return "the most similar Swift templates to " + template_name + " are " + str(sims)

@tool
def similar_template_fuzzil(template_name: str) -> str:
    """
    Find similar ProgramTemplateFuzzIL entries to the given template key.
    
    Args:
        template_name (str): The template key to compare against.
    Returns:
        str: A list of similar template names with scores, or a no-results message.
    """
    data = _load_templates_once()
    if template_name not in data:
        return "No results found"
    base = data[template_name].get("ProgramTemplateFuzzIL", "")
    sims = []
    for key, value in data.items():
        if key == template_name:
            continue
        score = fuzz.ratio(base, value.get("ProgramTemplateFuzzIL", ""))
        if score > 80:
            sims.append((key, score))
    sims.sort(key=lambda x: x[1], reverse=True)
    return "the most similar FuzzIL templates to " + template_name + " are " + str(sims)

@tool
def get_all_template_names() -> str:
    """List all template keys in templates.json."""
    data = _load_templates_once()
    return list(data.keys())

@tool
def get_template_by_name(name: str) -> str:
    """
    Get full template entry by key.
    
    Args:
        name (str): The template key to retrieve.
    Returns:
        str: The full template entry as a JSON string, or a no-results message.
    """
    data = _load_templates_once()
    entry = data.get(name)
    if entry is None:
        return "No results found"
    return "this is template data for " + name + "\n" + json.dumps(entry)


@tool 
def write_rag_db_id(rag_db_id: str, data: str) -> str:
    r"""
    Write data to the RAG database
    
    Args:
        rag_db_id (str): The ID of the RAG database to write to
        data (str): The data to write to the RAG database in the following format:
            ID:{
                body: <CODE SNIPPET>
                context: <OTHER IDS THAT ARE RELATED TO THIS ONE>
                explanation: <EXPLANATION OF THE CODE SNIPPET>
                file_line: exmaple.cc:10
            }
    Returns:
        str: The result of the write operation
    """
    db = _load_rag_db(rag_db_id)
    item_id, payload = _parse_rag_entry(data)
    if not item_id or not isinstance(payload, dict):
        return "ERROR: data must be JSON with 'id' or in 'ID:{...}' format"
    db[item_id] = payload
    _save_rag_db(rag_db_id, db)
    return f"OK: wrote {item_id} to {rag_db_id}"

@tool
def read_rag_db_id(rag_db_id: str) -> str:
    """
    Read data from the RAG database
    
    Args:
        rag_db_id (str): The ID of the RAG database to read from
    Returns:
        str: The data from the RAG database
    """
    db = _load_rag_db(rag_db_id)
    return json.dumps(db)

@tool
def init_rag_db(rag_db_id: str) -> str:
    """
    Initialize a non-vector RAG database identified by rag_db_id.
    Creates an empty JSON file under rag_db/<rag_db_id>.json if missing.
    
    Args:
        rag_db_id (str): The RAG database identifier to initialize.
    Returns:
        str: A confirmation message with the initialized path.
    """
    _ensure_rag_db_initialized(rag_db_id)
    return f"OK: initialized RAG DB {rag_db_id} at {_rag_db_path(rag_db_id)}"

