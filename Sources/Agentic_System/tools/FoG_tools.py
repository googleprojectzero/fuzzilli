from smolagents import tool
from common_tools import *


@tool
def lookup(query: str) -> str:
    """
    Search the internet for information about a given query.
    
    Args:
        query (str): The search query to look up online.
    
    Returns:
        str: Search results and relevant information from the web.
    """
    return run_command(f"curl -s 'https://api.duckduckgo.com/?q={query}&format=json&no_html=1&skip_disambig=1'")


@tool
def run_python(code: str) -> str:
    """
    Execute Python code using the Python interpreter.
    
    Args:
        code (str): The Python code to execute.
    
    Returns:
        str: The output from executing the Python code, including stdout and stderr.
    """
    return run_command(f"python3 -c '{code}'")

@tool 
def get_call_graph() -> str:
    """
    Generate and search a call graph to find functions, classes, and variables by name patterns.
    
    Returns:
        str: Call graph analysis results showing relationships and matches.
    """
    return get_call_graph()

@tool
def tree(directory: str = ".", options: str = "") -> str:
    """
    Display directory structure using tree command to explore project layout.
    
    Args:
        directory: The directory to explore. Defaults to current directory ".".
        Args: Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix
    
    Returns:
        str: Tree structure showing directories and files in the specified path.
    """
    return run_command(f"tree {options} {directory}")

@tool
def ripgrep(pattern: str, options: str = "") -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
    Args:
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
    return run_command(f"rg -C {options} '{pattern}'")   

@tool
def fuzzy_finder(pattern: str, options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching.
    
    Args:
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
    return run_command(f"fzf {options} '{pattern}'")

@tool
def lift_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to lift a FuzzIL protobuf to a JavaScript program

    Args:
        target (str): The path to the target FuzzIL program identified by .fzil to be lifted to JS

    Returns:
        str: The lifted JS program from the given FuzzIL
    """
    return run_command(f"swift run FuzzILTool --liftToFuzzIL {target}")

@tool
def compile_js_to_fuzzil(target: str) -> str:
    """
    Use FuzzILTool to compile a JavaScript program to a FuzzIl program (requires Node.js)

    Args:
        target (str): The path to the the JavaScript program to compile to FuzzIL

    Returns:
        str: The compiled FuzzIL program the given JS program
    """
    return run_command(f"swift run FuzzILTool --compile {target}")

# Unsure if we will want this tool to run with the fuzzilli d8
# so that we can measure if it hit the code region we are targeting. 
# That being said, surely we can find another way.
@tool
def run_d8(target: str) -> str:
    """
    Run the target program using d8 to test for syntactical correctness
    and test for coverage. 
    """ # consider adding arguments for it to tack onto the V8 runs
    return run_command(f"./v8/v8/out/fuzzbuild/d8 {target}") 


