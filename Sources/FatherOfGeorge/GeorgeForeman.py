#!/usr/bin/env python3
'''
Child of the Father of George. Thus, George.
L1 Manager Agent - Verification and Testing Coordinator
'''

from smolagents import LiteLLMModel, ToolCallingAgent
from BaseAgent import Agent, get_manager_tools, get_corpus_generation_tools, get_runtime_analysis_tools, get_validation_tools, get_code_analysis_tools


class George(Agent):
    """Verify and test seeds."""
    
    def setup_agents(self):
        # L3 Worker: Code Analyzer (under RuntimeAnalyzer)
        self.agents['code_analyzer'] = ToolCallingAgent(
            name="CodeAnalyzer",
            description="L3 Worker responsible for analyzing code patterns, vulnerabilities, and specific components for runtime analysis",
            tools=get_code_analysis_tools(),
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=8,  # Fewer steps than L1 CodeAnalyzer
            planning_interval=None,
        )
        
        # L2 Worker: Corpus Generator (under George)
        self.agents['corpus_generator'] = ToolCallingAgent(
            name="CorpusGenerator",
            description="L2 Worker responsible for generating seeds from the corpus and validating syntax/semantics",
            tools=get_corpus_generation_tools(),
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=10,
            planning_interval=None,
        )
        
        # L2 Worker: Runtime Analyzer (under George)
        self.agents['runtime_analyzer'] = ToolCallingAgent(
            name="RuntimeAnalyzer",
            description="L2 Manager responsible for analyzing program runtime, coverage, and execution state",
            tools=get_runtime_analysis_tools(),
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[
                self.agents['code_analyzer']
            ],
            max_steps=10,
            planning_interval=None,
        )
        
        # L2 Worker: Corpus Validator (under George)
        self.agents['corpus_validator'] = ToolCallingAgent(
            name="CorpusValidator",
            description="L2 Worker responsible for validating corpus integrity and quality",
            tools=get_validation_tools(),
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=8,
            planning_interval=None,
        )
        
        # L2 Worker: DB Analyzer (under George)
        self.agents['db_analyzer'] = ToolCallingAgent(
            name="DBAnalyzer",
            description="L2 Worker responsible for analyzing PostgreSQL database for corpus, flags, coverage, and execution state",
            tools=get_validation_tools(),  # Reusing validation tools for DB analysis
            model=LiteLLMModel(model_id="gpt-5", api_key=self.api_key),
            managed_agents=[],
            max_steps=8,
            planning_interval=None,
        )
        
        # L1 Manager Agent: George Foreman
        self.agents['george_foreman'] = ToolCallingAgent(
            name="GeorgeForeman",
            description="L1 Manager responsible for verifying JavaScript programs for correctness and testing them to evaluate interestingness",
            tools=get_manager_tools(),
            model=LiteLLMModel(model_id="gpt-5-mini", api_key=self.api_key),
            managed_agents=[
                self.agents['corpus_generator'],
                self.agents['runtime_analyzer'],
                self.agents['corpus_validator'],
                self.agents['db_analyzer']
            ],
            max_steps=15,
            planning_interval=None,
        )

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
    
    system = George(model)
    
    # run task
    result = system.run_task(
        task_description="Verify and test JavaScript program seeds",
        context={
            "CorpusGenerator": "Generate and validate seeds from corpus",
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