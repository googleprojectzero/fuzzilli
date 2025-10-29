#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Dict

def load_keys_from_config(config_path: Path = None) -> Dict[str, str]:
    if config_path is None:
        config_path = Path(__file__).parent / "keys.cfg"
    
    keys = {}
    
    if not config_path.exists():
        return keys
    
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                keys[key] = value
    
    return keys

def get_openai_api_key() -> str:
    keys = load_keys_from_config()
    return keys.get('OPENAI_API_KEY', '')
    
def get_anthropic_api_key() -> str:
    keys = load_keys_from_config()
    return keys.get('ANTHROPIC_API_KEY', '')

