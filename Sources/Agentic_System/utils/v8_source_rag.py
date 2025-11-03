#!/usr/bin/env python3

import os
import sys
from pathlib import Path
from typing import List, Dict
import json
import pickle

try:
    import numpy as np
    from sentence_transformers import SentenceTransformer
    import faiss
except ImportError as e:
    print(f"Error: {e}")
    print("Install with: pip3 install --user --break-system-packages numpy sentence-transformers faiss-cpu")
    sys.exit(1)

# Try importing V8_PATH from tools/common_tools.py, handling import path whether run directly or as a module
try:
    from tools.common_tools import V8_PATH
except ModuleNotFoundError:
    try:
        # Fallback: Add parent directories to sys.path and try importing again
        import sys
        import pathlib
        script_dir = pathlib.Path(__file__).resolve().parent
        sys.path.insert(0, str(script_dir.parent))
        from tools.common_tools import V8_PATH
    except Exception as e:
        print(f"Failed to import V8_PATH from tools.common_tools: {e}")
        sys.exit(1)

V8_TEXT_EXTENSIONS = {'.cc', '.h', '.cpp', '.hpp', '.c', '.js', '.ts', '.json', '.txt', '.md', '.torque'}

def collect_text_files(base_dir: Path) -> List[Dict[str, str]]:
    documents = []
    
    if not base_dir.exists():
        print(f"Error: V8 directory does not exist: {base_dir}")
        sys.exit(1)
    
    print(f"Scanning V8 directory: {base_dir}")
    
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != '__pycache__' and d != 'out']
        
        for file in files:
            if file.startswith('.'):
                continue
            
            filepath = Path(root) / file
            
            if filepath.suffix.lower() not in V8_TEXT_EXTENSIONS:
                continue
            
            try:
                content = filepath.read_text(encoding='utf-8', errors='ignore')
                
                if len(content.strip()) == 0:
                    continue
                
                rel_path = filepath.relative_to(base_dir)
                sub_dir = rel_path.parts[0] if len(rel_path.parts) > 1 else 'root'
                
                topic = f"V8 {sub_dir}"
                
                formatted_content = f"Topic: {topic}\nFile: {rel_path}\n\n{content}"
                
                documents.append({
                    'path': str(rel_path),
                    'topic': topic,
                    'content': formatted_content
                })
                
                if len(documents) % 100 == 0:
                    print(f"Collected {len(documents)} documents...")
                
            except Exception as e:
                print(f"Error reading {filepath}: {e}")
                continue
    
    return documents

def create_vector_db(documents: List[Dict[str, str]], output_dir: Path):
    print(f"\nCreating embeddings for {len(documents)} documents...")
    
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    contents = [doc['content'] for doc in documents]
    embeddings = model.encode(contents, show_progress_bar=True, convert_to_numpy=True)
    
    print(f"\nCreated embeddings with shape: {embeddings.shape}")
    
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    faiss.write_index(index, str(output_dir / 'v8_source_rag.index'))
    
    with open(output_dir / 'v8_source_rag_metadata.json', 'w') as f:
        json.dump(documents, f, indent=2)
    
    with open(output_dir / 'v8_source_rag_model.pkl', 'wb') as f:
        pickle.dump('all-MiniLM-L6-v2', f)
    
    print(f"\nVector database saved to {output_dir}")
    print(f"  - Index: v8_source_rag.index")
    print(f"  - Metadata: v8_source_rag_metadata.json")
    print(f"  - Model info: v8_source_rag_model.pkl")
    print(f"\nTotal documents indexed: {len(documents)}")

def main():
    if not V8_PATH:
        print("Error: V8_PATH environment variable not set")
        print("Do: export V8_PATH='path to v8 base dir'")
        print("Example: export V8_PATH=/path/to/v8/v8/src")
        sys.exit(1)
    
    base_dir = Path(V8_PATH)
    
    print(f"Scanning V8 directory: {base_dir}")
    print("Collecting text files from all subdirectories...\n")
    
    documents = collect_text_files(base_dir)
    
    if not documents:
        print("No documents found to index!")
        return
    
    print(f"\nTotal documents collected: {len(documents)}")
    
    output_dir = Path(__file__).parent.parent / 'rag_db' / 'v8_source_rag'
    print(f"Saving to: {output_dir}")
    create_vector_db(documents, output_dir)

if __name__ == '__main__':
    main()