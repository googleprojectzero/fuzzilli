from smolagents import tool
from common_tools import *

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