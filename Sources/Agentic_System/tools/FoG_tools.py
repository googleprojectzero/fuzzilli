from smolagents import tool
from tools.common_tools import * #

FUZZILTOOL_BIN = "/usr/share/vrigatoni/fuzzillai/.build/x86_64-unknown-linux-gnu/debug/FuzzILTool"
OUTPUT_DIRECTORY = "/tmp/fog-d8-records" 

@tool
def lookup(query: str) -> str:
    """
    Search the internet for information about a given query.
    
    Args:
        query (str): The search query to look up online.
    
    Returns:
        str: Search results and relevant information from the web.
    """
    return get_output(run_command(f"curl -s 'https://api.duckduckgo.com/?q={query}&format=json&no_html=1&skip_disambig=1'"))


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
def tree(directory: str = ".", options: str = "") -> str:
    """
    Display directory structure using tree command to explore project layout.
    
    Args:
        directory: The directory to explore. Defaults to current directory ".".
        options: Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix
    
    Returns:
        str: Tree structure showing directories and files in the specified path.
    """
    return get_output(run_command(f"tree {options} {directory}"))

@tool
def ripgrep(pattern: str, options: str = "") -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
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
    return get_output(run_command(f"rg -C {options} '{pattern}'"))

@tool
def fuzzy_finder(pattern: str, options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching.
    
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
                    Example: `fzf --bind "enter:execute(cat {})"` → runs `cat` on selected file.
    
    Returns:
        str: Fuzzy search results showing files and content that approximately match the pattern.
    """
    return get_output(run_command(f"fzf {options} '{pattern}'"))

@tool
def lift_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to lift a FuzzIL protobuf to a JavaScript program

    Args:
        target (str): The path to the target FuzzIL program identified by .fzil to be lifted to JS

    Returns:
        str: The lifted JS program from the given FuzzIL
    """
    return get_output(run_command(f"{FUZZILTOOL_BIN} --liftToFuzzIL {target}"))

@tool
def compile_js_to_fuzzil(target: str) -> str:
    """
    Use FuzzILTool to compile a JavaScript program to a FuzzIl program (requires Node.js)

    Args:
        target (str): The path to the the JavaScript program to compile to FuzzIL

    Returns:
        str: The compiled FuzzIL program the given JS program
    """
    return get_output(run_command(f"{FUZZILTOOL_BIN} --compile {target}"))

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
    completed_process = run_command(f"/usr/share/vrigatoni/fuzzillai/v8/v8/out/fuzzbuild/d8 {target} {options}")
    if not completed_process:
        return

    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)

    with open(f"{OUTPUT_DIRECTORY}/{target}.out", "w") as file:
        file.write(completed_process.stdout or "")

    with open(f"{OUTPUT_DIRECTORY}/{target}.err", "w") as file:
        file.write(completed_process.stderr or "")