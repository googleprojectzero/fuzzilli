#!/bin/bash
#
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

# Runs long V8 VRP-oriented fuzzing campaigns:
#   - v8: crash/assertion hunting
#   - v8Maglev: Maglev vs. --no-maglev differential hunting
#   - optional ASan crash campaign
#
# Fault injection (v8MaglevFaultInjection / --maglev-fuzz-drop-heapobject-check)
# is deliberately NOT part of the default VRP campaign; its crashes are injected.
#
# Usage:
#   Tools/v8-vrp-campaign.sh --d8 /path/to/fuzzbuild/d8 [options]
#
# Run with --help for the full option list.

set -euo pipefail

FUZZILLI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUZZILLI_CLI="$FUZZILLI_ROOT/.build/release/FuzzilliCli"
D8=""
ASAN_D8=""
OUT=""
JOBS="8"
DURATION="2h"
PROFILES="v8,v8Maglev"
RESUME=0
CANARY=0

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: Tools/v8-vrp-campaign.sh --d8 PATH [options]

Required:
  --d8 PATH             Path to a non-fault V8 fuzzbuild d8.

Options:
  --asan-d8 PATH        Optional ASan d8. Adds an ASan crash campaign.
  --out DIR             Output directory (default: /tmp/v8-vrp-<timestamp>).
  --jobs N              Fuzzilli jobs (default: 8).
  --duration D          Per-campaign runtime, e.g. 30m or 2h (default: 2h).
  --profiles LIST       Comma-separated profiles (default: v8,v8Maglev).
  --fuzzilli PATH       FuzzilliCli binary (default: .build/release/FuzzilliCli).
  --resume              Resume existing storage directories.
  --canary              Also run the injected-fault profile as a harness canary.
                        Crashes from it are NOT VRP candidates.
  --help                Show this help.

