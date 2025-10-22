#!/usr/bin/env python3

import threading
import time
from abc import ABC, abstractmethod
from pathlib import Path

from smolagents import LiteLLMModel, ToolCallingAgent


class Agent(ABC): #a
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
