OUTPUT_DIRECTORY = "/tmp/fog-output-samples"

# Try to import smolagents, but don't fail if it's not available
try:
    from smolagents import tool
except ImportError:
    # Define a dummy decorator if smolagents is not available
    def tool(func):
        return func
from openai import OpenAI
import subprocess
import os
import json
import pathlib
import sys

from config_loader import get_openai_api_key, get_anthropic_api_key
client = OpenAI(api_key=get_openai_api_key())


if not os.getenv('V8_PATH'):
    print("V8_PATH environment variable not set. Do export V8_PATH='path to v8 base dir'")
    print("     Example: export V8_PATH=/path/to/v8/v8/src")
    sys.exit(0)
if not os.getenv('D8_PATH'):
    print("D8_PATH is not set")
    sys.exit(1)
if not os.getenv('FUZZILLI_TOOL_BIN'):
    print("FUZZILLI_TOOL_BIN is not set")
    sys.exit(1)
if not os.getenv('FUZZILLI_PATH'):
    print("FUZZILLI_PATH is not set")
    sys.exit(1)
D8_PATH = os.getenv('D8_PATH')
FUZZILLI_TOOL_BIN = os.getenv('FUZZILLI_TOOL_BIN')
V8_PATH = os.getenv('V8_PATH')
FUZZILLI_PATH = os.getenv('FUZZILLI_PATH')
if "src" not in V8_PATH:
    print('V8_PATH is not a valid V8 source code directory')
    sys.exit(0)
if "fuzzillai" not in FUZZILLI_PATH:
    print(f"FUZZILLI_PATH is not a valid Fuzzilli path: {FUZZILLI_PATH}")
    sys.exit(0)

D8_COMMON_FLAGS = "--allow-natives-syntax"

# Try to import CFG tools, but don't fail if clang is not available
try:
    from tools.cfg_tool import *
    cfg_builder = CFGBuilder(V8_PATH)
    cfg_builder.parse_directory(V8_PATH, pattern='*.cc')
except Exception as e:
    # Define fallback functions if CFG tools can't be imported
    def find_function_cfg(function_name: str) -> str:
        return f"CFG analysis not available: {e}"
    
    cfg_builder = None

# Try to import from rag_tools, but handle import errors gracefully
try:
    from rag_tools import *
except ImportError as e:
    # Define fallback functions if rag_tools can't be imported
    def _get_embeddings():
        raise RuntimeError(f"RAG tools not available: {e}")
    
    def _get_active_collection(default="rag-chroma"):
        return default
    
    def _compute_doc_id(metadata, content):
        import hashlib
        key_fields = [
            metadata.get("challenge", ""),
            metadata.get("binary", ""),
            metadata.get("type", ""),
            metadata.get("label", ""),
            metadata.get("address", ""),
            metadata.get("file", ""),
            str(metadata.get("stage", "")),
        ]
        h = hashlib.sha1("|".join(key_fields).encode("utf-8"))
        return h.hexdigest()
    
    Chroma = None



# helper to get output from run_command
def get_output(completed_process) -> str:
    if not completed_process:
        return ""
    p_stdout = completed_process.stdout if completed_process.stdout else None
    p_stderr = completed_process.stderr if completed_process.stderr else None
    return p_stdout if p_stdout else p_stderr

@tool
def run_command(command: str) -> str:
    """
    Executes a command analysis tools.
    
    Args:
        command (str): The command to execute in the container.
    """
    return_val = subprocess.run(command, shell=True, capture_output=True, text=True)
    print(f"Command: {command}")
    return return_val

@tool
def read_rag_db(query: str) -> str:
    """
    Reads the RAG database and returns the most relevant information.

    Args:
        query (str): Natural language search query to retrieve relevant chunks.
    """
    try:
        # Lazy init if available
        if Chroma is None:
            return "RAG is not configured in this environment."
        try:
            embeddings = _get_embeddings()
        except Exception as ee:
            return f"RAG embedding not available: {ee}"
        RAG_DB_DIR = os.getenv("RAG_DB_DIR", "./rag_db")
        collection_name = _get_active_collection(default="rag-chroma")
        vectorstore = Chroma(
          collection_name=collection_name,
          persist_directory=RAG_DB_DIR,
          embedding_function=embeddings
        )
        retriever = vectorstore.as_retriever(search_kwargs={"k": 4})
        docs = retriever.invoke(query)
        return "\n---\n".join([getattr(d, 'page_content', str(d)) for d in docs])
    except Exception as e:
        return f"Error reading from RAG DB: {e}"


