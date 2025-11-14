from smolagents import tool
from tools.common_tools import *
from pathlib import Path
from fuzzywuzzy import fuzz

@tool
def tree(directory: str = ".", options: str = "") -> str:
    """
    Display directory structure using tree command to explore project layout.
    
    Args:
        directory (str, optional): The directory to explore. Defaults to current directory ".".
        options (str, optional): Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -f: Show full path prefix 
    
    Returns:
        str: Tree structure showing directories and files in the specified path.
    """
    return get_output(run_command(f"tree {options} {directory}"))

