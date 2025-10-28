#!/usr/bin/env python3

import sys
from pathlib import Path
import hashlib

sys.path.append(str(Path(__file__).parent.parent / "tools"))

try:
    import chromadb
    from chromadb.config import Settings as ChromaSettings
except ImportError:
    print("Error: chromadb not installed. Install with: pip install chromadb")
    sys.exit(1)

try:
    from langchain_community.embeddings import HuggingFaceEmbeddings
except ImportError:
    print("Error: langchain_community not installed. Install with: pip install langchain-community sentence-transformers")
    sys.exit(1)


def get_topic_from_path(file_path: Path, base_dir: Path) -> str:
    relative = file_path.relative_to(base_dir)
    parts = relative.parts
    
    if len(parts) > 1:
        topic = parts[0]
        if topic == "cpp":
            return "C++"
        elif topic == "v8":
            return "V8 JavaScript Engine"
        elif topic == "mdm_js":
            return "MDN JavaScript Documentation"
        elif topic == "whitepapers":
            return "Research Papers and Whitepapers"
    
    return "General"


def compute_doc_id(file_path: Path, base_dir: Path) -> str:
    relative_path = str(file_path.relative_to(base_dir))
    return hashlib.sha256(relative_path.encode()).hexdigest()


def index_files_to_rag(base_dir: Path, collection_name: str = "v8_knowlagebase"):
    print(f"Initializing ChromaDB with collection: {collection_name}")
    
    embeddings = HuggingFaceEmbeddings(model_name="sentence-transformers/all-MiniLM-L6-v2")
    
    rag_db_dir = base_dir.parent / "rag_db"
    rag_db_dir.mkdir(exist_ok=True)
    
    client = chromadb.PersistentClient(path=str(rag_db_dir))
    collection = client.get_or_create_collection(
        name=collection_name,
        metadata={"description": "Knowledge base for V8, JavaScript, C++, and fuzzing research"}
    )
    
    files_to_index = []
    for file_path in base_dir.rglob("*"):
        if file_path.is_file():
            if file_path.suffix == ".py":
                continue
            if file_path.name.startswith("."):
                continue
            if file_path.suffix in [".txt", ".md"]:
                files_to_index.append(file_path)
    
    print(f"Found {len(files_to_index)} files to index")
    
    batch_size = 100
    indexed_count = 0
    
    for i in range(0, len(files_to_index), batch_size):
        batch = files_to_index[i:i + batch_size]
        
        documents = []
        metadatas = []
        ids = []
        
        for file_path in batch:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
                
                if not content.strip():
                    continue
                
                topic = get_topic_from_path(file_path, base_dir)
                doc_id = compute_doc_id(file_path, base_dir)
                
                relative_name = str(file_path.relative_to(base_dir))
                
                formatted_content = f"Topic: {topic}\nFile: {relative_name}\n\n{content}"
                
                metadata = {
                    "topic": topic,
                    "filename": file_path.name,
                    "path": relative_name,
                    "extension": file_path.suffix,
                    "source": "knowlage_docs"
                }
                
                documents.append(formatted_content)
                metadatas.append(metadata)
                ids.append(doc_id)
                
            except Exception as e:
                print(f"Error processing {file_path}: {e}")
                continue
        
        if documents:
            try:
                texts_with_embeddings = [embeddings.embed_query(doc) for doc in documents]
                
                collection.add(
                    documents=documents,
                    metadatas=metadatas,
                    ids=ids,
                    embeddings=texts_with_embeddings
                )
                
                indexed_count += len(documents)
                print(f"Indexed {indexed_count}/{len(files_to_index)} files...")
                
            except Exception as e:
                print(f"Error adding batch to collection: {e}")
                continue
    
    print(f"\nIndexing complete! Total files indexed: {indexed_count}")
    print(f"Collection: {collection_name}")
    print(f"Database location: {rag_db_dir}")


def main():
    base_dir = Path(__file__).parent.resolve()
    
    if len(sys.argv) > 1:
        collection_name = sys.argv[1]
    else:
        collection_name = "v8_knowlagebase"
    
    print(f"Starting indexing of {base_dir}")
    index_files_to_rag(base_dir, collection_name)


if __name__ == "__main__":
    main()

