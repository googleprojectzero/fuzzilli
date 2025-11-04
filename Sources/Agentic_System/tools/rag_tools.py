from smolagents import tool

import os
import json
import hashlib
import sys
from pathlib import Path

try:
    import chromadb
    from chromadb.config import Settings as ChromaSettings
except ImportError as e:
    print(f"Failed to import chromadb: {e}") 
    sys.exit(-1)

try:
    from langchain_community.vectorstores import Chroma
    from langchain_community.embeddings import HuggingFaceEmbeddings
    Chroma = Chroma
except ImportError:
    Chroma = None
    HuggingFaceEmbeddings = None

try:
    import numpy as np
    import faiss
    import pickle
    from sentence_transformers import SentenceTransformer
    FAISS_AVAILABLE = True
except ImportError:
    FAISS_AVAILABLE = False

def _get_embeddings():
    """Get embeddings function, returns None if not available."""
    if HuggingFaceEmbeddings is None:
        raise RuntimeError("HuggingFaceEmbeddings not available")
    return HuggingFaceEmbeddings(model_name="sentence-transformers/all-MiniLM-L6-v2")

def _rag_dir() -> str:
    return os.getenv("RAG_DB_DIR", "./rag_db")

def _collection_marker_path() -> Path:
    return Path(_rag_dir()) / ".active_collection"

def _get_active_collection(default: str = "rag-chroma") -> str:
    try:
        p = _collection_marker_path()
        if p.exists():
            return p.read_text().strip() or default
        return default
    except Exception:
        return default

def _set_active_collection(name: str) -> None:
    p = _collection_marker_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(name)

def _get_chromadb_collection(collection_name: str):
    if chromadb is None:
        raise RuntimeError("chromadb not installed")
    path = _rag_dir()
    try:
        client = chromadb.PersistentClient(path=path)  # chromadb>=0.5
    except Exception:
        # Fallback: older API with Settings
        client = chromadb.Client(ChromaSettings(persist_directory=path))  # type: ignore
    return client.get_or_create_collection(name=collection_name)

def _compute_doc_id(metadata: dict, content: str) -> str:
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

@tool
def set_rag_collection(name: str) -> str:
    """
    Sets the active RAG collection name for subsequent operations.

    Args:
        name (str): Collection name to select, e.g., "rev-<challenge_slug>".
    """
    try:
        _set_active_collection(name)
        return f"Active RAG collection set to: {name}"
    except Exception as e:
        return f"Error setting collection: {e}"

@tool
def get_rag_collection() -> str:
    """
    Returns the current active RAG collection name.
    """
    return _get_active_collection()

@tool
def search_rag_db(query: str, where_json: str = "", k: int = 8, collection: str = "") -> str:
    """
    Hybrid search with optional metadata filters. Returns JSONL of {id, metadata, snippet}.

    Args:
        query (str): Natural language query used for vector retrieval.
        where_json (str): JSON dict filter on metadata (e.g., '{"challenge":"ctf-1"}').
        k (int): Number of results to return.
        collection (str): Override collection name; defaults to the active collection.
    """
    try:
        if Chroma is None:
            return "RAG is not configured in this environment."
        try:
            embeddings = _get_embeddings()
        except Exception as ee:
            return f"RAG embedding not available: {ee}"
        RAG_DB_DIR = _rag_dir()
        collection_name = collection or _get_active_collection("rag-chroma")
        vectorstore = Chroma(
          collection_name=collection_name,
          persist_directory=RAG_DB_DIR,
          embedding_function=embeddings
        )
        flt = json.loads(where_json) if where_json else None
        retriever = vectorstore.as_retriever(search_kwargs={"k": int(k), "filter": flt} if flt else {"k": int(k)})
        docs = retriever.invoke(query)
        lines = []
        for d in docs:
            meta = getattr(d, 'metadata', {}) or {}
            doc_id = meta.get("doc_id") or meta.get("id") or ""
            snippet = (getattr(d, 'page_content', str(d)) or "").strip()
            if len(snippet) > 300:
                snippet = snippet[:300] + "..."
            lines.append(json.dumps({"id": doc_id, "metadata": meta, "snippet": snippet}))
        return "\n".join(lines) if lines else "[]"
    except Exception as e:
        return f"Error searching RAG DB: {e}"

