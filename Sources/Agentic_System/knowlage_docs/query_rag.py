#!/usr/bin/env python3

import json
import pickle
import sys
from pathlib import Path
from typing import List, Dict, Tuple

try:
    import numpy as np
    from sentence_transformers import SentenceTransformer
    import faiss
except ImportError as e:
    print(f"Error: {e}")
    print("Install with: pip3 install --user --break-system-packages numpy sentence-transformers faiss-cpu")
    sys.exit(1)

class RAGDatabase:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        
        if not db_path.exists():
            raise FileNotFoundError(f"Database directory not found: {db_path}")
        
        index_file = db_path / 'v8_knowlagebase.index'
        metadata_file = db_path / 'v8_knowlagebase_metadata.json'
        model_file = db_path / 'v8_knowlagebase_model.pkl'
        
        if not all([index_file.exists(), metadata_file.exists(), model_file.exists()]):
            raise FileNotFoundError("Database files incomplete")
        
        self.index = faiss.read_index(str(index_file))
        
        with open(metadata_file, 'r') as f:
            self.metadata = json.load(f)
        
        with open(model_file, 'rb') as f:
            model_name = pickle.load(f)
        
        self.model = SentenceTransformer(model_name)
        
        print(f"Loaded RAG database with {len(self.metadata)} documents")
    
    def search(self, query: str, top_k: int = 5) -> List[Tuple[Dict, float]]:
        query_embedding = self.model.encode([query], convert_to_numpy=True)
        
        distances, indices = self.index.search(query_embedding.astype('float32'), top_k)
        
        results = []
        for idx, distance in zip(indices[0], distances[0]):
            if idx < len(self.metadata):
                doc = self.metadata[idx]
                similarity = 1.0 / (1.0 + distance)
                results.append((doc, similarity))
        
        return results
    
    def print_results(self, results: List[Tuple[Dict, float]]):
        for i, (doc, score) in enumerate(results, 1):
            print(f"\n{'='*80}")
            print(f"Result {i} (Similarity: {score:.3f})")
            print(f"Topic: {doc['topic']}")
            print(f"File: {doc['path']}")
            print(f"{'='*80}")
            
            content = doc['content']
            lines = content.split('\n')
            
            preview_lines = lines[:20]
            print('\n'.join(preview_lines))
            
            if len(lines) > 20:
                print(f"\n... ({len(lines) - 20} more lines)")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 query_rag.py <query> [top_k]")
        print("\nExample:")
        print("  python3 query_rag.py 'JavaScript array methods' 5")
        sys.exit(1)
    
    query = sys.argv[1]
    top_k = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    
    db_path = Path(__file__).parent / 'v8_knowlagebase'
    
    print(f"Loading RAG database from: {db_path}\n")
    rag = RAGDatabase(db_path)
    
    print(f"\nSearching for: '{query}' (top {top_k} results)\n")
    results = rag.search(query, top_k)
    
    rag.print_results(results)

if __name__ == '__main__':
    main()

