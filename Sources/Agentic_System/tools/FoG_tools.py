from smolagents import tool
from openai import OpenAI
from tools.common_tools import * 
from fuzzywuzzy import fuzz
from pathlib import Path
from typing_extensions import Literal

import json
import os
import subprocess
import re
import random
import time

# FUZZILTOOL_BIN = f"/usr/share/vrigatoni/fuzzillai/.build/x86_64-unknown-linux-gnu/debug/FuzzILTool"
OUTPUT_DIRECTORY = "/tmp/fog-d8-records" 
RAG_DB_DIR = (Path(__file__).parent.parent / "rag_db").resolve()

GENERATED_TEMPLATE_DIR = f"{FUZZILLI_PATH}/Sources/Agentic_System/generated_templates/"
try:
    os.makedirs(GENERATED_TEMPLATE_DIR)
except FileExistsError:
    pass

# Cached regressions.json data to avoid reloading on every tool call
_REGRESSIONS_PATH = (Path(__file__).parent.parent / "regressions.json").resolve()
_REGRESSIONS_CACHE = None
_TEMPLATES_PATH = (Path(__file__).parent.parent / "templates" / "templates.json").resolve()
_TEMPLATES_CACHE = None


RUNTIME_DB_IDS = []


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


@tool
def run_python(code: str) -> str:
    """
    Execute Python code using the Python interpreter.
    
    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search
    
    Args:
        code (str): The Python code to execute.
    
    Returns:
        str: The output from executing the Python code, including stdout and stderr.
    """
    return get_output(run_command(f"python3 -c '{code}' | head -n 1000"))


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

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    Args:
        path (str): The path to get the realpath of.
    Returns:
        str: The realpath of the given path.
    """
    return get_output(run_command(f"cd {V8_PATH} && realpath {path}"))


@tool
def tree(options: str = "") -> str:
    """
    Display directory structure using tree command to explore the v8 code base layout. 
    command structure: cd {V8_PATH} && tree {options}. 

    V8_PATH already points to the `src/` directory, DO NOT ADD `src/` to your arguments —  run `tree .` instead.

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search
    MAKE SURE THE ARGUMENTS TO `options` FOLLOW THE DEFINED FORMAT.

    Args:
        options (str): Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix
            PATH: Prefer '.' or an absolute path. If you pass a relative like 'maglev/', it must exist under V8_PATH.
    
    Returns:
        str: Tree structure showing directories and files in the v8 code base.
    """
    # If a trailing non-flag token looks like a path but does not exist under V8_PATH, fallback to '.'
    opts = options or ""
    parts = opts.split()
    if parts:
        last = parts[-1]
        if not last.startswith("-"):
            candidate = os.path.join(V8_PATH, last)
            if not os.path.isdir(candidate):
                parts[-1] = "."
                opts = " ".join(parts)
    final_opts = opts if opts else "-L 2 -f ."
    return get_output(run_command(f"cd {V8_PATH} && tree {final_opts} | head -n 1000"))


@tool
def ripgrep(pattern: str, options: str = "") -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search
    
    command: cd {V8_PATH} && rg {options} '{pattern}' [paths...]
    Args:
        pattern (str): The text or regular expression pattern to search for.
            Example: `"TODO"` → searches for the string "TODO" in files.

        options (str): Additional ripgrep command-line options and paths.
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
    valid, error = is_valid_regex(pattern)
    if not valid:
        return f"Invalid regex passed in as pattern with error: {error}"

    #debugging
    print(f"VALID REGEX FOUND, IS VALID? {valid}") 

    if not options:
        return get_output(run_command(f"cd {V8_PATH} && rg '{pattern}' | head -n 10000"))
    
    parts = options.split()
    flags = []
    
    i = 0
    while i < len(parts):
        part = parts[i]
        if part.startswith('-'):
            flags.append(part)
            if part in ['--type', '--glob'] and i + 1 < len(parts):
                next_part = parts[i + 1]
                if not next_part.startswith('-') and not next_part.startswith('v8/'):
                    i += 1
                    flags.append(parts[i])
        else:
            flags.append(part)
        i += 1
    
    flags_str = ' '.join(flags) if flags else ''

    cmd = f"cd {V8_PATH} && rg {flags_str} '{pattern}' | head -n 1000"
    
    return get_output(run_command(cmd))


@tool
def fuzzy_finder(pattern: str, options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching.

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    command: cd {V8_PATH} && rg --hidden --no-follow --no-ignore-vcs --files 2>/dev/null | fzf {options} '{pattern}'
    Args:
        pattern (str): The search pattern to match against files and content.
        options (str): Additional fzf command-line options:
            --filter: Run non-interactively; outputs only matching lines. 
                  Example: `ls | fzf --filter .py` → lists only Python files.

                  Notes:
                  - `--filter` must be followed immediately by the query string. Do not place other flags right after it. For example, use `--filter 'v8/src/compiler' -e` not `--filter -e v8/src/compiler`.
                  - With `--filter`, `fzf` expects input on stdin. Provide input via a producer command. Example: `rg -n 'JSLoadElement' | fzf -e --filter 'v8/src/compiler'`.

            --exact: Match the query exactly (not fuzzily). 
                    Example: `echo "main.c\nmain.cpp" | fzf --exact --filter main.c` → returns only `main.c`.

            --delimiter: Define field separator for structured input. 
                        Example: `cat results.txt | fzf --delimiter : --nth 1` → searches only filenames in `file:line:match`.

            --nth: Limit searchable fields to specific columns. 
                Example: `ps aux | fzf --nth 2` → searches only in the command field.

            --bind: Map keys or events to actions (e.g. reload, execute). 
                    Example: `fzf --bind "enter:execute(cat {V8_PATH}/{{}})"` → runs `cat` on selected file.
    Returns:
        str: Fuzzy search results showing up to 1000 files and content that approximately match the pattern.
    """
    file_list_cmd = "rg --hidden --no-follow --no-ignore-vcs --files 2>/dev/null"
    return get_output(run_command(f"cd {V8_PATH} && {file_list_cmd} | fzf {options} '{pattern}' | head -n 1000")) 


