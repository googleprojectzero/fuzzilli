#!/usr/bin/env python3

# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Triage Fuzzilli V8 crash/differential artifacts for VRP work.

Reproduces each stored program with the target arguments recorded in its
Fuzzilli footer, checks determinism, optionally runs an ASan shell, and writes a
Markdown + JSON report. Injected-fault crashes are marked and excluded from
--fail-on-finding.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

FAULT_FLAG = "--maglev-fuzz-drop-heapobject-check"


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Triage Fuzzilli V8 crash/differential artifacts for VRP work."
    )
    parser.add_argument("storage", type=Path, help="Fuzzilli storage directory.")
    parser.add_argument("--d8", type=Path, required=True, help="d8 used for reproduction.")
    parser.add_argument("--asan-d8", type=Path, help="Optional ASan d8 for a second run.")
    parser.add_argument(
        "--out",
        type=Path,
        help="Triage output directory (default: <storage>/triage).",
    )
    parser.add_argument(
        "--fuzzil-tool",
        type=Path,
        help="FuzzILTool path (default: .build/debug/FuzzILTool).",
    )
    parser.add_argument(
        "--runs", type=int, default=3, help="Reproduction attempts (default: 3)."
    )
    parser.add_argument(
        "--timeout", type=int, default=30, help="Per-execution timeout in seconds."
    )
    parser.add_argument(
        "--include-duplicates",
        action="store_true",
        help="Also triage crashes/duplicates.",
    )
    parser.add_argument(
        "--fail-on-finding",
        action="store_true",
        help="Exit 2 if a deterministic non-injected crash or differential is found.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Only write the JSON report."
    )
    return parser.parse_args()


def read_text(path):
    try:
        return path.read_text(errors="replace")
    except OSError as e:
        die(f"cannot read {path}: {e}")


