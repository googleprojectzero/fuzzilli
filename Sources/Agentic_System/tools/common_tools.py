OUTPUT_DIRECTORY = "/tmp/fog-output-samples"

# Try to import smolagents, but don't fail if it's not available
try:
    from smolagents import tool
except ImportError:
    # Define a dummy decorator if smolagents is not available
    def tool(func):
        return func

import subprocess
import os
import json

# Try to import CFG tools, but don't fail if clang is not available
try:
    from tools.cfg_tool import *
    cfg_builder = CFGBuilder("/usr/share/vrigatoni/fuzzillai/v8/v8")
    cfg_builder.parse_directory("/usr/share/vrigatoni/fuzzillai/v8/v8", pattern='*.cc')
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
    Executes a command inside the CTF Docker container with access to analysis tools.
    
    Args:
        command (str): The command to execute in the container.
    """
    return subprocess.run(command, shell=True, capture_output=True, text=True)

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