@tool
def lift_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to lift a FuzzIL protobuf to a JavaScript program

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    Args:
        target (str): The path to the target FuzzIL program identified by .fzil to be lifted to JS

    Returns:
        str: The lifted JS program from the given FuzzIL
    """
    return get_output(run_command(f"{FUZZILLI_TOOL_BIN} --liftToFuzzIL {target} | head -n 1000"))


@tool
def compile_js_to_fuzzil(target: str) -> str:
    """
    Use FuzzILTool to compile a JavaScript program to a FuzzIl program (requires Node.js)

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    Args:
        target (str): The path to the the JavaScript program to compile to FuzzIL

    Returns:
        str: The compiled FuzzIL program the given JS program
    """
    return get_output(run_command(f"{FUZZILLI_TOOL_BIN} --compile {target} | head -n 1000"))


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
    completed_process = run_command(f"{D8_PATH} {target} {options}")
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
def get_all_template_names_from_json() -> str:
    """List all template keys in templates.json."""
    data = _load_templates_once()
    return list(data.keys())

@tool
def get_template_from_json_by_name(name: str) -> str:
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
def write_rag_db_id(id: str, Body: str, Context: list[str], Explanation: str, FileLine: str) -> str:

# ╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
# │ Calling tool: 'write_rag_db_id' with arguments: {'id': '1', 'data': '{"id":1,"body":"BinaryOperationFeedback enum and values","context":["common/globals.h:~1443"],"explanation":"Defines BinaryOperationFeedback constants used │
# │ across feedback collection (kSignedSmall, kNumber, kString, kBigInt etc).","file_line":"src/common/globals.h:1443"}'}                                                                                                            │
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
# Observations: OK: wrote 1 to 1
# [Step 10: Duration 2.80 seconds| Input tokens: 294,624 | Output tokens: 2,411
    r"""
    Write data to the RAG database

    PLEASE MAKE SURE YOU HAVE VERY DETAILED EXPLANATIONS AND 
    MAKE SURE THE BODY IS VERY DETAILED AND THE CONTEXT IS ACCURATE.
        OR ELSE I WILL KILL MYSELF.
    
    Args:
        id (str): The ID of the RAG database to write to, should be in the format "jsadd_pipeline"
        Body (str): The body of the RAG database entry, THIS SHOULD BE THE CODE INTERESTING AND DETAILED.
        Context (list[str]): The context of IDs related to the body of the RAG database entry.
        Explanation (str): The explanation of why this is interesting and why it should be added to the RAG database.
        FileLine (str): The file lines related to the body of the RAG database entry, THIS SHOULD BE THE FILE LINES RELATED TO THE BODY.
    Returns:
        str: The result of the write operation
    """
    data = {
        "body": Body,
        "context": Context,
        "explanation": Explanation,
        "file_line": FileLine
    }
    _save_rag_db(id, data)
    RUNTIME_DB_IDS.append(id)
    return f"OK: wrote {id} to {_rag_db_path(id)}"


@tool
def read_rag_db_id(id: str) -> str:
    """
    Read data from the RAG database
    
    Args:
        id (str): The ID of the RAG database to read from. Should be in either "id" OR "ID:{...}" format.
    Returns:
        str: The data from the RAG database
    """
    db = _load_rag_db(id)
    return json.dumps(db)

# @tool
# def init_rag_db(id: str) -> str:
#     """
#     Initialize a non-vector RAG database identified by rag_db_id.
#     Creates an empty JSON file under rag_db/<rag_db_id>.json if missing.
    