@tool
def update_rag_db(doc_id: str, new_content: str = "", new_metadata_json: str = "", collection: str = "") -> str:
    """
    Updates an existing doc by id, or creates it if it doesn't exist (upsert).
    If content or metadata omitted when updating, preserves current value.

    Args:
        doc_id (str): The document id to update or create.
        new_content (str): New full content for the document. Required for new docs, optional for updates.
        new_metadata_json (str): JSON dict of metadata fields to merge into existing metadata (or full metadata for new docs).
        collection (str): Override collection name; defaults to the active collection.
    """
    try:
        coll = _get_chromadb_collection(collection or _get_active_collection("rag-chroma"))
        cur = coll.get(ids=[doc_id])
        
        if not cur or not cur.get("ids"):
            if not new_content:
                return f"Error: new_content required when creating new document: {doc_id}"
            meta = {}
            if new_metadata_json:
                try:
                    meta = json.loads(new_metadata_json)
                except Exception:
                    return "Invalid JSON for new_metadata_json"
            coll.add(ids=[doc_id], documents=[new_content], metadatas=[meta])
            return f"Created: {doc_id}"
        
        doc = (cur.get("documents") or [""])[0]
        meta = (cur.get("metadatas") or [{}])[0]
        if new_content:
            doc = new_content
        if new_metadata_json:
            try:
                meta_update = json.loads(new_metadata_json)
                meta.update(meta_update)
            except Exception:
                return "Invalid JSON for new_metadata_json"
        coll.update(ids=[doc_id], documents=[doc], metadatas=[meta])
        return f"Updated: {doc_id}"
    except Exception as e:
        return f"Error updating RAG DB: {e}"

@tool
def delete_rag_db(doc_ids_json: str = "", where_json: str = "", collection: str = "") -> str:
    """
    Deletes documents by ids or metadata filter.

    Args:
        doc_ids_json (str): JSON list of ids to delete (e.g., '["id1","id2"]').
        where_json (str): JSON dict metadata filter for bulk delete (e.g., '{"challenge":"ctf-1"}').
        collection (str): Override collection name; defaults to the active collection.
    """
    try:
        coll = _get_chromadb_collection(collection or _get_active_collection("rag-chroma"))
        ids = json.loads(doc_ids_json) if doc_ids_json else None
        where = json.loads(where_json) if where_json else None
        if ids:
            coll.delete(ids=ids)
            return f"Deleted {len(ids)} by id"
        if where:
            coll.delete(where=where)
            return "Deleted by filter"
        return "No ids or filter provided"
    except Exception as e:
        return f"Error deleting from RAG DB: {e}"

@tool
def list_rag_db(where_json: str = "", limit: int = 100, collection: str = "") -> str:
    """
    Lists documents (id, metadata, snippet) matching optional filter.

    Args:
        where_json (str): JSON dict metadata filter (e.g., '{"type":"func"}').
        limit (int): Maximum number of documents to return.
        collection (str): Override collection name; defaults to the active collection.
    """
    try:
        coll = _get_chromadb_collection(collection or _get_active_collection("rag-chroma"))
        where = json.loads(where_json) if where_json else None
        resp = coll.get(where=where, limit=int(limit))
        ids = resp.get("ids") or []
        docs = resp.get("documents") or []
        metas = resp.get("metadatas") or []
        lines = []
        for i, doc_id in enumerate(ids):
            snippet = (docs[i] or "").strip()
            if len(snippet) > 300:
                snippet = snippet[:300] + "..."
            lines.append(json.dumps({"id": doc_id, "metadata": metas[i] if i < len(metas) else {}, "snippet": snippet}))
        return "\n".join(lines) if lines else "[]"
    except Exception as e:
        return f"Error listing RAG DB: {e}"

@tool
def get_rag_doc(doc_id: str, collection: str = "") -> str:
    """
    Gets a single document by id, returning full document and metadata as JSON.

    Args:
        doc_id (str): The document id to fetch.
        collection (str): Override collection name; defaults to the active collection.
    """
    try:
        coll = _get_chromadb_collection(collection or _get_active_collection("rag-chroma"))
        resp = coll.get(ids=[doc_id])
        if not resp or not resp.get("ids"):
            return f"Not found: {doc_id}"
        result = {
            "id": (resp.get("ids") or [""])[0],
            "metadata": (resp.get("metadatas") or [{}])[0],
            "document": (resp.get("documents") or [""])[0],
        }
        return json.dumps(result)
    except Exception as e:
        return f"Error getting RAG doc: {e}"

