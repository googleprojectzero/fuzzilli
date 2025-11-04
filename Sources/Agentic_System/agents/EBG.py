#!/usr/bin/env python3
'''
Ethiopian BG
L0 Manager Agent - Runtime analysis and issue solev
'''

from smolagents import LiteLLMModel, ToolCallingAgent
from agents.BaseAgent import Agent
from pathlib import Path
from tools.EBG_tools import *
from tools.rag_tools import (
    search_rag_db, 
    list_rag_db,
    get_rag_doc,
    search_knowledge_base,
    get_knowledge_doc,
    search_v8_source_rag,
    get_v8_source_rag_doc,
)
import sys
import yaml 
import importlib.resources
sys.path.append(str(Path(__file__).parent.parent))
from config_loader import get_openai_api_key, get_anthropic_api_key


class EBG(Agent): 
    """Verify and test seeds."""
    
    def setup_agents(self):
        # L3 Worker: Code Analyzer (under RuntimeAnalyzer)
        system_prompt = self.get_prompt("code_analyzer.txt")
        self.agents['code_analyzer'] = ToolCallingAgent(
            name="CodeAnalyzer",
            description="L3 Worker responsible for analyzing code patterns, vulnerabilities, and specific components for runtime analysis",
            tools=[
                search_rag_db,
                list_rag_db,
                get_rag_doc,
                search_knowledge_base,
                get_knowledge_doc,
                search_v8_source_rag,
                get_v8_source_rag_doc,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            max_steps=8,  # Fewer steps than L1 CodeAnalyzer
            planning_interval=None,
        )
        self.agents['code_analyzer'].prompt_templates["system_prompt"] = system_prompt

        # L2 Worker: Corpus Validator (under RuntimeAnalyzer)
        system_prompt = self.get_prompt("corpus_validator.txt")
        self.agents['corpus_validator'] = ToolCallingAgent(
            name="CorpusValidator",
            description="L2 Worker responsible for validating corpus integrity and quality",
            tools=[
                # Add corpus validation tools here
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            max_steps=8,
            planning_interval=None,
        )
        self.agents['corpus_validator'].prompt_templates["system_prompt"] = system_prompt
        
        # L2 Manager: Runtime Analyzer (under George)
        system_prompt = self.get_prompt("runtime_analyzer.txt")
        self.agents['runtime_analyzer'] = ToolCallingAgent(
            name="RuntimeAnalyzer",
            description="L2 Manager responsible for analyzing program runtime, coverage, and execution state",
            tools=[
                search_rag_db,
                list_rag_db,
                get_rag_doc,
                search_knowledge_base,
                get_knowledge_doc,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['code_analyzer'],
                self.agents['corpus_validator']
            ],
            max_steps=10,
            planning_interval=None,
        )
        self.agents['runtime_analyzer'].prompt_templates["system_prompt"] = system_prompt
        
        # L2 Worker: DB Analyzer (under George)
        system_prompt = self.get_prompt("db_analyzer.txt")
        self.agents['db_analyzer'] = ToolCallingAgent(
            name="DBAnalyzer",
            description="L2 Worker responsible for analyzing PostgreSQL database for corpus, flags, coverage, and execution state",
            tools=[
                # Add database analysis tools here
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            max_steps=8,
            planning_interval=None,
        )
        self.agents['db_analyzer'].prompt_templates["system_prompt"] = system_prompt
        
        # L0 Manager: George Foreman (Root Agent)
        try:
            default_templates = yaml.safe_load(
                importlib.resources.files("smolagents.prompts").joinpath("toolcalling_agent.yaml").read_text()
            )
        except (ModuleNotFoundError, AttributeError):
            template_path = Path(__file__).parent.parent / "smolagent-fork" / "prompts" / "toolcalling_agent.yaml"
            if template_path.exists():
                with open(template_path, 'r') as f:
                    default_templates = yaml.safe_load(f.read())
            else:
                raise FileNotFoundError(f"Could not find toolcalling_agent.yaml template at {template_path}")
        
        custom_prompt = self.get_prompt("george_foreman.txt")
        self.agents['george_foreman'] = ToolCallingAgent(
            name="GeorgeForeman",
            description="L0 Manager responsible for verifying JavaScript programs for correctness and testing them to evaluate interestingness",
            tools=[
                search_rag_db,
                list_rag_db,
                get_rag_doc,
                search_knowledge_base,
                get_knowledge_doc,
                search_v8_source_rag,
                get_v8_source_rag_doc,
            ],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['runtime_analyzer'],
                self.agents['corpus_validator'],
                self.agents['db_analyzer']
            ],
            max_steps=20,
            planning_interval=None,
            prompt_templates=default_templates,
        )
        self.agents['george_foreman'].prompt_templates["system_prompt"] = custom_prompt

    def get_prompt(self, prompt_name: str) -> str:
        f = open(Path(__file__).parent.parent / "prompts" / "EBG-prompts" / prompt_name, 'r')
        prompt = f.read()
        f.close()
        return prompt

    def start_system(self):
        result = self.run_task(
            task_description="Initialize EBG orchestration for runtime analysis and seed verification",
            context={
                "GeorgeForeman": "Primary orchestrator responsible for verifying and testing JavaScript programs",
                "RuntimeAnalyzer": "Analyze program runtime, coverage, and execution state",
                "CorpusValidator": "Validate corpus quality and integrity",
                "DBAnalyzer": "Analyze PostgreSQL database for execution information"
            }
        )
        print("EBG start result:")
        print(f"Completed: {result['completed']}")
        if result['output']:
            print(f"Output: {result['output']}")
        if result['error']:
            print(f"Error: {result['error']}")
        return result


def main():
    openai_key = get_openai_api_key()
    anthropic_key = get_anthropic_api_key()
    
    model = LiteLLMModel(
        model_id="gpt-5-mini",
        #model_id="gpt-5",
        api_key=openai_key
    )
    
    system = EBG(model, api_key=openai_key, anthropic_api_key=anthropic_key)
    
    # run task
    result = system.run_task(
        task_description="Verify and test JavaScript program seeds",
        context={
            "GeorgeForeman": "Orchestrate verification and testing of JavaScript programs",
            "RuntimeAnalyzer": "Analyze program execution and coverage",
            "CorpusValidator": "Validate corpus quality and integrity",
            "DBAnalyzer": "Analyze database for execution information"
        }
    )
    
    print("Task Result:")
    print(f"Completed: {result['completed']}")
    print(f"Output: {result['output']}")
    if result['error']:
        print(f"Error: {result['error']}")


if __name__ == "__main__":
    main()

###
# we need tool calls for EBG to be able to actually put the program templates hard coded into the actual execution of fuzzili  
###
