#!/usr/bin/env python3

import threading
import time
from abc import ABC, abstractmethod
from pathlib import Path

from smolagents import LiteLLMModel, ToolCallingAgent


class Agent(ABC):
    """Base class for AI agents."""
    
    def __init__(self, model: LiteLLMModel, api_key: str = None, anthropic_api_key: str = None):
        self.model = model
        self.api_key = api_key
        self.anthropic_api_key = anthropic_api_key
        self.agents = {}
        self.setup_agents()

        # Rate limiting configuration
        self.min_request_interval = 1.0  # Minimum seconds between requests
        self.last_request_time = None
        self.request_lock = threading.Lock()

    def wait_for_rate_limit(self):
        """Ensure minimum time between requests."""
        with self.request_lock:
            if self.last_request_time:
                elapsed = time.time() - self.last_request_time
                if elapsed < self.min_request_interval:
                    sleep_time = self.min_request_interval - elapsed
                    print(f"Rate limiting: waiting {sleep_time:.2f} seconds...")
                    time.sleep(sleep_time)
            self.last_request_time = time.time()
            
    def get_prompt(self, prompt_name: str) -> str:
        """Load prompt template from file."""
        prompt_path = Path(__file__).parent / "prompts" / prompt_name
        if prompt_path.exists():
            with open(prompt_path, 'r') as f:
                return f.read()
        return ""
    
    @abstractmethod
    def setup_agents(self):
        """Setup agents specific to this agent."""
        pass
    
    def get_manager_agent(self) -> ToolCallingAgent: 
        """Get the main manager agent for this system."""
        # Try to find father_of_george first
        if 'father_of_george' in self.agents:
            return self.agents['father_of_george']
        
        # Look for agents with 'Manager' in their description or name
        for key, agent in self.agents.items():
            if hasattr(agent, 'description') and 'Manager' in agent.description:
                return agent
            if hasattr(agent, 'name') and 'Manager' in agent.name:
                return agent
        
        # Fallback: return the first agent if no manager found
        if self.agents:
            return list(self.agents.values())[0]
        
        return None
    
    def get_all_agents(self) -> list:
        """Get all agents in this system."""
        return list(self.agents.values())
    
    def run_task(self, task_description: str, context: dict = None) -> dict:
        """Run a task using this system's agents."""
        results = {
            "task_description": task_description,
            "completed": False,
            "output": None,
            "error": None,
        }
        
        try:
            self.wait_for_rate_limit()
            
            # Get the manager agent
            manager_agent = self.get_manager_agent()
            if not manager_agent:
                results["error"] = "No manager agent found for this system"
                return results
            
            # Create task prompt
            prompt = self._create_task_prompt(task_description, context)
            
            print(f"Using {manager_agent.name} for task: {task_description}")
            
            # Run the agent
            agent_output = manager_agent.run(prompt)
            results["output"] = str(agent_output)
            results["completed"] = True

        except Exception as e:
            results["error"] = str(e)
            print(f"Error running task: {e}")

        return results
    
    def _create_task_prompt(self, task_description: str, context: dict = None) -> str:
        """Create a prompt for the given task."""
        prompt = f"Task: {task_description}\n\n"
        
        if context:
            prompt += "Context:\n"
            for key, value in context.items():
                prompt += f"- {key}: {value}\n"
            prompt += "\n"
        
        return prompt


# Tool definitions for different agent types
def get_manager_tools():
    """Tools available to manager agents."""
    return [
        # TODO: Add manager-specific tools
        # - orchestrate_subagents
        # - collect_results
        # - make_decisions
        # - validate_outputs
    ]

def get_code_analysis_tools():
    """Tools available to code analysis agents."""
    return [
        # TODO: Add code analysis tools
        # - analyze_syntax
        # - analyze_semantics
        # - extract_patterns
        # - identify_vulnerabilities
    ]

def get_retrieval_tools():
    """Tools available to retrieval agents."""
    return [
        # TODO: Add retrieval tools
        # - query_rag_db
        # - search_vector_db
        # - retrieve_context
        # - validate_information
    ]

def get_v8_search_tools():
    """Tools available to V8 search agents."""
    return [
        # TODO: Add V8 search tools
        # - fuzzy_find
        # - regex_search
        # - compile_with_clang
        # - test_with_python
        # - view_call_graph
        # - web_search
    ]

def get_program_builder_tools():
    """Tools available to program builder agents."""
    return [
        # TODO: Add program builder tools
        # - query_postgres_db
        # - generate_seed_program
        # - combine_contexts
        # - validate_syntax
    ]

def get_corpus_generation_tools():
    """Tools available to corpus generation agents."""
    return [
        # TODO: Add corpus generation tools
        # - validate_syntax
        # - validate_semantics
        # - test_program
        # - evaluate_interestingness
    ]

def get_runtime_analysis_tools():
    """Tools available to runtime analysis agents."""
    return [
        # TODO: Add runtime analysis tools
        # - analyze_execution_state
        # - check_coverage
        # - evaluate_flags
        # - determine_seed_quality
    ]

def get_validation_tools():
    """Tools available to validation agents."""
    return [
        # TODO: Add validation tools
        # - validate_corpus
        # - check_db_integrity
        # - verify_results
        # - quality_assurance
    ]
