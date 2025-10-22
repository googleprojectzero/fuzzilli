#!/usr/bin/env python3



from smolagents import LiteLLMModel, ToolCallingAgent
from BaseAgent import Agent
from EBG import EBG
from pathlib import Path #a


class Father(Agent):
    def setup_agents(self):
        # L2 Worker: EBG
        self.agents['george_foreman'] = ToolCallingAgent(
            name="GeorgeForeman",
            description="L2 Worker responsible for generating JavaScript programs and fuzzing corpus",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=10,
            planning_interval=None,
        )

        # L2 Worker: Reviwer of Code (under CodeAnalyzer)

        self.agents['reviewer_of_code'] = ToolCallingAgent(
            name="ReviewerOfCode",
            description="L2 Worker responsible for reviewing code from various sources using RAG database",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['george_foreman']
            ], 
            max_steps=10,
            planning_interval=None,
            system_prompt=self.get_prompt('reviewer_of_code.txt'),
        )
        
        # L2 Worker: V8 Search (under CodeAnalyzer)

        self.agents['v8_search'] = ToolCallingAgent(
            name="V8Search",
            description="L2 Worker responsible for searching V8 source code using fuzzy find, regex, and compilation tools",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=10,
            planning_interval=None,
            system_prompt=self.get_prompt('v8_search.txt'),
        )

        # L1 Manager: Code Analysis Agent

        self.agents['code_analyzer'] = ToolCallingAgent(
            name="CodeAnalyzer",
            description="L1 Manager responsible for analyzing code and coordinating retrieval and V8 search operations",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['retriever_of_code'],
                self.agents['v8_search']
            ],
            max_steps=15,
            planning_interval=None,
            system_prompt=self.get_prompt('code_analyzer.txt'),
        )
        
        # L1 Manager: Program Builder Agent  
        self.agents['program_builder'] = ToolCallingAgent(
            name="ProgramBuilder",
            description="L1 Manager responsible for building program templates using corpus and context",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['george_foreman']
            ],
            max_steps=15,
            planning_interval=None,
            system_prompt=self.get_prompt('program_builder.txt'),
        )
        
        # L0 Root Manager Agent
        self.agents['father_of_george'] = ToolCallingAgent(
            name="FatherOfGeorge",
            description="L0 Root Manager responsible for orchestrating code analysis and program building operations",
            tools=[],
            model=LiteLLMModel(model_id="gpt-5-mini", api_key=self.api_key),
            managed_agents=[
                self.agents['code_analyzer'],
                self.agents['program_builder']
            ],
            max_steps=20,
            planning_interval=None,
            system_prompt=self.get_prompt('root_manager.txt'),
        )
    

    def get_prompt(self, prompt_name: str) -> str:
        f = open(Path(__file__).parent / "prompts_FOG" / prompt_name, 'r')
        prompt = f.read()
        f.close()
        return prompt


    def run_task(self, task_description: str, context: dict = None) -> dict:
        results = {
            "task_description": task_description,
            "completed": False,
            "output": None,
            "error": None,
        }
        return results




def main():
    # Init model
    model = LiteLLMModel(
        model_id="gpt-5-mini",
        api_key="<key>"
    )
    
    system = Father(model)
    
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