from smolagents import tool
from common_tools import *
from rag_tools import * # deal with this later

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
    return run_command(f"tree {options} {directory}")

@tool 
def run_d8(target: str) -> str:
    """
    Run the target program using d8 to test for syntactical correctness
    and test for coverage. 
    """ # consider adding arguments for it to tack onto the V8 runs
    return run_command(f"./v8/v8/out/fuzzbuild/d8 {target}") 

@tool
def get_execution_data(target: str) -> str:
    """
    Get execution data from the target program using d8 to test for syntactical correctness
    and test for coverage. 
    """
    return run_command(f"")  # Database access wrappere

@tool
def get_call_graph(target: str) -> str:
    """
    Get the call graph of the target program using d8 to test for syntactical correctness
    and test for coverage. 
    """
    return run_command(f"")  # Database access wrappere

