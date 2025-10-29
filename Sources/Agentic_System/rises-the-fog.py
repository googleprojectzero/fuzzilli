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

# we need logging. Steal from squidagent

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
            'FoG': Father(self.model, self.api_key, self.anthropic_api_key),
            'EBG': EBG(self.model, self.api_key, self.anthropic_api_key)
        }





def main():
    print("I must go in; the fog is rising")
    parser = argparse.ArgumentParser(description="Father of God")

if __name__ == "__main__":
    main()