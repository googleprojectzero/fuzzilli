### How to run FoG
1. Install the `requirements.txt`, make sure you're in a venv
2. export the required environment variables
- `V8_PATH` => points to V8 src directory
- `D8_PATH` => points to the d8 binary
- `FUZZILLI_TOOL_BIN` => points to the FuzzILTool binary, typically under .build in Fuzzilli's root
- `FUZZILLI_PATH` => points to Fuzzilli's root directory, where you land after cloning and cd'ing into the repo
3. Put your OpenAI key into a `keys.cfg` in Sources/Agentic_System
4. Replace the smolagents site-packaged located in `.venv/lib/python3.12/site-packages` or similar with the provided fork of smolagents<br>
    You can simply remove the existing smolagents in site-packages and move + rename the fork as `smolagents`
5. run `python3 rises-the-fog.py (--debug)`

### Technical flow
#### The first multi agent system is implemented and starts by initializing a root manager whose goal is to actually orchestrate the creation of program templates. It starts by selecting a "code region" that it determines to be interesting; this is done by querying a RAG DB (json file) that contains over 8000 regression tests, their FuzzIL form, and execution data via trace flags.  We instruct the system to select a code region by using the execution data. On top of that, the system has access to a vector RAG DB with: V8 docs, JS MDM docs, C++ docs, and various research papers that it can query to gather more information. The vectorization library we use is META’s FAISS -"Facebook AI Similarity Search". After this is done it will select a code region such as: "Keyed array element access & elements-kind transitions (KeyedStoreIC/KeyedLoadIC, ElementsTransition, GrowElements/CopyElements, and Array builtin fast paths)".


#### From there we run a code analysis agent whose goal is to actually figure out what the code region looks like in the V8 code base and give back an in depth analysis of the code region - functions / files that are deemed "interesting". We give the V8 search agent, who is responsible for querying and searching through the source code, a variety of tools like ripgrep, fuzzyfinder, and sed in order to read files.  This agent will create a run-time RAG in order to store interesting code chunks. We use tool calls that create controlled, structured json in order to create the runtime RAG that gets used between agents. After V8 search completes and generates a list of relevant database entries linked to the initial code region, the code analysis stage compiles a comprehensive summary of the codebase and its functions. It then sends a detailed explanation - along with supporting code snippets - to the verification agent. Once the response is verified, the finalized version is returned to the root manager.


#### From here our system will define a task to literally create swift program templates. This will be sent to an agentic ‘program template builder’, which itself has a RAG json filled with program templates, their FuzzIL equivalence, and JS which we got by dumping runtime info via a Fuzzilli patch. This stage also has a verification agent, and if all goes well, we have tools to ensure compilation and test that target code paths are being hit, namely by looking at d8 trace output.

```
>> Start Initializaiton
-> PickSection -> FoG -> CodeAnalyzer: Reviewer_of_Code, V8_Search -> FoG 
-> ProgramBuilder: Corpus_Generator, Runtime_Analyzer, Corpus_Validator, DB_Analyzer, George_Foreman, Compiler 
>> End Initialization []
```

- PickSection: chooses a component of V8 that targets/interfaces with JIT.
- FoG : Init root agent (similar to an IPC).
- CodeAnalyzer: Manager agent to Reviewer_of_Code and V8_Search. Makes overall decisions regarding target.
    - Reviewer_of_Code: references design docs, whitepapers, and regressions regarding the selected V8 
            component, build context, and select a region of code within that component to target.
    - V8_Search: Uses tools to analyze source code and pull entire functions and files related to the target
            and contextual functions related to those selected functions. The agents tend to target places with 
            DCHECKS as this is an indicator of where state can be potentially corrupt. 
- ProgramBuilder: Manages construction of program templates that target the code paths found by CodeAnalyzer.
    - Corpus_Generator:
    - Corpus_Validator:
    - Runtime_Analyzer:
    - Corpus_Validator:
    - Compiler:
- George Foreman: Verification agent used to validate that results and 
        trajectory of other agents are inline with their goals.


```
The below is wrong for now btw

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
