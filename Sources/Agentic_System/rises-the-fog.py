#!/usr/bin/env python3
import argparse
import functools
import json
import os
import sys
from pathlib import Path

from agents.FoG import Father
from agents.EBG import EBG

# we need logging. Steal from squidagent

from smolagents import LiteLLMModel


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