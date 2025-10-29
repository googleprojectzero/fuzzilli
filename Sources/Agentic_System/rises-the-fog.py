#!/usr/bin/env python3
import argparse
import functools
import json
import os
import sys
from pathlib import Path
import logging 

from agents.FoG import Father
from agents.EBG import EBG
from smolagents import LiteLLMModel
from config_loader import get_openai_api_key, get_anthropic_api_key

logging.basicConfig(filename=os.path.join(os.getcwd(), 'fog_logs', 'rises_the_fog.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

BASE_MODEL_ID = "gpt-5-mini"


class FatherOfGod:
    def __init__(self, api_key: str = None, anthropic_api_key: str = None):
        if api_key:
            self.model = LiteLLMModel(model_id=BASE_MODEL_ID, api_key=api_key)
        else:
            self.model = LiteLLMModel(model_id=BASE_MODEL_ID)

        self.api_key = api_key
        self.anthropic_api_key = anthropic_api_key

        # Create specialized subsystem classes
        self.systems = {
            'fog': Father(self.model, self.api_key, self.anthropic_api_key),
            'ebg': EBG(self.model, self.api_key, self.anthropic_api_key)
        }
        
        self.environment = None  # path/to/.venv

    def get_system_list(self) -> list:
        """Get list of available system names."""
        return list(self.systems.keys())
    
    def get_system(self, system_name: str):
        """Get a system by name (case-insensitive)."""
        normalized = (system_name or "").strip().lower()
        return self.systems.get(normalized)

    def get_prompt(self, prompt_name):
        prompt_path = Path(__file__).parent.parent / "squidagent" / "prompts" / prompt_name
        with open(prompt_path, 'r') as f:
            template_content = f.read()
        return template_content

    def run_task(self, system_name: str, task_description: str, context: dict = None) -> dict:
        """
        Run a task using the specified system.
        
        Args:
            system_name (str): Name of the system to use ('fog' or 'ebg')
            task_description (str): Description of the task to run
            context (dict): Optional context for the task
            
        Returns:
            dict: Results of the task execution
        """
        system = self.get_system(system_name)
        if not system:
            return {
                "error": f"System '{system_name}' not found. Available systems: {list(self.systems.keys())}",
                "completed": False
            }
        
        logger.info(f"Running task '{task_description}' on system '{system_name}'")
        return system.run_task(task_description, context)


def read_api_keys(key_file: str) -> dict:
    """Read API keys from a configuration file."""
    api_keys = {}
    try:
        with open(key_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    api_keys[key.strip()] = value.strip()
    except Exception as e:
        logger.error(f"Error reading API keys from {key_file}: {e}")
    return api_keys


def main():
    parser = argparse.ArgumentParser(description="Father of God - V8 Fuzzing Agentic System")
    parser.add_argument("--system", required=True, choices=['fog', 'ebg'], 
                       help="Which system to run: 'fog' (Father of God) or 'ebg' (Ethiopian BG)")
    parser.add_argument("--task", required=True, 
                       help="Task description for the agent")
    parser.add_argument("--context", type=str, default=None,
                       help="JSON context dictionary as a string (optional)")
    parser.add_argument("--context-file", type=str, default=None,
                       help="Path to JSON file containing context (optional)")
    parser.add_argument("--api-keys", default="keys.cfg", help="Path to API keys configuration file")
    
    args = parser.parse_args()
    
    # Read API keys
    api_keys = read_api_keys(args.api_keys)
    openai_key = api_keys.get("OPENAI_API_KEY")
    anthropic_key = api_keys.get("ANTHROPIC_API_KEY")
    
    if not openai_key:
        logger.error("No OpenAI API key found")
        print("Error: No OpenAI API key found. Please set OPENAI_API_KEY in keys.cfg")
        return 1
    
    # Initialize the FatherOfGod system
    logger.info("Initializing Father of God system...")
    system_manager = FatherOfGod(api_key=openai_key, anthropic_api_key=anthropic_key)
    
    # Parse context if provided
    context = None
    if args.context_file:
        try:
            with open(args.context_file, 'r') as f:
                context = json.load(f)
                logger.info(f"Loaded context from file: {args.context_file}")
        except Exception as e:
            logger.error(f"Failed to load context file: {e}")
            print(f"Error: Failed to load context file: {e}")
            return 1
    elif args.context:
        try:
            context = json.loads(args.context)
            logger.info("Loaded context from command line argument")
        except Exception as e:
            logger.error(f"Failed to parse context JSON: {e}")
            print(f"Error: Failed to parse context JSON: {e}")
            return 1
    
    # Run the task
    logger.info(f"Starting task execution on system '{args.system}'")
    print("I must go in; the fog is rising")
    print(f"System: {args.system.upper()}")
    print(f"Task: {args.task}")
    if context:
        print(f"Context: {json.dumps(context, indent=2)}")
    print("-" * 80)
    
    try:
        results = system_manager.run_task(
            system_name=args.system,
            task_description=args.task,
            context=context
        )
        
        # Print results
        print("\n" + "=" * 80)
        print("Task Results:")
        print("=" * 80)
        print(f"Task: {results.get('task_description', args.task)}")
        print(f"Completed: {results.get('completed', False)}")
        
        if results.get('output'):
            print(f"\nOutput:\n{results['output']}")
        
        if results.get('error'):
            print(f"\nError: {results['error']}")
            return 1
        
        if results.get('completed'):
            print("\n✓ Task completed successfully!")
            return 0
        else:
            print("\n✗ Task did not complete successfully")
            return 1
            
    except Exception as e:
        logger.error(f"Error during task execution: {e}", exc_info=True)
        print(f"\nError during task execution: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
