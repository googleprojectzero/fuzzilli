from smolagents import Tool
from common_tools import *

@Tool
def swift_build(target: str = "FuzzilliCli") -> str:
    """
    Build the Swift codebase using the Swift compiler.
    
    Args:
        target (str, optional): The Swift target to build. Defaults to "FuzzilliCli".
    
    Returns:
        str: The build output including any errors or success messages.
    """
    return run_command(f"swift build --target {target}")

@Tool
def lookup(query: str) -> str:
    """
    Search the internet for information about a given query.
    
    Args:
        query (str): The search query to look up online.
    
    Returns:
        str: Search results and relevant information from the web.
    """
    return run_command(f"curl -s 'https://api.duckduckgo.com/?q={query}&format=json&no_html=1&skip_disambig=1'")

@Tool
def run_python(code: str) -> str:
    """
    Execute Python code using the Python interpreter.
    
    Args:
        code (str): The Python code to execute.
    
    Returns:
        str: The output from executing the Python code, including stdout and stderr.
    """
    return run_command(f"python3 -c '{code}'")

@Tool 
def get_call_graph() -> str:
    """
    Generate and search a call graph to find functions, classes, and variables by name patterns.
    
    Returns:
        str: Call graph analysis results showing relationships and matches.
    """
    return get_call_graph()

@Tool
def tree(directory: str = ".", max_depth: int = 3) -> str:
    """
    Display directory structure using tree command to explore project layout.
    
    Args:
        directory (str, optional): The directory to explore. Defaults to current directory ".".
        max_depth (int, optional): Maximum depth to display. Defaults to 3.
    
    Returns:
        str: Tree structure showing directories and files in the specified path.
    """
    return run_command(f"tree -L {max_depth} {directory}")

@Tool
def ripgrep(pattern: str, file_type: str = "swift", context_lines: int = 2) -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
    Args:
        --files: List all files that would be searched, without searching inside them. 
             Example: `rg --files src/` → lists all files under `src/`.

        --type: Limit search to specific file types. 
                Example: `rg --type py "def " src/` → search only Python files.

        --glob: Include or exclude paths by glob pattern. 
                Example: `rg --glob '!tests/*' "TODO"` → skip `tests` folder.

        --ignore-case: Match text case-insensitively. 
                    Example: `rg --ignore-case "error"` → matches `Error`, `ERROR`, etc.

        --no-heading: Suppress file name headings in results. 
                    Example: `rg --no-heading "main"` → cleaner, machine-parsable output.

        --line-number: Show line numbers in matches. 
                    Example: `rg --line-number "main"` → outputs `file:line:match`.

        --vimgrep: Output in `file:line:column:match` format for easy parsing. 
                Example: `rg --vimgrep "init"` → structured grep-like output.

        --json: Emit results as structured JSON. 
                Example: `rg --json "TODO"` → machine-readable output for parsing.

        --max-depth: Limit recursion depth when searching directories. 
                    Example: `rg --max-depth 2 "class"` → search only two levels deep.
    
    Returns:
        str: Search results showing matching lines with context.
    """
    return run_command(f"rg -t {file_type} -C {context_lines} '{pattern}'")   

@Tool
def fuzzy_finder(pattern: str, file_type: str = "swift", options: str = "") -> str:
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
    return run_command(f"fzf {options} {file_type} {pattern}")