class FAISSKnowledgeBase:
    _instance = None
    
    def __init__(self):
        if not FAISS_AVAILABLE:
            raise RuntimeError("FAISS dependencies not available")
        
        base_dir = Path(__file__).parent.parent / 'knowlage_docs' / 'v8_knowlagebase'
        
        if not base_dir.exists():
            raise FileNotFoundError(f"Knowledge base not found: {base_dir}")
        
        index_file = base_dir / 'v8_knowlagebase.index'
        metadata_file = base_dir / 'v8_knowlagebase_metadata.json'
        model_file = base_dir / 'v8_knowlagebase_model.pkl'
        
        if not all([index_file.exists(), metadata_file.exists(), model_file.exists()]):
            raise FileNotFoundError("Knowledge base files incomplete")
        
        self.index = faiss.read_index(str(index_file))
        
        with open(metadata_file, 'r') as f:
            self.metadata = json.load(f)
        
        with open(model_file, 'rb') as f:
            model_name = pickle.load(f)
        
        # Force CPU device to avoid accidental meta device transfers that cause
        # "Cannot copy out of meta tensor" errors in some torch/accelerate setups.
        import torch
        self.model = SentenceTransformer(model_name)
        self.model = self.model.to('cpu')
        if hasattr(self.model, 'eval'):
            self.model.eval()
    
    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance
    
    def search(self, query: str, top_k: int = 5, topic_filter: str = None):
        query_embedding = self.model.encode([query], convert_to_numpy=True)
        
        search_k = top_k * 3 if topic_filter else top_k
        distances, indices = self.index.search(query_embedding.astype('float32'), search_k)
        
        results = []
        for idx, distance in zip(indices[0], distances[0]):
            if idx < len(self.metadata):
                doc = self.metadata[idx]
                
                if topic_filter and topic_filter.lower() not in doc['topic'].lower():
                    continue
                
                similarity = 1.0 / (1.0 + distance)
                results.append({
                    'path': doc['path'],
                    'topic': doc['topic'],
                    'content': doc['content'],
                    'similarity': float(similarity)
                })
                
                if len(results) >= top_k:
                    break
        
        return results

@tool
def search_knowledge_base(query: str, top_k: int = 3, topic_filter: str = "") -> str:
    """
    Searches the V8/JavaScript/C++ knowledge base using semantic search.
    
    Args:
        query (str): Natural language query about V8, JavaScript, or C++ concepts.
        top_k (int): Number of results to return (default 3, max 10, for the first query please keep top_k between 3-5).
        topic_filter (str): Optional topic filter: 'v8', 'javascript', 'cpp', or empty for all.
    Returns:
        str: JSON string containing search results with topic, file path, and content snippets.
    """
    if not FAISS_AVAILABLE:
        return json.dumps({"error": "Knowledge base not available. Install dependencies: pip install numpy faiss-cpu sentence-transformers"})
    
    try:
        kb = FAISSKnowledgeBase.get_instance()
        
        top_k = max(1, min(10, int(top_k)))
        
        results = kb.search(query, top_k, topic_filter if topic_filter else None)
        
        output = []
        for result in results:
            content = result['content']
            
            output.append({
                'topic': result['topic'],
                'file': result['path'],
                'similarity': round(result['similarity'], 3),
                'content': content
            })
        
        return json.dumps(output, indent=2)
    
    except Exception as e:
        return json.dumps({"error": f"Failed to search knowledge base: {str(e)}"})

@tool
def get_knowledge_doc(file_path: str) -> str:
    """
    Retrieves a full document from the knowledge base by its file path.
    
    Args:
        file_path (str): The relative file path from search results.
    
    Returns:
        str: JSON string containing the full document content.
    """
    if not FAISS_AVAILABLE:
        return json.dumps({"error": "Knowledge base not available"})
    
    try:
        kb = FAISSKnowledgeBase.get_instance()
        
        for doc in kb.metadata:
            if doc['path'] == file_path:
                return json.dumps({
                    'topic': doc['topic'],
                    'file': doc['path'],
                    'content': doc['content']
                }, indent=2)
        
        return json.dumps({"error": f"Document not found: {file_path}"})
    
    except Exception as e:
        return json.dumps({"error": f"Failed to retrieve document: {str(e)}"})


