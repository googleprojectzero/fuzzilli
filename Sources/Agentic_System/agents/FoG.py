#!/usr/bin/env python3

from smolagents import LiteLLMModel, ToolCallingAgent, WebSearchTool
from agents.BaseAgent import Agent
from agents.EBG import EBG
from pathlib import Path 
from tools.FoG_tools import *
from tools.rag_tools import (
    set_rag_collection,
    get_rag_collection,
    search_rag_db,
    update_rag_db,
    delete_rag_db,
    list_rag_db,
    get_rag_doc,
    search_knowledge_base,
    get_knowledge_doc,
    FAISSKnowledgeBase,
)
import sys
sys.path.append(str(Path(__file__).parent.parent))
from config_loader import get_openai_api_key, get_anthropic_api_key


class Father(Agent):

    def setup_agents(self):
        # Pre-warm FAISS knowledge base to avoid first-call latency
        # while not :
        #     print("Waiting for FAISSKnowledgeBase to be initialized...")
        #     time.sleep(1)   
        # FAISSKnowledgeBase.get_instance()
        # L2 Worker: EBG
        system_prompt=self.get_prompt("george_forman.txt")
        self.agents['george_foreman'] = ToolCallingAgent(
            name="GeorgeForeman",
            description="L2 Worker responsible for validating program templates built by the program builder",
            tools=[
                # templates.json access (generation-focused)
                get_all_template_names,
                get_template_by_name,
                get_random_template_swift,
                get_random_template_fuzzil,
                search_template_file_json,
                search_regex_template_swift,
                search_regex_template_fuzzil,
                similar_template_swift,
                similar_template_fuzzil,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=20,
            planning_interval=None
        )
        self.agents['george_foreman'].prompt_templates["system_prompt"] = system_prompt

        # L2 Worker: Retriever of Code (under CodeAnalyzer)
        self.agents['reviewer_of_code'] = ToolCallingAgent(
            name="ReviewerOfCode",
            description="L2 Worker responsible for reviewing code from various sources using RAG database",
            tools=[run_d8,
                fuzzy_finder,
                ripgrep,
                tree,
                WebSearchTool(),
                search_rag_db,
                search_knowledge_base,
                get_rag_doc,
                get_knowledge_doc,
                set_rag_collection,
                get_rag_collection,
                update_rag_db,
                delete_rag_db,
                list_rag_db,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            max_steps=20,
            planning_interval=None,
        )
        self.agents['reviewer_of_code'].prompt_templates["system_prompt"] = self.get_prompt("reviewer_of_code.txt")
        
        # L2 Worker: V8 Search (under CodeAnalyzer)
        system_prompt=self.get_prompt("v8_search.txt"),
        self.agents['v8_search'] = ToolCallingAgent(
            name="V8Search",
            description="L2 Worker responsible for searching V8 source code using fuzzy find, regex, and compilation tools",
            tools=[
                fuzzy_finder,
                ripgrep,
                tree,
                read_rag_db_id,
                write_rag_db_id,
                init_rag_db,
                read_file,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),  
            max_steps=15,
            planning_interval=None,
        )
        self.agents['v8_search'].prompt_templates["system_prompt"] = self.get_prompt("v8_search.txt")

        # L1 Manager: Code Analysis Agent
        self.agents['code_analyzer'] = ToolCallingAgent(
            name="CodeAnalyzer",
            description="L1 Manager responsible for analyzing code and coordinating retrieval and V8 search operations",
            tools=[
                run_python, 
                lift_fuzzil_to_js,
                compile_js_to_fuzzil, 
                WebSearchTool(),
                # RAG collection management
                set_rag_collection,
                get_rag_collection,
                # Chroma-based RAG queries
                search_rag_db,
                update_rag_db,
                delete_rag_db,
                list_rag_db,
                get_rag_doc,
                # FAISS knowledge base queries
                search_knowledge_base,
                get_knowledge_doc,
                read_rag_db_id,
                 
                ], # add rag db tools here aswell
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['reviewer_of_code'], 
                self.agents['v8_search']
                ],
            max_steps=15,
            planning_interval=None,
        )
        self.agents['code_analyzer'].prompt_templates["system_prompt"] = self.get_prompt("code_analyzer.txt")
        
        # L1 Manager: Program Builder Agent  
        self.agents['program_builder'] = ToolCallingAgent(
            name="ProgramBuilder",
            description="L1 Manager responsible for building program templates using corpus and context",
            tools=[
                run_d8,
                get_all_template_names,
                get_template_by_name,
                get_random_template_swift,
                get_random_template_fuzzil,
                search_template_file_json,
                search_regex_template_swift,
                search_regex_template_fuzzil,
                similar_template_swift,
                similar_template_fuzzil,
            ], # add rag db stuff here aswell
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['george_foreman']
            ],
            max_steps=30,
            planning_interval=None,
        )
        self.agents['program_builder'].prompt_templates["system_prompt"] = self.get_prompt("program_builder.txt")

        # L1 Root: pick_section
        self.agents['pick_section'] = ToolCallingAgent(
            name="PickSection",
            description="L0 Root Manager responsible for picking a section of the V8 code base that targets the JIT system",
            tools=[
                search_js_file_name_by_pattern,
                get_js_entry_data_by_name,
                get_all_js_file_names,
                get_random_entry_data,
                search_knowledge_base,
                get_knowledge_doc,
            ],
            model=LiteLLMModel(model_id="gpt-5-mini", api_key=self.api_key),
            max_steps=20,
            planning_interval=None,
        )
        self.agents['pick_section'].prompt_templates["system_prompt"] = self.get_prompt("pick_section.txt")
        
        # L0 Manager: Father of George 
        self.agents['father_of_george'] = ToolCallingAgent(
            name="FatherOfGeorge",
            description="L1 Manager responsible for orchestrating code analysis and program building operations",
            tools=[
                # RAG collection management
                set_rag_collection,
                get_rag_collection,
                # Chroma-based RAG queries
                search_rag_db,
                update_rag_db,
                delete_rag_db,
                list_rag_db,
                get_rag_doc,
                # FAISS knowledge base queries
                search_knowledge_base,
                get_knowledge_doc,
            ],
            model=LiteLLMModel(model_id="gpt-5-mini", api_key=self.api_key),
            managed_agents=[
                self.agents['code_analyzer'],
                self.agents['program_builder'],
                self.agents['pick_section']
            ],
            max_steps=30,
            planning_interval=None,
        )
        self.agents['father_of_george'].prompt_templates["system_prompt"] = self.get_prompt("root_manager.txt")


    

    def get_prompt(self, prompt_name: str) -> str:
        f = open(Path(__file__).parent.parent / "prompts" / "FoG-prompts" / prompt_name, 'r')
        prompt = f.read()
        f.close()
        return prompt 
    


    def start_system(self):
        """Kick off the FoG agentic system by running an initial orchestration task."""
        result = self.run_task(
            task_description="Initialize FoG orchestration across PickSection, FatherOfGeorge, CodeAnalyzer, and ProgramBuilder",
            context={
                "PickSection": "Select a promising V8 subsystem or JIT-related area to explore",
                "FatherOfGeorge": "Coordinate between analysis and program generation",
                "CodeAnalyzer": "Analyze V8 code and knowledge bases to guide fuzz inputs",
                "ProgramBuilder": "Synthesize JavaScript programs and templates for fuzzing"
            }
        )
        print("FoG start result:")
        print(f"Completed: {result['completed']}")
        if result['output']:
            print(f"Output: {result['output']}")
        if result['error']:
            print(f"Error: {result['error']}")
        return result

    # def run_task(self, task_description: str, context: dict = None) -> dict:
    #     self.set

    #     return results

def main():
    openai_key = get_openai_api_key()
    anthropic_key = get_anthropic_api_key()
    
    model = LiteLLMModel(
        model_id="gpt-5-mini",
        api_key=openai_key
    )
    
    system = Father(model, api_key=openai_key, anthropic_api_key=anthropic_key)
    
    # run task
    result = system.run_task(
        task_description="Initialize corpus generation for V8 fuzzing",
        context={
            "CodeAnalyzer": "Analyze V8 source code for patterns. vulnerabilities. specifc components, etc...",
            "ProgramBuilder": "Build JavaScript programs using corpus and context"
        }
    )
    
    print("Task Result:")
    print(f"Completed: {result['completed']}")
    print(f"Output: {result['output']}")
    if result['error']:
        print(f"Error: {result['error']}")


if __name__ == "__main__":
    main()


# L0 Root: pick_section
# ├── L1 Manager: father_of_george
#     ├── L1 Manager: code_analyzer
#     │   ├── L2 Worker: reviewer_of_code
#     │   └── L2 Worker: v8_search
#     └── L1 Manager: program_builder
#         └── L2 Worker: george_foreman