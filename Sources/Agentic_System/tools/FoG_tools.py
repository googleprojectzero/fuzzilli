from smolagents import tool
from common_tools import *

@tool
def swift_build(target: str = "FuzzilliCli") -> str:
    """
    Build the Swift codebase using the Swift compiler.
    
    Args:
        target (str, optional): The Swift target to build. Defaults to "FuzzilliCli".
    
    Returns:
        str: The build output including any errors or success messages.
    """
    return run_command(f"swift build --target {target}")

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

@tool
def ripgrep(pattern: str, file_type: str = "swift", context_lines: int = 2) -> str:
    """
    Search for text patterns in files using ripgrep (rg) for fast text searching.
    
    Args:
        pattern (str): The regex pattern to search for.
        file_type (str, optional): File type filter (e.g., 'swift', 'py', 'js'). Defaults to 'swift'.
        context_lines (int, optional): Number of context lines to show around matches. Defaults to 2.
    
    Returns:
        str: Search results showing matching lines with context.
    """
    return run_command(f"rg -t {file_type} -C {context_lines} '{pattern}'")   

@tool
def fuzzy_finder(pattern: str, file_type: str = "swift", options: str = "") -> str:
    """
    Use fuzzy finding to locate files and content by approximate name matching.
    
    Args:
        pattern (str): The fuzzy search pattern to match against file names and content.
        file_type (str, optional): File type filter (e.g., 'swift', 'py', 'js'). Defaults to 'swift'.
    
    Returns:
        str: Fuzzy search results showing files and content that approximately match the pattern.
    """
    return run_command(f"fzf {options} {file_type} {pattern}")

@tool
def lift_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to lift a FuzzIL protobuf to a JavaScript program

    Args:
        target (str): The path to the target FuzzIL program identified by .fzil to be lifted to JS

    Returns:
        str: The lifted JS program from the given FuzzIL
    """
    return run_comman(f"swift run FuzzILTool --liftToFuzzIL {target}")

@tool
def compile_fuzzil_to_js(target: str) -> str:
    """
    Use FuzzILTool to compile a JavaScript program to a FuzzIl program (requires Node.js)

    Args:
        target (str): The path to the the JavaScript program to compile to FuzzIL

    Returns:
        str: The compiled FuzzIL program the given JS program
    """
    return run_command(f"swift run FuzzILTool --compile {target}")