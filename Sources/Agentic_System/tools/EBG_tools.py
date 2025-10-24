from smolagents import tool
from common_tools import *

@tool
def tree(directory: str = ".", options: str = "") -> str:
    """
    Display directory structure using tree command to explore project layout.
    
    Args:
        directory (str, optional): The directory to explore. Defaults to current directory ".".
        options (str, optional): Additional tree command options. Common options include:
            -L NUM: Limit depth to NUM levels
            -a: Show hidden files (files starting with .)
            -d: Show only directories
            -f: Show full path prefix
            -i: Don't print indentation lines
            -l: Follow symbolic links like directories
            -p: Print the file type and permissions for each file
            -s: Print the size of each file
            -t: Sort files by modification time
            -u: Print the username, or UID # if no username is available
            -g: Print the group name, or GID # if no group name is available
            -D: Print the date of the last modification time
            -F: Append a '/' for directories, a '=' for socket files, a '@' for symbolic links, a '|' for FIFOs, and a '*' for executable files
            -I pattern: Do not list files that match the given pattern
            -P pattern: List only those files that match the given pattern
            -H baseHREF: Prints out HTML format with baseHREF as top directory
            -T string: Replace the default HTML title and H1 header with string
            -R: Rerun tree when max dir is reached
            -o filename: Send output to filename
            -q: Print non-printable characters as '?'
            -N: Print non-printable characters as is
            -r: Sort the output in reverse alphabetic order
            -dirsfirst: List directories before files
            -version: Print version and exit
            -help: Print usage and exit
    
    Returns:
        str: Tree structure showing directories and files in the specified path.
    """
    return run_command(f"tree {options} {directory}")