#     Args:
#         id (str): The RAG database identifier to initialize. Should be in either "id" OR "ID:{...}" format.
#     Returns:
#         str: A confirmation message with the initialized path.
#     """
#     _ensure_rag_db_initialized(id)
#     return f"OK: initialized RAG DB {id} at {_rag_db_path(id)}"


@tool 
def get_runtime_db_ids() -> str:
    """
    Get the runtime DB IDs
    
    Returns:
        str: The runtime DB IDs
    """
    return json.dumps(RUNTIME_DB_IDS)


@tool 
def read_program_template_input_file() -> str:
    """
    Read a program template input file
    
    Returns:
        str: The content of the program template file
    """
    program_templates_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplates.swift")
    return get_output(run_command(f"cat '{program_templates_file}'"))


@tool
def list_program_templates() -> str:
    """
    Lists all the existing program templates in ProgramTemplates.swift

    Returns:
        str: List of all the program templates in ProgramTemplates.swift. Duplicates are included for validation purposes.
    """
    program_templates_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplates.swift")
    
    if not os.path.exists(program_templates_file):
        return f"Error: ProgramTemplates.swift not found at {program_templates_file}"
    
    try:
        with open(program_templates_file, 'r') as f:
            content = f.read()
    except Exception as e:
        return f"Error reading ProgramTemplates.swift: {e}"

    pattern = r'(?:WasmProgramTemplate|ProgramTemplate)\s*\("([^"]+)"\)'

    program_templates = re.findall(pattern, content)
    
    #TODO: can also double check against ProgramTemplateWeights.swift for the found program_templates
    return f"Found program templates: {program_templates}"


