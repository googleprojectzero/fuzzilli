#!/usr/bin/env python3

import functools
import threading
import time
import os
import logging
from abc import ABC, abstractmethod
from pathlib import Path

from smolagents import LiteLLMModel, ToolCallingAgent

logger = logging.getLogger("base_agent")
if not logger.handlers:
    logger.addHandler(logging.NullHandler())
logger.propagate = False
logger.disabled = True

def enable_base_agent_logging():
    """Enable logging to Agentic_System/agents/fog_logs/base_agent.log if FOG_DEBUG=1."""
    try:
        if os.getenv("FOG_DEBUG") == "1":
            logs_dir = Path(__file__).parent / "fog_logs"
            logs_dir.mkdir(parents=True, exist_ok=True)
            log_path = logs_dir / "base_agent.log"
            logging.basicConfig(
                filename=str(log_path),
                level=logging.INFO,
                format='%(asctime)s - %(levelname)s - %(message)s'
            )
            logger.disabled = False
    except Exception:
        # Fail closed: keep logging disabled
        logger.disabled = True

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
                    logger.info(f"Rate limiting: waiting {sleep_time:.2f} seconds...")
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
            
            logger.info(f"Using {manager_agent.name} for task: {task_description}")
            logger.info (f"Task prompt: {prompt}")
            
            # Helper functions for collecting and wrapping agents
            def _collect_agents(root_agent):
                # Collect all agents from the solver instance
                all_agents = []
                for attr_name in dir(self):
                    if attr_name.endswith('_agent') and not attr_name.startswith('_'):
                        try:
                            agent = getattr(self, attr_name)
                            if hasattr(agent, 'run') and hasattr(agent, 'name'):
                                all_agents.append(agent)
                        except Exception:
                            pass
                
                # Also collect via managed_agents relationships
                to_process = [root_agent]
                collected = set()
                while to_process:
                    current = to_process.pop()
                    if current not in collected:
                        collected.add(current)
                        try:
                            managed = getattr(current, "managed_agents", []) or []
                            to_process.extend(managed)
                        except Exception:
                            pass
                
                # Combine both approaches and remove duplicates
                final_agents = list(collected)
                for agent in all_agents:
                    if agent not in final_agents:
                        final_agents.append(agent)
                
                return final_agents

            def _wrap_litellm_completion(agents):
                """Wrap LiteLLM completion to intercept tool calls and results."""
                import litellm
                original_completion = litellm.completion
                
                pending_tool_calls = {}
                
                def wrapped_completion(*args, **kwargs):
                    result = original_completion(*args, **kwargs)
                    
                    try:
                        if hasattr(result, 'choices') and result.choices:
                            choice = result.choices[0]
                            if hasattr(choice, 'message') and choice.message:
                                message = choice.message
                                
                                agent_name = "unknown_agent"
                                model_name = kwargs.get('model', 'unknown')
                                
                                for agent in agents:
                                    try:
                                        agent_model = getattr(agent, 'model', None)
                                        if agent_model and hasattr(agent_model, 'model_id'):
                                            if agent_model.model_id == model_name:
                                                agent_name = getattr(agent, 'name', 'unknown_agent')
                                                break
                                    except Exception:
                                        pass
                                
                                if hasattr(message, 'tool_calls') and message.tool_calls:
                                    for tool_call in message.tool_calls:
                                        try:
                                            tool_name = getattr(tool_call.function, 'name', 'unknown_tool')
                                            tool_args = getattr(tool_call.function, 'arguments', '{}')
                                            
                                            if isinstance(tool_args, str):
                                                import json
                                                try:
                                                    tool_args = json.loads(tool_args)
                                                except:
                                                    tool_args = {}
                                            
                                            logger.info(f"Tool call: {agent_name} -> {tool_name} with args: {tool_args}")
                                            logger.debug(f"Logged tool call via LiteLLM: {tool_name} by {agent_name}")
                                            
                                            call_id = getattr(tool_call, 'id', f"{agent_name}_{tool_name}_{len(pending_tool_calls)}")
                                            pending_tool_calls[call_id] = {
                                                'agent': agent_name,
                                                'tool_name': tool_name,
                                                'args': tool_args
                                            }
                                            logger.debug(f"Stored pending tool call {call_id} for {agent_name} calling {tool_name}")
                                        except Exception as e:
                                            logger.error(f"Failed to log tool call via LiteLLM: {e}")
                                
                                # Handle tool results (content from tool responses)
                                elif hasattr(message, 'content') and message.content:
                                    # Check if this looks like a tool result
                                    content = message.content
                                    if isinstance(content, str) and content.strip():
                                        # Try to find matching tool call - be more flexible with matching
                                        matched_tool = None
                                        matched_call_id = None
                                        
                                        # First try exact agent match
                                        for call_id, call_info in pending_tool_calls.items():
                                            if call_info['agent'] == agent_name:
                                                matched_tool = call_info
                                                matched_call_id = call_id
                                                logger.debug(f"Exact agent match found for {agent_name} with tool {call_info['tool_name']}")
                                                break
                                        
                                        # Fallbacks to reduce dropped tool results while avoiding misattribution:
                                        # 1) If there is only one pending tool call overall, attribute to it
                                        if not matched_tool and len(pending_tool_calls) == 1:
                                            matched_call_id, matched_tool = next(iter(pending_tool_calls.items()))
                                            logger.debug(f"Single pending tool call fallback -> {matched_tool['tool_name']} by {matched_tool['agent']}")
                                        # 2) If multiple pending but only one from this agent, use that (prefer the most recent)
                                        if not matched_tool and pending_tool_calls:
                                            agent_calls = [
                                                (cid, info) for cid, info in pending_tool_calls.items()
                                                if info.get('agent') == agent_name
                                            ]
                                            if len(agent_calls) == 1:
                                                matched_call_id, matched_tool = agent_calls[0]
                                                logger.debug(f"Single pending tool for agent fallback -> {matched_tool['tool_name']} by {matched_tool['agent']}")
                                            elif len(agent_calls) > 1:
                                                # Choose the most recently inserted pending call for this agent
                                                matched_call_id, matched_tool = agent_calls[-1]
                                                logger.debug(f"Most recent pending tool for agent fallback -> {matched_tool['tool_name']} by {matched_tool['agent']}")
                                        
                                        if matched_tool:
                                            try:
                                                logger.info(f"Tool result: {matched_tool['agent']} <- {matched_tool['tool_name']}: {content[:200]}")
                                                logger.debug(f"Logged tool result via LiteLLM: {matched_tool['tool_name']} by {matched_tool['agent']}")
                                                
                                                del pending_tool_calls[matched_call_id]
                                            except Exception as e:
                                                logger.error(f"Failed to log tool result via LiteLLM: {e}")
                                        else:
                                            logger.debug(f"No matching tool call found for {agent_name}, treating as assistant message")
                                            try:
                                                logger.info(f"Assistant message: {agent_name}: {content[:200]}")
                                            except Exception as e:
                                                logger.error(f"Failed to log assistant message: {e}")
                    except Exception as e:
                        logger.error(f"Failed to process LiteLLM result: {e}")
                    
                    return result
                
                # Replace the global completion function
                litellm.completion = wrapped_completion
                return original_completion
            
            def _restore_litellm_completion(original_completion):
                """Restore original LiteLLM completion."""
                import litellm
                litellm.completion = original_completion

            def _wrap_agent_run_method(agents):
                """Wrap the run method of agents to capture their conversations."""
                original_runs_map = {}
                for a in agents:
                    try:
                        original_run = getattr(a, "run")
                        original_runs_map[a] = original_run
                        
                        def make_run_wrapper(agent_obj, orig_run):
                            @functools.wraps(orig_run)
                            def _wrapped_run(prompt, *args, **kwargs):
                                agent_name = getattr(agent_obj, "name", "agent")
                                try:
                                    logger.info(f"Agent {agent_name} executing with prompt: {str(prompt)[:200]}")
                                except Exception:
                                    pass
                                
                                result = orig_run(prompt, *args, **kwargs)
                                
                                try:
                                    logger.info(f"Agent {agent_name} completed with result: {str(result)[:200]}")
                                except Exception:
                                    pass
                                
                                return result
                            return _wrapped_run
                        
                        setattr(a, "run", make_run_wrapper(a, original_run))
                    except Exception:
                        pass
                return original_runs_map

            def _restore_agent_runs(original_runs_map):
                """Restore original agent run methods."""
                for agent_obj, orig_run in original_runs_map.items():
                    try:
                        setattr(agent_obj, "run", orig_run)
                    except Exception:
                        pass

            agents_to_wrap = _collect_agents(manager_agent)

            # Run agent with logging
            agent_output = None
            try:
                litellm_original = _wrap_litellm_completion(agents_to_wrap)
                run_originals = _wrap_agent_run_method(agents_to_wrap)
                
                agent_output = manager_agent.run(prompt)
                agent_output = str(agent_output)
                
                logger.info(f"Task '{task_description}' completed successfully by {manager_agent.name}")
            finally:
                _restore_litellm_completion(litellm_original)
                _restore_agent_runs(run_originals)
            
            results["output"] = agent_output
            results["completed"] = (agent_output is not None)

        except Exception as e:
            results["error"] = str(e)
            logger.info(f"Error running task: {e}")

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