class FAISSV8SourceRag:
    _instance = None
    
    def __init__(self):
        if not FAISS_AVAILABLE:
            raise RuntimeError("FAISS dependencies not available")
        
        base_dir = Path(__file__).parent.parent / 'rag_db' / 'v8_source_rag'
        
        if not base_dir.exists():
            raise FileNotFoundError(f"v8 source rag not found: {base_dir}")
        
        index_file = base_dir / 'v8_source_rag.index'
        metadata_file = base_dir / 'v8_source_rag_metadata.json'
        model_file = base_dir / 'v8_source_rag_model.pkl'
        
        if not all([index_file.exists(), metadata_file.exists(), model_file.exists()]):
            raise FileNotFoundError("v8 source rag files incomplete")
        
        self.index = faiss.read_index(str(index_file))
        
        with open(metadata_file, 'r') as f:
            self.metadata = json.load(f)
        
        with open(model_file, 'rb') as f:
            model_name = pickle.load(f)
        
        # Force CPU device to avoid accidental meta device transfers that cause
        # "Cannot copy out of meta tensor" errors in some torch/accelerate setups.
        import torch
        self.model = SentenceTransformer(model_name)
        self.model = self.model.to('cpu')
        if hasattr(self.model, 'eval'):
            self.model.eval()
    
    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance
    
    def search(self, query: str, top_k: int = 5, topic_filter: str = None):
        query_embedding = self.model.encode([query], convert_to_numpy=True)
        
        search_k = top_k * 3 if topic_filter else top_k
        distances, indices = self.index.search(query_embedding.astype('float32'), search_k)
        
        results = []
        for idx, distance in zip(indices[0], distances[0]):
            if idx < len(self.metadata):
                doc = self.metadata[idx]
                
                if topic_filter and topic_filter.lower() not in doc['topic'].lower():
                    continue
                
                similarity = 1.0 / (1.0 + distance)
                results.append({
                    'path': doc['path'],
                    'topic': doc['topic'],
                    'content': doc['content'],
                    'similarity': float(similarity)
                })
                
                if len(results) >= top_k:
                    break
        
        return results

@tool
def search_v8_source_rag(query: str, top_k: int = 3, topic_filter: str = "") -> str:
    """
    Searches the V8 source code RAG using semantic search.
    
    Args:
        query (str): Natural language query about V8 source code, JavaScript, or C++ concepts.
        top_k (int): Number of results to return (default 3, max 10, for the first query please keep top_k between 3-5).
        topic_filter (str): Optional topic filter to narrow results (e.g., 'ic', 'compiler', 'runtime'), or empty for all.
    Returns:
        str: JSON string containing search results with topic, file path, and content snippets.
    """
    if not FAISS_AVAILABLE:
        return json.dumps({"error": "V8 source RAG not available. Install dependencies: pip install numpy faiss-cpu sentence-transformers"})
    
    try:
        kb = FAISSV8SourceRag.get_instance()
        
        top_k = max(1, min(10, int(top_k)))
        
        results = kb.search(query, top_k, topic_filter if topic_filter else None)
        
        output = []
        for result in results:
            content = result['content']
            output.append({
                'topic': result['topic'],
                'file': result['path'],
                'similarity': round(result['similarity'], 3),
                'content': content
            })
        
        return json.dumps(output, indent=2)
    
    except Exception as e:
        return json.dumps({"error": f"Failed to search V8 source RAG: {str(e)}"})

@tool
def get_v8_source_rag_doc(file_path: str) -> str:
    """
    Retrieves a full document from the V8 source RAG by its file path.
    
    Args:
        file_path (str): The relative file path from search results.
    
    Returns:
        str: JSON string containing the full document content.
    """
    if not FAISS_AVAILABLE:
        return json.dumps({"error": "V8 source RAG not available"})
    
    try:
        kb = FAISSV8SourceRag.get_instance()
        
        for doc in kb.metadata:
            if doc['path'] == file_path:
                return json.dumps({
                    'topic': doc['topic'],
                    'file': doc['path'],
                    'content': doc['content']
                }, indent=2)
        
        return json.dumps({"error": f"V8 source RAG document not found: {file_path}"})
    
    except Exception as e:
        return json.dumps({"error": f"Failed to retrieve V8 source RAG document: {str(e)}"})