# TODO: fix, this seems to remove the ","" from "JSONFUzzer" when there's only one program template
# TODO: potentially separate writing/removing templates and weights so in the case that the template exists but the weight doesn't, we don't error and can fix the state
@tool
def remove_program_template(program_template: str) -> str:
    """
    Remove a program template from the ProgramTemplates.swift file.
    Remove the template from the ProgramTemplates array before the closing bracket.

    Args:
        program_template (str): The name of the swift program template to remove (must be a program template that's been added dynamically by write_program_template)
    Returns:
        str: whether removing the program template was successfull or failed 
    """
    default_program_templates = ['Codegen100', 'Codegen50', 'WasmCodegen50', 'WasmCodegen100', 'MixedJsAndWasm1', 'MixedJsAndWasm2', 'JSPI', 
'ThrowInWasmCatchInJS', 'WasmReturnCalls', 'JIT1Function', 'JIT2Functions', 'JITTrickyFunction', 'JSONFuzzer']

    if program_template in default_program_templates:
        return f"Do not remove a 'default' program template! Here are the defaults: {default_program_template}"

    program_templates_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplates.swift")
    
    if not os.path.exists(program_templates_file):
        return f"Error: ProgramTemplates.swift not found at {program_templates_file}"
    
    try:
        with open(program_templates_file, 'r') as f:
            content = f.read()
    except Exception as e:
        return f"Error reading ProgramTemplates.swift: {e}"
    
    block_start_pattern = re.compile(
        r'^\s*(?:WasmProgramTemplate|ProgramTemplate)\s*\(\s*"' + re.escape(program_template) + r'"\s*\)\s*\{',
        re.MULTILINE
    )

    start_match = block_start_pattern.search(content)

    if not start_match:
        return f"Error: Program template '{program_template}' not found in file {program_templates_file} (start tag missing)."

    start_index = start_match.start()

    brace_count = 1
    end_index = -1
    for i in range(start_match.end(), len(content)):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                end_index = i
                break

    if end_index == -1:
        return f"Error: Could not find matching closing brace '}}' for template '{program_template}'."

    separator_after_match = re.search(r'^\s*,\s*', content[end_index + 1:], re.MULTILINE | re.DOTALL)

    if separator_after_match:
        end_of_block_to_remove = end_index + 1 + separator_after_match.end()
    else:
        end_of_block_to_remove = end_index + 1

    preceding_separator_match = re.search(r'^\s*,?\s*', content[:start_index][::-1], re.MULTILINE | re.DOTALL)

    if preceding_separator_match:
        start_of_block_to_remove = start_index - preceding_separator_match.end()
        #start_of_block_to_remove += (len(content[:start_index]) - len(content[:start_index].lstrip()))
    else:
        start_of_block_to_remove = start_index

    content = content[:start_of_block_to_remove] + content[end_of_block_to_remove:]

    try:
        with open(program_templates_file, 'w') as f:
            f.write(content)
        ret = f"OK: Successfully removed program template {program_template} from {program_templates_file}"
    except Exception as e:
        return f"Error writing to ProgramTemplates.swift: {e}"

    # remove from ProgramTemplateWeights.swift below
    program_template_weights_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplateWeights.swift")
    
    if not os.path.exists(program_template_weights_file):
        return f"Error: ProgramTemplateWeights.swift not found at {program_template_weights_file}"

    try:
        with open(program_template_weights_file, 'r') as f:
            content_weight = f.read()
    except Exception as e:
        return f"Error reading ProgramTemplateWeights.swift: {e}"

    weight_removal_pattern = re.compile(
        r'^\s*"' + re.escape(program_template) + r'"\s*:\s*\d+\s*,\s*$',
        re.MULTILINE
    )
    content_weight = weight_removal_pattern.sub('', content_weight)
    content_weight = re.sub(r'\n\s*\n', '\n', content_weight)

    try:
        with open(program_template_weights_file, 'w') as f:
            f.write(content_weight)
        return ret + f"\nOK: Successfully removed program template {program_template} weight from {program_template_weights_file}"
    except Exception as e:
        return f"Error writing to ProgramTemplateWeights.swift: {e}"


# TODO: potentially separate writing/removing templates and weights so in the case that the template exists but the weight doesn't, we don't error and can fix the state
@tool 
def write_program_template(program_template: str) -> str:
    """
    Write a program template to the ProgramTemplates.swift file.
    Adds the template to the ProgramTemplates array before the closing bracket.
    
    Args:
        program_template (str): The Swift program template code to add (must be a complete ProgramTemplate or WasmProgramTemplate entry)
    Returns:
        str: The result of the write operation
    """
    program_templates_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplates.swift")
    
    if not os.path.exists(program_templates_file):
        return f"Error: ProgramTemplates.swift not found at {program_templates_file}"
    
    try:
        with open(program_templates_file, 'r') as f:
            content = f.read()
    except Exception as e:
        return f"Error reading ProgramTemplates.swift: {e}"
    
    content = content.rstrip()
    if not content.endswith(']'):
        return "Error: ProgramTemplates.swift does not end with closing bracket"
    
    template_code = program_template.strip()
    if not template_code.endswith(','):
        template_code += ','
    
    content = content[:-1] + '\n\n    ' + template_code + '\n]'

    try:
        with open(program_templates_file, 'w') as f:
            f.write(content)
        ret = f"OK: Successfully wrote program template to {program_templates_file}"
    except Exception as e:
        return f"Error writing to ProgramTemplates.swift: {e}"

    # update program template weights below
    program_template_weights_file = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplateWeights.swift")

    template_name_pattern = r'(?:WasmProgramTemplate|ProgramTemplate)\s*\("([^"]+)"\)'
    name_match = re.search(template_name_pattern, program_template)
    if not name_match:
        return f"Error: Could not extract template name to update weights."
    template_name = name_match.group(1)

    if not os.path.exists(program_template_weights_file):
        return f"Error: ProgramTemplateWeights.swift not found at {program_template_weights_file}"
    
    try:
        with open(program_template_weights_file, 'r') as f:
            content_weights = f.read()
    except Exception as e:
        return f"Error reading ProgramTemplates.swift: {e}"
    
    content_weights = content_weights.rstrip()
    if not content_weights.endswith(']'):
        return "Error: ProgramTemplates.swift does not end with closing bracket"

    # default weight is 2. maybe update this?
    new_weight_entry = f'\n\t"{template_name}": 2,'

    content_weights = content_weights[:-1] + new_weight_entry + '\n]'

    try:
        with open(program_template_weights_file, 'w') as f:
            f.write(content_weights)
        return ret + f"\nOK: Successfully wrote program template weight to {program_template_weights_file}"
    except Exception as e:
        return f"Error writing to ProgramTemplateWeights.swift: {e}"

