#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Dict

def load_keys_from_config(config_path: Path = None) -> Dict[str, str]:
    keys = {}
    
    if config_path is None:
        possible_paths = [
            Path(__file__).parent / "keys.cfg",
            Path(__file__).parent.parent / "keys.cfg",
            Path.cwd() / "keys.cfg",
            Path.cwd() / "Sources" / "Agentic_System" / "keys.cfg",
        ]
        
        for path in possible_paths:
            if path.exists():
                config_path = path
                break
        else:
            return keys
    
    if not config_path or not config_path.exists():
        return keys
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    if key and value:
                        keys[key] = value
    except Exception as e:
        import sys
        print(f"Error loading keys from {config_path}: {e}", file=sys.stderr)
        return keys
    
    return keys

def get_openai_api_key() -> str:
    keys = load_keys_from_config()
    return keys.get('OPENAI_API_KEY', '')
    
def get_anthropic_api_key() -> str:
    keys = load_keys_from_config()
    return keys.get('ANTHROPIC_API_KEY', '')
    
def get_deepseek_api_key() -> str:
    keys = load_keys_from_config()
    key = keys.get('DEEPSEEK_API_KEY', '')
    if not key:
        key = os.getenv('DEEPSEEK_API_KEY', '')
    return key