Outputs:
  DIR/metadata.txt      Build/revision/flag metadata.
  DIR/SUMMARY.txt       Per-campaign crash/differential counts.
  DIR/logs/*.log        Fuzzilli logs.
  DIR/storage/<name>/   Crashes, differentials, corpus, stats.

Then triage with:
  Tools/v8-vrp-triage.py DIR/storage/<name> --d8 PATH --out DIR/triage-<name>
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
    --d8)
        D8="$2"
        shift 2
        ;;
    --asan-d8)
        ASAN_D8="$2"
        shift 2
        ;;
    --out)
        OUT="$2"
        shift 2
        ;;
    --jobs)
        JOBS="$2"
        shift 2
        ;;
    --duration)
        DURATION="$2"
        shift 2
        ;;
    --profiles)
        PROFILES="$2"
        shift 2
        ;;
    --fuzzilli)
        FUZZILLI_CLI="$2"
        shift 2
        ;;
    --resume)
        RESUME=1
        shift
        ;;
    --canary)
        CANARY=1
        shift
        ;;
    --help | -h)
        usage
        exit 0
        ;;
    *)
        die "unknown argument: $1 (use --help)"
        ;;
    esac
done

[ -n "$D8" ] || die "--d8 is required"
[ -x "$D8" ] || die "d8 is not executable: $D8"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
[[ "$DURATION" =~ ^[1-9][0-9]*[smh]$ ]] || die "--duration must look like 30s, 15m, or 2h"

D8="$(realpath "$D8")"
[ -z "$OUT" ] && OUT="/tmp/v8-vrp-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT/logs" "$OUT/storage"

# Locate the V8 checkout (the d8 lives in <v8>/out/<config>/d8).
V8_ROOT="$(git -C "$(dirname "$D8")" rev-parse --show-toplevel 2>/dev/null || true)"
V8_REV="unknown"
[ -n "$V8_ROOT" ] && V8_REV="$(git -C "$V8_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"

if [ ! -x "$FUZZILLI_CLI" ]; then
    echo "building FuzzilliCli..."
    (cd "$FUZZILLI_ROOT" && swift build -c release --product FuzzilliCli)
fi
[ -x "$FUZZILLI_CLI" ] || die "FuzzilliCli not found: $FUZZILLI_CLI"

{
    echo "date=$(date -Is)"
    echo "v8_root=$V8_ROOT"
    echo "v8_revision=$V8_REV"
    echo "d8=$D8"
    echo "d8_sha256=$(sha256sum "$D8" | awk '{print $1}')"
    "$D8" --version 2>&1 | sed 's/^/d8_version=/'
    if [ -n "$ASAN_D8" ]; then
        echo "asan_d8=$ASAN_D8"
        echo "asan_d8_sha256=$(sha256sum "$ASAN_D8" | awk '{print $1}')"
        "$ASAN_D8" --version 2>&1 | sed 's/^/asan_d8_version=/'
    fi
    echo "fuzzilli=$FUZZILLI_CLI"
    echo "profiles=$PROFILES"
    echo "jobs=$JOBS"
    echo "duration=$DURATION"
    echo "note=fault-injection flag must be absent for VRP candidates"
} >"$OUT/metadata.txt"

# Run one campaign. Arguments: name profile d8 [extra env assignments...]
run_campaign() {
    local name="$1"
    local profile="$2"
    local shell="$3"
    shift 3
    local storage="$OUT/storage/$name"
    local log="$OUT/logs/$name.log"
    local tag="v8-rev:$V8_REV"

    if [ -d "$storage" ] && [ -n "$(ls -A "$storage" 2>/dev/null)" ] && [ "$RESUME" -ne 1 ]; then
        die "storage exists and is not empty: $storage (pass --resume or choose another --out)"
    fi

    local cmd=(
        "$FUZZILLI_CLI"
        "--profile=$profile"
        "--jobs=$JOBS"
        "--maxRuntime=$DURATION"
        "--logLevel=info"
        "--diagnostics"
        "--tag=$tag"
        "--storagePath=$storage"
    )
    # Program templates (including the Maglev one) require the HybridEngine.
    if [ "$profile" = "v8Maglev" ] || [ "$profile" = "v8MaglevFaultInjection" ]; then
        cmd+=("--engine=hybrid")
    fi
    [ "$RESUME" -eq 1 ] && cmd+=("--resume")
    cmd+=("$shell")

    echo "=== $name ($profile) ==="
    echo "storage: $storage"
    echo "command: ${cmd[*]}"
    echo "log: $log"
    set +e
    env "$@" "${cmd[@]}" 2>&1 | tee "$log"
    local rc=${PIPESTATUS[0]}
    set -e
    echo "$name exit=$rc" >>"$STATUS_FILE"
    return "$rc"
}

STATUS_FILE="$OUT/status.txt"
: >"$STATUS_FILE"

IFS=',' read -r -a PROFILE_LIST <<<"$PROFILES"
for profile in "${PROFILE_LIST[@]}"; do
    [ -n "$profile" ] || continue
    run_campaign "$profile" "$profile" "$D8" || true
done

if [ -n "$ASAN_D8" ]; then
    [ -x "$ASAN_D8" ] || die "ASan d8 is not executable: $ASAN_D8"
    ASAN_D8="$(realpath "$ASAN_D8")"
    run_campaign "asan" "v8" "$ASAN_D8" \
        ASAN_OPTIONS="abort_on_error=1:detect_leaks=0:symbolize=1" || true
fi

if [ "$CANARY" -eq 1 ]; then
    run_campaign "fault-canary" "v8MaglevFaultInjection" "$D8" || true
fi

count() {
    local dir="$1"
    [ -d "$dir" ] || {
        echo 0
        return
    }
    find "$dir" -maxdepth 1 -name '*.fzil' | wc -l | tr -d ' '
}

{
    echo "V8 VRP campaign summary"
    echo "======================="
    echo "out=$OUT"
    echo "v8_revision=$V8_REV"
    echo "duration_per_campaign=$DURATION"
    for storage in "$OUT"/storage/*; do
        [ -d "$storage" ] || continue
        name="$(basename "$storage")"
        echo "[$name] crashes=$(count "$storage/crashes") differentials=$(count "$storage/differentials")"
    done
    echo
    echo "Fault-injection canary crashes are NOT VRP candidates."
    echo "Triage each storage with Tools/v8-vrp-triage.py."
} >"$OUT/SUMMARY.txt"

cat "$OUT/SUMMARY.txt"
echo
echo "Campaign logs: $OUT/logs"
echo "Triage: Tools/v8-vrp-triage.py $OUT/storage/v8 --d8 $D8 --out $OUT/triage-v8"