@tool
def edit_template_by_regex( 
    search_pattern: str, 
    new_content: str, 
    start_line: int = None, 
    end_line: int = None,
    mode: Literal["replace", "insert_after", "insert_before"] = "replace"
) -> str:
    """
    Performs precise, line-based editing of ProgramTemplates.swift using a regular expression
    to locate the target insertion or replacement point, optionally limited by line numbers.

    Args:
        search_pattern (str): The regex pattern to find the target line. The pattern
                              must match the ENTIRE line for 'replace' mode, or any part
                              of the line for 'insert_after'/'insert_before' modes.
        new_content (str): The content to be inserted or replaced.
        mode (Literal["replace", "insert_after", "insert_before"]):
            - 'replace': Replace the line that matches the search_pattern with 'new_content'.
            - 'insert_after': Insert 'new_content' immediately after the matching line.
            - 'insert_before': Insert 'new_content' immediately before the matching line.
        start_line (int): The 1-based line number to start the search from (inclusive).
        end_line (int): The 1-based line number to end the search at (inclusive).

    Returns:
        str: A status message indicating success or failure in editing the ProgramTemplates.swift file.
    """
    valid, error = is_valid_regex(search_pattern)
    if not valid:
        return f"Invalid regex passed in as pattern with error: {error}"

    # TODO: could check these line numbers fall within the range for ProgramTemplates.swift and give more verbose feedback
    if not (start_line and end_line):
        return "Must pass in a start_line AND end_line to limit the scope of your replacements."

    filepath = os.path.join(SWIFT_PATH, "CodeGen", "ProgramTemplates.swift")
    if not os.path.exists(filepath):
        return f"Error: File not found at {filepath}"

    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        return f"Error reading file {filepath}: {e}"

    # Pattern compilation is already checked by is_valid_regex, but kept for strictness
    try:
        pattern = re.compile(search_pattern)
    except re.error as e:
        return f"Error: Internal regex compilation failed: {e}"

    new_lines = []
    found_match = False
    match_count = 0

    if new_content and not new_content.endswith('\n'):
        new_content += '\n'

    for i, line in enumerate(lines):
        # Line numbers are 1-based for the user/agent
        line_number = i + 1 
        is_in_range = True

        if start_line is not None and line_number < start_line:
            is_in_range = False
        if end_line is not None and line_number > end_line:
            is_in_range = False 
        
        if is_in_range and pattern.search(line):
            found_match = True
            match_count += 1
            if mode == "insert_before":
                new_lines.append(new_content)
                new_lines.append(line)
            elif mode == "insert_after":
                new_lines.append(line)
                new_lines.append(new_content)
            elif mode == "replace":
                # Partial replacement: replace the matched substring with new_content.
                modified_line = pattern.sub(new_content.strip(), line)
                new_lines.append(modified_line)
        else:
            new_lines.append(line)

    if match_count == 0:
        range_str = f" in line range {start_line}-{end_line}" if start_line or end_line else ""
        return f"Error: Search pattern '{search_pattern}' not found{range_str} in {filepath}. No changes made."

    try:
        with open(filepath, 'w') as f:
            f.writelines(new_lines)
        return f"OK: Successfully updated {filepath} using mode '{mode}' and pattern '{search_pattern}'. {match_count} matches applied."
    except Exception as e:
        return f"Error writing to file {filepath}: {e}"


