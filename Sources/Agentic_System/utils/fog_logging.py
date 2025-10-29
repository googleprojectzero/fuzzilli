#!/usr/bin/env python3
import json
import os
import time
import re
from typing import Any, Dict, List, Optional


def _slugify(title: str) -> str:
    s = title.strip().lower()
    s = re.sub(r"[^a-z0-9\-_. ]+", "", s)
    s = s.replace(" ", "-")
    s = re.sub(r"-+", "-", s)
    return s


class FogAgentRunLogger:
    """
    Lightweight JSON logger for smolagents runs.

    Writes a single JSON file per challenge to fog_logs/<run_title>.json
    with run-level metadata and a transcript of events (thoughts, tool calls, outputs).
    """

    def __init__(
        self,
        run_title: str,
        base_dir: str = "fog_logs",
    ) -> None:
        self.run_title = run_title
        self.base_dir = base_dir
        self.events: List[Dict[str, Any]] = []
        self.start_time: Optional[float] = None
        self.end_time: Optional[float] = None
        self.success: Optional[bool] = None
        self.exit_reason: Optional[str] = None
        self.error: Optional[str] = None

        os.makedirs(self.base_dir, exist_ok=True)

    def start(self) -> None:
        self.start_time = time.time()

    def log_event(
        self,
        *,
        agent: Optional[str] = None,
        role: Optional[str] = None,
        content: Optional[str] = None,
        tool_call: Optional[Dict[str, Any]] = None,
        tool_result: Optional[Dict[str, Any]] = None,
        meta: Optional[Dict[str, Any]] = None,
        index: Optional[int] = None,
    ) -> None:
        event: Dict[str, Any] = {}
        if agent is not None:
            event["agent"] = agent
        if role is not None:
            event["role"] = role
        if index is not None:
            event["index"] = index
        if content is not None:
            event["content"] = content
        if tool_call is not None:
            event["tool_call"] = self._maybe_truncate(tool_call)
        if tool_result is not None:
            event["tool_result"] = self._maybe_truncate(tool_result)
        if meta is not None:
            event["meta"] = meta
        self.events.append(event)

    def set_outcome(
        self,
        *,
        success: Optional[bool] = None,
        exit_reason: Optional[str] = None,
        error: Optional[str] = None,
    ) -> None:
        if success is not None:
            self.success = success
        if exit_reason is not None:
            self.exit_reason = exit_reason
        if error is not None:
            self.error = error

    def finish(self) -> None:
        self.end_time = time.time()
        self._write()

    def _maybe_truncate(self, obj: Any, max_chars: int = 50000) -> Any:
        try:
            text = json.dumps(obj)
            if len(text) <= max_chars:
                return obj
            truncated = text[: max_chars - 3] + "..."
            try:
                return json.loads(truncated)
            except Exception:
                return {"truncated_json": truncated}
        except Exception:
            return obj

    def _write(self) -> None:
        data: Dict[str, Any] = {
            "start_time": self.start_time,
            "end_time": self.end_time,
            "time_taken": (self.end_time - self.start_time) if (self.start_time and self.end_time) else None,
            "success": self.success,
            "exit_reason": self.exit_reason,
            "error": self.error,
            "transcript": self.events,
        }

        filename = f"{_slugify(self.run_title)}.json"
        path = os.path.join(self.base_dir, filename)
        tmp_path = path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp_path, path)


class run_log:
    """
    Context manager to simplify usage:

    with run_log(run_title) as logger:
        logger.log_event(agent="manager_agent", role="system", content="...")
        ...
        logger.set_outcome(success=True, exit_reason="completed")
    """

    def __init__(
        self,
        run_title: str,
        base_dir: str = "fog_logs",
    ) -> None:
        self._logger = FogAgentRunLogger(run_title, base_dir=base_dir)

    def __enter__(self) -> FogAgentRunLogger:
        self._logger.start()
        return self._logger

    def __exit__(self, exc_type, exc, tb) -> None:
        if exc is not None:
            self._logger.set_outcome(success=False, error=str(exc), exit_reason="exception")
        self._logger.finish()

