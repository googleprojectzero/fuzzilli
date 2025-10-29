#!/usr/bin/env python3
import argparse
import functools
import json
import os
import sys
from pathlib import Path
import logging 
import config_loader
from agents.FoG import Father
from agents.EBG import EBG

# we need logging. Steal from squidagent

from smolagents import LiteLLMModel
from config_loader import get_openai_api_key, get_anthropic_api_key

logging.basicConfig(filename=os.path.join(os.getcwd(), 'fog_logs', 'rises_the_fog.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

BASE_MODEL_ID = "gpt-5-mini"


class FatherOfGod:
    def __init__(self):
        self.openai_api_key = get_openai_api_key()
        self.anthropic_api_key = get_anthropic_api_key()
        self.model = LiteLLMModel(model_id=BASE_MODEL_ID, api_key=self.openai_api_key)
        self.system = Father(self.model, api_key=self.openai_api_key, anthropic_api_key=self.anthropic_api_key)
        self.ebg = EBG(self.model, api_key=self.openai_api_key, anthropic_api_key=self.anthropic_api_key)




def main():
    print("I must go in; the fog is rising")
    a = FatherOfGod()
    a.system.run_task(
        task_description="Initialize corpus generation for V8 fuzzing",
        context={
            "CodeAnalyzer": "Analyze V8 source code for patterns. vulnerabilities. specifc components, etc...",
            "ProgramBuilder": "Build JavaScript programs using corpus and context"
        }
    )


if __name__ == "__main__":
    main()