@tool 
def compile_program_template(template: str) -> str:
    """
    Compile a program template file to JavaScript
    
    Args:
        template (str): the name of the program template to be executed
            The available templates are located in Sources/Fuzzilli/CodeGen/ProgramTemplates.swift

    Returns:
        str: The resulting JavaScript program from the given program template and extra information

    DO NOT WORRY ABOUT fake_path IT IS SIMPLY THERE SO FUZZILTOOL RUNS PROPERLY. 
    fake_path DOES NOT GET USED ANYWHERE
    """
    # fake_path is passed in because FuzzILTool requires a path to run
    # use swift run to recompile ProgramTemplates.swift and check for errors
    build = run_command(f'swift run FuzzILTool --compileTemplate="{template}" fake_path')
    if build.stderr and not build.stdout:
        return f"swift build failed, likely errors with generated program template: {build.stderr}" 

    javascript = build.stdout

    # TODO: remove old program template if it failed to compile, 
    #   maybe at the end once it gets a successfull execution remove the other JS files that don't 
    #   match the successfull hash with the same program template name.
    # OR maybe let compiler read these to see the previous failers.
    path = f"{GENERATED_TEMPLATE_DIR}{template}-{hash(javascript)}.js"
    with open(path, "w") as f:
        f.write(javascript)  

    return f"Generated JavaScript from {template} template, stored at {path}, full JavaScript: {javascript}"


@tool 
def execute_program_template(template_js_path: str) -> str:
    """
    Excute a JavaScript program generated from a program template

    Args:
        template_js_path (str): The path to the given JavaScript program generated from a program template

    Returns:
        str: The result of the excuting the program template's javascript

    """
    #TODO: update D8_COMMON_FLAGS so compiler can better examine the ouput for success/get more info. Also update the STAGE 7 prompt in compiler.txt if this is done.
    d8 = run_command(f"{D8_PATH} {D8_COMMON_FLAGS} {template_js_path}")
    return f"Program execution result:\n{d8.stderr}\n{d8.stdout}"

