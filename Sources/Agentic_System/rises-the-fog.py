#!/usr/bin/env python3
import argparse
import functools
import json
import os
import sys
import subprocess
from pathlib import Path
import logging 
import config_loader as config_loader 
from agents.FoG import Father
from agents.EBG import EBG
from smolagents import LiteLLMModel
from config_loader import get_openai_api_key, get_anthropic_api_key
logger = logging.getLogger("rises_the_fog")
if not logger.handlers:
    logger.addHandler(logging.NullHandler())
logger.propagate = False
logger.disabled = True

BASE_MODEL_ID = "gpt-5-mini"

import site


class FatherOfGod:
    def __init__(self):
        logger.info("Initializing FatherOfGod")
        self.openai_api_key = get_openai_api_key()
        self.anthropic_api_key = get_anthropic_api_key()
        self.model = LiteLLMModel(model_id=BASE_MODEL_ID, api_key=self.openai_api_key)
        self.system = Father(self.model, api_key=self.openai_api_key, anthropic_api_key=self.anthropic_api_key)
        self.ebg = EBG(self.model, api_key=self.openai_api_key, anthropic_api_key=self.anthropic_api_key)
        

def main():

    site.addsitedir(Path(__file__).parent.parent)
    #smolagent-fork

    
    parser = argparse.ArgumentParser(description="Rise the FoG agentic system")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging to fog logs")
    args = parser.parse_args()

    if args.debug:
        log_dir = Path(__file__).parent / 'agents' / 'fog_logs'
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = str(log_dir / 'rises_the_fog.log')

        # Configure logger to write messages as-is (no prefixes) for 1:1 capture
        logger.handlers.clear()
        file_handler = logging.FileHandler(log_path, mode='a', encoding='utf-8')
        file_handler.setFormatter(logging.Formatter('%(message)s'))
        logger.addHandler(file_handler)
        logger.setLevel(logging.INFO)
        logger.disabled = False

        
        class _StreamToLogger:
            def __init__(self, log_fn):
                self.log_fn = log_fn
                self._buffer = ''
            def write(self, message):
                if not isinstance(message, str):
                    message = message.decode('utf-8', errors='ignore')
                self._buffer += message
                while '\n' in self._buffer:
                    line, self._buffer = self._buffer.split('\n', 1)
                    self.log_fn(line)
            def flush(self):
                if self._buffer:
                    self.log_fn(self._buffer)
                    self._buffer = ''
            def isatty(self):
                return False

        sys.stdout = _StreamToLogger(logger.info)
        sys.stderr = _StreamToLogger(logger.error)

        # Signal BaseAgent to enable its own logging lazily and ensure directory exists
        os.environ["FOG_DEBUG"] = "1"

    logger.info("I must go in; the fog is rising")
    a = FatherOfGod()
    if (not os.path.exists("regressions.json")):
        try:
            subprocess.run(["xz", "-d", "regressions.json.xz"], check=True)
            #xz -d regressions.json.xz
        except subprocess.CalledProcessError as e:
            logger.error(f"Error decompressing regressions.json.xz: {e}")
            exit(1)
        else:
            logger.info("Regressions.json decompressed successfully")
    a.system.start_system()




if __name__ == "__main__":
    sys.exit(main())
