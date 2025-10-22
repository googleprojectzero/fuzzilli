### `Father of George (FoG)` is the Initialization agent for our program template builder. Execution will start in the L0 root/manager agent which is in charge of 2 main agents: `Code analysis` agent and `Program(Template) Builder` agent. 
* ##### Starting with the `Code Analysis` agent: it has access to 2 sub-agents: `Retriever of Code`(RoC) and `V8 Search`. RoC has access to a vector RAG database that it can query for information from sources like cppdev, gpz, v8.dev, mdn, various whitepapers, as well as another sub agent `George Foreman` that can verify the semantics/logic of the information RoC wants to pass along. The other L2 sub agent, V8 Search, does exactly what it says. It uses tool calls like fuzzyfind(fzf) and regex(grep) to analyze specific parts of V8 src for context and seed gen. Also has the ability to compiler with clang and test with python as well as view the V8 call graph up to the point where a program would be analyzed. Also will have access to the internet so that it can quickly look up things it needs to know.
* ##### - The other L1 agent is the `Program Template Builder`. The most important part of this agent is it's access to the PostgreSQL database that will contain our existing corpus- unique and interesting javascript(/FuzzIL) programs. Ideally it will use these existing programs to make a new-interesting programs by combining the context garnered from code analysis agent as well as from a RAG db of various JS PoCs and program templates. After building an initial seed program it will be analyzed by the George Foreman agent for correctness and added to the PostgreSQL db to start the fuzzing instance. 


#### `George Foreman` is the verification agent that has 2 main l1 agents (given it's context): `Corpus Generation` and `Runtime Analysis`. 
Corpus Gen is responsible for taking in test inputs/seeds from the PostgreSQL db and PoCs from the RAG db. Here it will validate the Syntactical and Semantical correctness of the seeds for which it will then call the `test` tool- this is where `Runtime Analysis` comes in. 
It has access to the PostgreSQL db which besides the corpus, contains information such as what flags the program was run with, what sort of coverage it hit, and ideally it's execution state. (also a 'list tree'. don't know what this does.) After analyzing the seed and it's corresponding execution information, it can determine whether or not it was a good seed and if it should be added back/taken out of the db. 

```
FatherOfGeorge (L0 Manager)
├── CodeAnalyzer (L1 Manager)
│   ├── RetrieverOfCode (L2 Worker) → GeorgeForeman
│   └── V8Search (L2 Worker)
└── ProgramBuilder (L1 Manager)
    └── GeorgeForeman (L1 Manager)
        ├── CorpusGenerator (L2 Worker)
        ├── RuntimeAnalyzer (L2 Manager)
        │   └── CodeAnalyzer (L3 Worker)
        ├── CorpusValidator (L2 Worker)
        └── DBAnalyzer (L2 Worker)
```

---

```
This is all my interpretation of the agentic system, and I'm sure my understanding of the George Foreman agent is skewed- feel free to correct my mistakes.

I'd like to clarify this agent is specifically for corpus initialization- at the start of a fuzzing campaign. Yes we can expect it to be slower due to it's various API and MCP calls but that will resolve itself after the initialization phase has passed.
```