@tool
def swift_fuzzy_finder(pattern: str, options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching in the Fuzzilli Swift codebase.

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    command: cd {SWIFT_PATH} && rg --hidden --no-follow --no-ignore-vcs --files 2>/dev/null | fzf {options} '{pattern}'
    Args:
        pattern (str): The search pattern to match against files and content.
        options (str): Additional fzf command-line options:
            --filter: Run non-interactively; outputs only matching lines. 
                  Example: `ls | fzf --filter .py` → lists only Python files.

                  Notes:
                  - `--filter` must be followed immediately by the query string. Do not place other flags right after it. For example, use `--filter 'v8/src/compiler' -e` not `--filter -e v8/src/compiler`.
                  - With `--filter`, `fzf` expects input on stdin. Provide input via a producer command. Example: `rg -n 'JSLoadElement' | fzf -e --filter 'v8/src/compiler'`.

            --exact: Match the query exactly (not fuzzily). 
                    Example: `echo "main.c\nmain.cpp" | fzf --exact --filter main.c` → returns only `main.c`.

            --delimiter: Define field separator for structured input. 
                        Example: `cat results.txt | fzf --delimiter : --nth 1` → searches only filenames in `file:line:match`.

            --nth: Limit searchable fields to specific columns. 
                Example: `ps aux | fzf --nth 2` → searches only in the command field.

            --bind: Map keys or events to actions (e.g. reload, execute). 
                    Example: `fzf --bind "enter:execute(cat {SWIFT_PATH}/{{}})"` → runs `cat` on selected file.
    Returns:
        str: Fuzzy search results showing up to 1000 files and content that approximately match the pattern.
    """
    file_list_cmd = "rg --hidden --no-follow --no-ignore-vcs --files 2>/dev/null"
    return get_output(run_command(f"cd {SWIFT_PATH} && {file_list_cmd} | fzf {options} '{pattern}' | head -n 1000")) 


@tool
def swift_tree(options: str = "") -> str:
    """
    Display directory structure using tree command to explore the Fuzzilli Swift codebase layout. 
    command structure: cd {SWIFT_PATH} && tree {options}. 

    SWIFT_PATH points to the Fuzzilli Swift source directory.

    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search
    MAKE SURE THE ARGUMENTS TO `options` FOLLOW THE DEFINED FORMAT.

    Args:
        options (str): Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix
            PATH: Prefer '.' or an absolute path. If you pass a relative path, it must exist under SWIFT_PATH.
    
    Returns:
        str: Tree structure showing directories and files in the Fuzzilli Swift codebase.
    """
    opts = options or ""
    parts = opts.split()
    if parts:
        last = parts[-1]
        if not last.startswith("-"):
            candidate = os.path.join(SWIFT_PATH, last)
            if not os.path.isdir(candidate):
                parts[-1] = "."
                opts = " ".join(parts)
    final_opts = opts if opts else "-L 2 -f ."
    return get_output(run_command(f"cd {SWIFT_PATH} && tree {final_opts} | head -n 1000"))


@tool
def swift_ripgrep(pattern: str, options: str = "") -> str:
    """
    Search for text patterns in the Fuzzilli Swift codebase using ripgrep (rg) for fast text searching.
    
    MAX OUTPUT 1000 lines, if output getting cut out please use a more specific search

    command: cd {SWIFT_PATH} && rg {options} '{pattern}' [paths...]
    Args:
        pattern (str): The text or regular expression pattern to search for.
            Example: `"TODO"` → searches for the string "TODO" in files.

        options (str): Additional ripgrep command-line options and paths.
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
    valid, error = is_valid_regex(pattern)
    if not valid:
        return f"Invalid regex passed in as pattern with error: {error}"
    
    #debugging
    print(f"VALID REGEX FOUND, IS VALID? {valid}") 

    if "ProgramTemplate" in pattern:
        resolved_path = os.path.join(SWIFT_PATH, "CodeGen")
    else:
        resolved_path = SWIFT_PATH

    if not options:
        return get_output(run_command(f"cd {resolved_path} && rg '{pattern}' | head -n 10000"))
    
    parts = options.split()
    flags = []
    
    i = 0
    while i < len(parts):
        part = parts[i]
        if part.startswith('-'):
            flags.append(part)
            if part in ['--type', '--glob'] and i + 1 < len(parts):
                next_part = parts[i + 1]
                if not next_part.startswith('-') and not next_part.startswith('v8/'):
                    i += 1
                    flags.append(parts[i])
        else:
            flags.append(part)
        i += 1
    
    flags_str = ' '.join(flags) if flags else ''

    cmd = f"cd {resolved_path} && rg '{pattern}' {flags_str} | head -n 1000"
    
    return get_output(run_command(cmd))


@tool
def swift_read_file(file_path: str, section: int = None) -> str:
    """
    Reads and returns the content of a specified text file from the Fuzzilli Swift codebase, 
    limited to 3000 lines maximum (1 section). If the file is longer, split into 3000-line sections, 
    and require specifying which section to read.

    IMPORTANT: Never call more than 3000 lines. Use get_file_size first for very large or binary files.

    Args:
        file_path (str): The full path to the file to be read. Relative paths will be resolved relative to SWIFT_PATH.
        section (int): Section of the file to read. Each section is 3000 lines. If the file has multiple sections, agent must specify which section (starting from 1).
    Returns:
        If the file is <= 3000 lines, returns its content. If more, returns only the requested section and info about total sections. If section is not specified, instruct agent to pick a section.
    """
    if file_path.startswith('Sources/') or file_path.startswith('Fuzzilli/'):
        resolved_path = os.path.join(FUZZILLI_PATH, file_path)
    elif not os.path.isabs(file_path):
        resolved_path = os.path.join(SWIFT_PATH, file_path)
    else:
        resolved_path = file_path

    line_count_result = get_output(run_command(f"wc -l '{resolved_path}'"))
    try:
        line_count = int(line_count_result.strip().split()[0])
    except Exception:
        return f"Could not determine number of lines in file. wc -l output: {line_count_result}"

    lines_per_section = 3000
    num_sections = (line_count + lines_per_section - 1) // lines_per_section

    if line_count <= lines_per_section:
        return get_output(run_command(f"cat '{resolved_path}'"))

    if section is None or section < 1 or section > num_sections:
        return (
            f"File '{file_path}' has {line_count} lines and is divided into {num_sections} sections "
            f"(each section is 3000 lines).\n"
            f"To read this file, please specify a section number between 1 and {num_sections} "
            f"using the 'section' argument."
        )

    start_line = 1 + (section - 1) * lines_per_section
    end_line = min(start_line + lines_per_section - 1, line_count)
    read_cmd = f"sed -n '{start_line},{end_line}p' '{resolved_path}'"
    content = get_output(run_command(read_cmd))
    return (
        f"Showing section {section}/{num_sections} (lines {start_line}-{end_line}) of '{file_path}':\n"
        f"{content}"
    )