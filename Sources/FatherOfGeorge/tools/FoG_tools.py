from smolagents import Tool
from common_tools import *

@Tool
def swift_build(query: str) -> str:
    """
    Build the swift code using the swift compiler
    """
    return swift_build(query)

@Tool
def lookup(query: str) -> str:
    """
    Lookup the query in the internet
    """
    return lookup(query)

@Tool
def run_python(code: str) -> str:
    """
    Run the python code using the python interpreter
    No more than `N` steps should be spent on this tool.
    Args:
        code (str): The python code to run
    """
    return run_python(code)

@Tool 
def get_call_graph(query: str) -> str:
    """
    Use the call graph to find functions, classes, and variables by name patterns
    """
    return get_call_graph(query)

@Tool
def tree(query: str) -> str:
    """
    Use tree to find directories and files relating to the component we are investigating.
    """
    return tree(query)

@Tool
def ripgrep(query: str) -> str:
    """
    Use ripgrep to find functions, classes, and variables by name patterns
    """
    return ripgrep(query)   

@Tool
def fuzzy_finder(query: str) -> str:
    """
    Use fuzzy find to find functions, classes, and variables by name patterns
    """
    return fuzzy_finder(query)
