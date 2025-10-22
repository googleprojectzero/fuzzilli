from smolagents import Tool
from common_tools import *

@Tool
def tree(query: str) -> str:
    """
    Use tree to find directories and files relating to the component we are investigating.
    """
    return tree(query)