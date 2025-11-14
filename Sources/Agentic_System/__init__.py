import importlib.util
import sys
from pathlib import Path

_module_dir = Path(__file__).parent
_module_path = _module_dir / "rises-the-fog.py"

if str(_module_dir) not in sys.path:
    sys.path.insert(0, str(_module_dir))

_spec = importlib.util.spec_from_file_location("rises_the_fog", _module_path)
rises_the_fog = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rises_the_fog)

