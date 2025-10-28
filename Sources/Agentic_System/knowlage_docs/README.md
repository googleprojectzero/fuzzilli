# V8 Knowledge Base

A comprehensive vector RAG database containing documentation for V8 JavaScript Engine, MDN JavaScript Reference, and C++ Standard Library.

## Contents

The knowledge base includes:
- **V8 JavaScript Engine**: Documentation from v8.dev
- **MDN JavaScript Reference**: JavaScript API documentation from developer.mozilla.org
- **C++ Standard Library**: Documentation from cppreference.com
- **Fuzzing Research Papers**: Academic papers and whitepapers on JavaScript engine fuzzing

Total documents indexed: **2752**

## Database Structure

```
knowlage_docs/
├── v8/                      # V8 engine documentation (HTML to TXT)
├── mdm_js/                  # MDN JavaScript docs (HTML to TXT)
├── cpp/                     # C++ reference docs (HTML to TXT)
└── v8_knowlagebase/         # FAISS vector database
    ├── v8_knowlagebase.index              # FAISS index file
    ├── v8_knowlagebase_metadata.json      # Document metadata
    └── v8_knowlagebase_model.pkl          # Embedding model info
```

## Requirements

```bash
pip3 install --user --break-system-packages numpy faiss-cpu sentence-transformers
```

## Usage

### Command Line Query

Use the query script to search the knowledge base:

```bash
cd Agentic_System/knowlage_docs
python3 query_rag.py "JavaScript array methods" 5
```

Arguments:
- First argument: Query string
- Second argument (optional): Number of results (default: 5)

### Python API

```python
from pathlib import Path
import json
import pickle
import faiss
from sentence_transformers import SentenceTransformer

base_dir = Path("knowlage_docs/v8_knowlagebase")

index = faiss.read_index(str(base_dir / "v8_knowlagebase.index"))

with open(base_dir / "v8_knowlagebase_metadata.json") as f:
    metadata = json.load(f)

with open(base_dir / "v8_knowlagebase_model.pkl", "rb") as f:
    model_name = pickle.load(f)

model = SentenceTransformer(model_name)

query = "How do JavaScript promises work?"
query_embedding = model.encode([query], convert_to_numpy=True)
distances, indices = index.search(query_embedding.astype('float32'), 5)

for idx, distance in zip(indices[0], distances[0]):
    doc = metadata[idx]
    print(f"Topic: {doc['topic']}")
    print(f"File: {doc['path']}")
    print(f"Similarity: {1.0 / (1.0 + distance):.3f}\n")
```

### Agent Tools

The knowledge base is integrated with the agentic system through `tools/rag_tools.py`:

```python
from tools.rag_tools import search_knowledge_base, get_knowledge_doc

results = search_knowledge_base(
    query="JavaScript array methods",
    top_k=3,
    topic_filter=""  # or "v8", "javascript", "cpp"
)

doc = get_knowledge_doc("v8/v8.dev/features/at-method.txt")
```

## Maintenance

### Re-crawling Documentation

To update the documentation:

```bash
# V8 docs
cd knowlage_docs/v8
python3 v8_crawler.py https://v8.dev --max-pages 50000 --delay 0.01

# MDN JavaScript docs
cd ../mdm_js
python3 mdn_js_crawler.py https://developer.mozilla.org/en-US/docs/Web/JavaScript --max-pages 50000 --delay 0.01

# C++ reference
cd ../cpp
python3 cppreference_crawler.py https://en.cppreference.com/w/cpp --max-pages 50000 --delay 0.01
```

### Converting HTML to Text

```bash
cd knowlage_docs
python3 html_to_text.py
```

### Re-indexing the Database

```bash
cd knowlage_docs
python3 index_to_rag_faiss.py
```

This will:
1. Scan all `.txt` and `.md` files in subdirectories
2. Create embeddings using `all-MiniLM-L6-v2` model
3. Build a FAISS index for fast semantic search
4. Save metadata and model information

## Technical Details

- **Embedding Model**: `all-MiniLM-L6-v2` (384 dimensions)
- **Vector Database**: FAISS with L2 distance
- **Document Format**: `Topic: {topic}\nFile: {path}\n\n{content}`
- **Topics**: Automatically detected from file paths (V8, MDN JS, C++)

## Example Queries

```bash
# JavaScript concepts
python3 query_rag.py "async await syntax" 3

# V8 engine features
python3 query_rag.py "V8 garbage collection" 5

# C++ standard library
python3 query_rag.py "std::vector operations" 3

# Array methods
python3 query_rag.py "map filter reduce" 3
```

## Notes

- All HTML files have been converted to plain text
- Original HTML files have been removed to save space
- The database uses semantic search for intelligent retrieval
- Documents are automatically categorized by topic based on their source