def find_fuzzil_tool(root, override):
    candidates = []
    if override:
        candidates.append(override)
    candidates += [
        root / ".build/debug/FuzzILTool",
        root / ".build/release/FuzzILTool",
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def read_settings(storage):
    path = storage / "settings.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(read_text(path))
    except json.JSONDecodeError as e:
        print(f"warning: cannot parse {path}: {e}", file=sys.stderr)
        return {}


def clean_comment(line):
    line = line.strip()
    line = re.sub(r"^//\s?", "", line)
    return line.strip()


def read_footer(text):
    """Extracts reproduction metadata from a stored/lifted program."""
    info = {
        "target_args": None,
        "opt_args": None,
        "ref_args": None,
        "contributors": None,
        "has_crash_info": False,
        "has_diff_info": False,
    }
    for raw in text.splitlines():
        line = clean_comment(raw)
        if line.startswith("TARGET ARGS:"):
            info["target_args"] = line.split(":", 1)[1].strip()
        elif line.startswith("REFERENCE ARGS:"):
            info["ref_args"] = line.split(":", 1)[1].strip()
        elif line.startswith("ARGS:"):
            info["opt_args"] = line.split(":", 1)[1].strip()
        elif line.startswith("CONTRIBUTORS:"):
            info["contributors"] = line.split(":", 1)[1].strip()
        elif line.startswith("CRASH INFO"):
            info["has_crash_info"] = True
        elif line.startswith("DIFFERENTIAL INFO"):
            info["has_diff_info"] = True
    return info


def split_recorded_args(recorded, d8):
    args = shlex.split(recorded)
    if args and not args[0].startswith("-"):
        # The footer contains the original executable. Use the supplied d8.
        args = args[1:]
    return args


def resolve_args(footer, settings, d8):
    if footer["target_args"]:
        return split_recorded_args(footer["target_args"], d8)
    if footer["opt_args"]:
        return split_recorded_args(footer["opt_args"], d8)
    recorded = settings.get("processArguments")
    if isinstance(recorded, list):
        return [str(a) for a in recorded]
    return None


def resolve_reference_args(footer, settings, d8, profile):
    if footer["ref_args"]:
        return split_recorded_args(footer["ref_args"], d8)
    if footer["has_diff_info"]:
        if profile in ("v8Maglev", "v8MaglevFaultInjection"):
            return resolve_args(footer, settings, d8) + ["--no-maglev"]
    return None


def lift_program(tool, fzil, outdir):
    if tool is None:
        return None
    try:
        result = subprocess.run(
            [str(tool), "--liftToJS", str(fzil)],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    output = outdir / (fzil.stem + ".js")
    output.write_text(result.stdout)
    return output


def script_for(fzil, tool, outdir):
    js = fzil.with_suffix(".js")
    if js.is_file():
        output = outdir / js.name
        shutil.copyfile(js, output)
        return output
    return lift_program(tool, fzil, outdir)


def run_once(executable, args, script, timeout, env):
    cmd = [str(executable)] + args + [str(script)]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, env=env
        )
        return {
            "command": cmd,
            "returncode": result.returncode,
            "signal": -result.returncode if result.returncode < 0 else None,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as e:
        return {
            "command": cmd,
            "returncode": None,
            "signal": None,
            "stdout": e.stdout if isinstance(e.stdout, str) else "",
            "stderr": e.stderr if isinstance(e.stderr, str) else "",
            "timed_out": True,
        }


def has_asan_error(result):
    text = result["stderr"] + result["stdout"]
    markers = (
        "AddressSanitizer",
        "runtime error:",
        "SUMMARY: AddressSanitizer",
        "MemorySanitizer",
        "UndefinedBehaviorSanitizer",
    )
    return any(marker in text for marker in markers)


def signature(result, compare_output=False):
    if result["timed_out"]:
        return "timeout"
    if result["signal"] is not None:
        return f"signal={result['signal']}"
    if compare_output:
        digest = hashlib.sha256(result["stdout"].encode()).hexdigest()[:16]
        return f"exit={result['returncode']} stdout={digest}"
    return f"exit={result['returncode']}"


def excerpt(text, limit=2500):
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[:limit] + "\n...<truncated>"


def collect_candidates(storage, include_duplicates):
    candidates = []
    for kind, directory in (
        ("crash", storage / "crashes"),
        ("differential", storage / "differentials"),
    ):
        if not directory.is_dir():
            continue
        for fzil in sorted(directory.glob("*.fzil")):
            candidates.append((kind, fzil))
    if include_duplicates:
        duplicates = storage / "crashes" / "duplicates"
        if duplicates.is_dir():
            for fzil in sorted(duplicates.glob("*.fzil")):
                candidates.append(("duplicate-crash", fzil))
    return candidates


def triage_candidate(
    kind, fzil, tool, outdir, d8, asan_d8, args, settings, runs, timeout
):
    script = script_for(fzil, tool, outdir)
    if script is None:
        return {
            "kind": kind,
            "name": fzil.stem,
            "error": "could not lift program (missing FuzzILTool/JS?)",
        }

    footer = read_footer(read_text(script))
    opt_args = resolve_args(footer, settings, d8)
    ref_args = resolve_reference_args(footer, settings, d8, "")
    injected = any(FAULT_FLAG in a for a in (opt_args or []) + (ref_args or []))
    if opt_args is None:
        return {
            "kind": kind,
            "name": fzil.stem,
            "script": str(script),
            "injected": injected,
            "error": "no reproduction args in footer/settings.json",
        }

    env = os.environ.copy()
    attempts = [
        run_once(d8, opt_args, script, timeout, env) for _ in range(max(1, runs))
    ]
    compare_output = kind != "crash"
    signatures = {
        signature(attempt, compare_output=compare_output) for attempt in attempts
    }
    opt = attempts[0]
    deterministic = len(signatures) == 1

    reference = None
    differential = False
    if ref_args is not None:
        reference = run_once(d8, ref_args, script, timeout, env)
        differential = (
            opt["returncode"] != reference["returncode"]
            or opt["signal"] != reference["signal"]
            or opt["stdout"].strip() != reference["stdout"].strip()
        )

    asan = None
    if asan_d8 is not None:
        asan_env = os.environ.copy()
        asan_env["ASAN_OPTIONS"] = "abort_on_error=1:detect_leaks=0:symbolize=1"
        asan = run_once(asan_d8, opt_args, script, timeout, asan_env)

    return {
        "kind": kind,
        "name": fzil.stem,
        "script": str(script),
        "fzil": str(fzil),
        "args": opt_args,
        "reference_args": ref_args,
        "injected": injected,
        "deterministic": deterministic,
        "signature": sorted(signatures)[0] if deterministic else sorted(signatures),
        "crashed": opt["signal"] is not None or (opt["returncode"] or 0) != 0,
        "timed_out": opt["timed_out"],
        "differential": differential,
        "reference": reference,
        "asan": asan,
        "asan_error": has_asan_error(asan) if asan else False,
        "contributors": footer["contributors"],
        "stderr": excerpt(opt["stderr"]),
        "stdout": excerpt(opt["stdout"]),
    }


def write_reports(storage, outdir, results, d8, asan_d8, args):
    stats = {
        "generated": str(d8),
        "asan": str(asan_d8) if asan_d8 else None,
        "timestamp": datetime.now().isoformat(),
        "candidates": results,
    }
    (outdir / "report.json").write_text(json.dumps(stats, indent=2) + "\n")
    if args.json:
        return

    lines = [
        "# Fuzzilli V8 VRP triage",
        "",
        f"- storage: `{storage}`",
        f"- generated: {stats['timestamp']}",
        f"- d8: `{d8}`",
        f"- ASan d8: `{asan_d8}`" if asan_d8 else "- ASan d8: not provided",
        "",
        "## Candidates",
        "",
        "| # | kind | deterministic | signature | injected fault | ASan | contributors |",
        "|---|------|---------------|-----------|----------------|------|--------------|",
    ]
    for i, result in enumerate(results, 1):
        if "error" in result:
            lines.append(f"| {i} | {result['kind']} | n/a | error | n/a | n/a | n/a |")
            continue
        if result.get("asan_error"):
            asan = "error"
        elif result.get("asan"):
            asan = "run"
        else:
            asan = "n/a"
        lines.append(
            "| {i} | {kind} | {det} | {sig} | {inj} | {asan} | {contrib} |".format(
                i=i,
                kind=result["kind"],
                det="yes" if result["deterministic"] else "no",
                sig=result["signature"],
                inj="yes" if result["injected"] else "no",
                asan=asan,
                contrib=(result.get("contributors") or "")[:80],
            )
        )

    lines += ["", "## Details", ""]
    for i, result in enumerate(results, 1):
        lines.append(f"### {i}. {result.get('name')} ({result['kind']})")
        lines.append("")
        if "error" in result:
            lines += [result["error"], ""]
            continue
        lines.append(f"- script: `{result['script']}`")
        lines.append(f"- injected fault: **{'yes' if result['injected'] else 'no'}**")
        lines.append(f"- deterministic: {'yes' if result['deterministic'] else 'no'}")
        lines.append(f"- signature: `{result['signature']}`")
        lines.append(f"- differential: {'yes' if result['differential'] else 'no'}")
        if result.get("asan_error"):
            lines.append("- ASan: **error detected**")
        lines.append("")
        command = [str(d8)] + result["args"] + [result["script"]]
        lines.append("```")
        lines.append(" ".join(shlex.quote(p) for p in command))
        lines.append("```")
        if result.get("stderr"):
            lines += ["", "stderr:", "```", result["stderr"], "```"]
        if result.get("asan") and result["asan"]["stderr"]:
            lines += ["", "ASan stderr:", "```", excerpt(result["asan"]["stderr"]), "```"]
        lines.append("")

    lines += [
        "## Next steps",
        "",
        "1. Reproduce on a clean, non-fault build and without `--maglev-fuzz-drop-heapobject-check`.",
        "2. Confirm determinism and minimize the JS if needed.",
        "3. Verify memory corruption with ASan/MSan and assess sandbox impact.",
        "4. Report through the Chrome VRP/Chromium security tracker if unfixed.",
        "",
        "Injected-fault candidates are harness canaries, not VRP findings.",
        "",
    ]
    (outdir / "report.md").write_text("\n".join(lines))


def main():
    args = parse_args()
    storage = args.storage.expanduser().resolve()
    d8 = args.d8.expanduser().resolve()
    if not storage.is_dir():
        die(f"storage directory does not exist: {storage}")
    if not d8.is_file():
        die(f"d8 does not exist: {d8}")
    asan_d8 = args.asan_d8.expanduser().resolve() if args.asan_d8 else None
    if asan_d8 is not None and not asan_d8.is_file():
        die(f"ASan d8 does not exist: {asan_d8}")

    outdir = (args.out or (storage / "triage")).expanduser().resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    root = Path(__file__).resolve().parent.parent
    tool = find_fuzzil_tool(root, args.fuzzil_tool)
    settings = read_settings(storage)
    candidates = collect_candidates(storage, args.include_duplicates)

    results = []
    for kind, fzil in candidates:
        results.append(
            triage_candidate(
                kind,
                fzil,
                tool,
                outdir,
                d8,
                asan_d8,
                args,
                settings,
                args.runs,
                args.timeout,
            )
        )

    write_reports(storage, outdir, results, d8, asan_d8, args)

    print(f"Triage report: {outdir / 'report.md'}")
    print(f"JSON report:   {outdir / 'report.json'}")
    if not results:
        print("No crash/differential artifacts found.")
        return 0

    findings = [
        r
        for r in results
        if "error" not in r
        and not r["injected"]
        and r["deterministic"]
        and (r["crashed"] or r["differential"] or r["timed_out"])
    ]
    injected = [r for r in results if r.get("injected")]
    print(f"Candidates: {len(results)}, non-injected findings: {len(findings)}")
    if injected:
        print(f"Injected-fault candidates (not VRP findings): {len(injected)}")

    if args.fail_on_finding and findings:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())



