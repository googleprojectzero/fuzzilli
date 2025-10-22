from smolagents import Tool
import subprocess

@Tool
def run_command(command: str) -> str:
    """
    Executes a command inside the CTF Docker container with access to analysis tools.
    
    Args:
        command (str): The command to execute in the container.
    """
    return subprocess.run(command, shell=True, capture_output=True, text=True)