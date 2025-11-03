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

def collect_text_files(base_dir: Path) -> List[Dict[str, str]]:
    documents = []
    
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != '__pycache__']
        
        for file in files:
            if file.startswith('.'):
                continue
                
            filepath = Path(root) / file
            
            if file.endswith('.py') or file.endswith('.pyc'):
                continue
                
            if file.endswith('.txt') or file.endswith('.md'):
                try:
                    content = filepath.read_text(encoding='utf-8', errors='ignore')
                    
                    if len(content.strip()) == 0:
                        continue
                    
                    rel_path = filepath.relative_to(base_dir)
                    
                    if 'v8' in str(rel_path):
                        topic = 'V8 JavaScript Engine'
                    elif 'mdm_js' in str(rel_path) or 'mdn' in str(rel_path).lower():
                        topic = 'MDN JavaScript Reference'
                    elif 'cpp' in str(rel_path):
                        topic = 'C++ Standard Library'
                    elif 'whitepapers' in str(rel_path):
                        topic = 'Fuzzing Research Papers'
                    else:
                        topic = 'General Documentation'
                    
                    formatted_content = f"Topic: {topic}\nFile: {rel_path}\n\n{content}"
                    
                    documents.append({
                        'path': str(rel_path),
                        'topic': topic,
                        'content': formatted_content
                    })
                    
                    print(f"Collected: {rel_path}")
                    
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
    
    faiss.write_index(index, str(output_dir / 'v8_knowlagebase.index'))
    
    with open(output_dir / 'v8_knowlagebase_metadata.json', 'w') as f:
        json.dump(documents, f, indent=2)
    
    with open(output_dir / 'v8_knowlagebase_model.pkl', 'wb') as f:
        pickle.dump('all-MiniLM-L6-v2', f)
    
    print(f"\n Vector database saved to {output_dir}")
    print(f"  - Index: v8_knowlagebase.index")
    print(f"  - Metadata: v8_knowlagebase_metadata.json")
    print(f"  - Model info: v8_knowlagebase_model.pkl")
    print(f"\nTotal documents indexed: {len(documents)}")

def main():
    base_dir = Path(__file__).parent
    
    print(f"Scanning directory: {base_dir}")
    print("Collecting text files...\n")
    
    documents = collect_text_files(base_dir)
    
    if not documents:
        print("No documents found to index!")
        return
    
    output_dir = base_dir / 'v8_knowlagebase'
    create_vector_db(documents, output_dir)

if __name__ == '__main__':
    main()