@tool
def write_rag_db(content: str, metadata_json: str = "") -> str:
    """
    Writes a text chunk to the RAG database, with metadata as JSON.

    Copy the following metadata format and fill in the values as appropriate:
    EXAMPLE:
    {"agent":"IDA","challenge":"...","file":"...","line":"..."}

    Args:
        content: Text to index.
        metadata_json: JSON string with metadata regarding the agent that wrote the content 
    """
    try:
        if Chroma is None:
            return "RAG is not configured in this environment."
        try:
            embeddings = _get_embeddings()
        except Exception as ee:
            return f"RAG embedding not available: {ee}"
        RAG_DB_DIR = os.getenv("RAG_DB_DIR", "./rag_db")
        collection_name = _get_active_collection(default="rag-chroma")
        vectorstore = Chroma(
          collection_name=collection_name,
          persist_directory=RAG_DB_DIR,
          embedding_function=embeddings
        )
        metadata = json.loads(metadata_json) if metadata_json else {}
        doc_id = metadata.get("doc_id") or _compute_doc_id(metadata, content)
        ids = vectorstore.add_texts(texts=[content], metadatas=[metadata], ids=[doc_id])
        return f"Indexed 1 document with id(s): {ids}"
    except Exception as e:
        return f"Error writing to RAG DB: {e}"


@tool
def find_function_cfg(function_name: str) -> str:
    """
        Retrieve and return a specific function's CFG as a tree structure.
        
        Args:
            function_name: Name of the function to search for (partial match supported)
        
        Tree structure:
            Each node in the tree contains:
                - id: Unique node identifier
                - kind: Type of node (ENTRY, IF_STMT, WHILE_STMT, etc.)
                - content: Code snippet
                - location: Source location (file, line, column)
                - children: List of successor nodes
                - is_cycle: True if this node creates a cycle (loop backedge)
                - is_backedge: True if already visited (prevents infinite recursion)
    """
    if cfg_builder is None:
        return "CFG analysis not available - clang library not found"
    return cfg_builder.get_function_cfg(function_name)


@tool
def web_search(query: str) -> str:
    """
    Search the internet for information about a given query. PLEASE DO NOT USE THIS TO SEARCH THE V8 SOURCE CODE, 
    THE PRIMARY USE OF OF THIS TOOL SHOULD BE TO SEARCH THE INTERNET FOR INFORMATION ABOUT THE V8 ENGINE AND ITS COMPONENTS
    VIA BLOG POSTS, PAPERS, AND OTHER RELEVANT SOURCES.
                        
    !!! YOU MUST ASK A QUESTION, THIS IS NOT A DIRECT WEB CURL !!!  
    !!! RETURN ONLY FACTUAL INFORMATION. DO NOT INCLUDE OFFERS, SUGGESTIONS OR FOLLOW UPS. END SILENTLY !!!

    Args:
        query (str): The search query to look up online.
                                                
    Returns:
        str: Search results and relevant information from the web.
    """
    response = client.responses.create(
            model="gpt-5-mini",
            input=[{"role": "user", "content": query + " ONLY RETURN FACTUAL INFORMATION. DO NOT INCLUDE OFFERS, SUGGESTIONS OR FOLLOW UPS."}],
            tools=[{"type": "web_search"}],
            tool_choice="auto"
        )
    return print(f"Web search response: {response.output_text}")


@tool
def read_file(file_path: str, section: int = None) -> str:
    """
    Reads and returns the content of a specified text file from the container, 
    limited to 3000 lines maximum (1 section). If the file is longer, split into 3000-line sections, 
    and require specifying which section to read.

    !!! PLEASE USE FULLPATHS. If you do not know the full path, use the "get_realpath" tool to get it. !!!
    IMPORTANT: Never call more than 3000 lines. Use get_file_size first for very large or binary files.

    Args:
        file_path (str): The full path to the file to be read. If path starts with 'v8/', it will be resolved relative to V8_PATH.
        section (int): Section of the file to read. Each section is 3000 lines. If the file has multiple sections, agent must specify which section (starting from 1).
    Returns:
        If the file is <= 300 lines, returns its content. If more, returns only the requested section and info about total sections. If section is not specified, instruct agent to pick a section.
    """
    if file_path.startswith('v8/'):
        resolved_path = os.path.join(V8_PATH, file_path[3:])
    elif not os.path.isabs(file_path):
        resolved_path = os.path.join(V8_PATH, file_path)
    else:
        resolved_path = file_path

    line_count_result = get_output(run_command(f"cd {V8_PATH} && wc -l '{resolved_path}'"))
    try:
        line_count = int(line_count_result.strip().split()[0])
    except Exception:
        return f"Could not determine number of lines in file. wc -l output: {line_count_result}"

    lines_per_section = 3000
    num_sections = (line_count + lines_per_section - 1) // lines_per_section

    if line_count <= lines_per_section:
        return get_output(run_command(f"cd {V8_PATH} && cat '{resolved_path}'"))

    if section is None or section < 1 or section > num_sections:
        return (
            f"File '{file_path}' has {line_count} lines and is divided into {num_sections} sections "
            f"(each section is 3000 lines).\n"
            f"To read this file, please specify a section number between 1 and {num_sections} "
            f"using the 'section' argument."
        )

    start_line = 1 + (section - 1) * lines_per_section
    end_line = min(start_line + lines_per_section - 1, line_count)
    read_cmd = f"cd {V8_PATH} && sed -n '{start_line},{end_line}p' '{resolved_path}'"
    content = get_output(run_command(read_cmd))
    return (
        f"Showing section {section}/{num_sections} (lines {start_line}-{end_line}) of '{file_path}':\n"
        f"{content}"
    )