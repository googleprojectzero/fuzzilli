# V8 VRP fuzzing workflow

This document describes how to run Fuzzilli to find V8 bugs that are candidates
for the Chrome/V8 Vulnerability Reward Program (VRP), triage them, and produce a
report.

The key rule: **fault-injection runs are harness canaries, not VRP findings.**
The `v8MaglevFaultInjection` profile and
`--maglev-fuzz-drop-heapobject-check` deliberately introduce Maglev Phi
representation bugs. Do not report their crashes. Use them only to verify that a
template and oracle can observe a shape.

## 1. Build the target

Use the V8 fuzzbuild described in [Targets/V8/README.md](../Targets/V8/README.md):

```bash
cd /path/to/v8
gn gen out/fuzzbuild --args='is_debug=false dcheck_always_on=true \
  v8_static_library=true v8_enable_verify_heap=true \
  v8_enable_partition_alloc=false v8_fuzzilli=true \
  sanitizer_coverage_flags="trace-pc-guard" target_cpu="x64"'
ninja -C out/fuzzbuild d8
```

For memory-corruption confirmation, also build ASan:

```bash
gn gen out/asan --args='is_debug=false dcheck_always_on=true is_asan=true \
  v8_fuzzilli=true v8_enable_verify_heap=true \
  v8_enable_partition_alloc=false \
  sanitizer_coverage_flags="trace-pc-guard" target_cpu="x64"'
ninja -C out/asan d8
```

Build the Fuzzilli CLI:

```bash
cd /path/to/fuzzilli
swift build -c release --product FuzzilliCli
```

The default VRP workflow must **not** pass
`--maglev-fuzz-drop-heapobject-check`.

## 2. Run campaigns

The campaign driver runs the crash and silent-miscompilation profiles and keeps
metadata, logs, and per-campaign storage:

```bash
Tools/v8-vrp-campaign.sh \
  --d8 /path/to/v8/out/fuzzbuild/d8 \
  --asan-d8 /path/to/v8/out/asan/d8 \
  --jobs 8 \
  --duration 2h \
  --out /tmp/v8-vrp-run
```

Defaults:
- profiles: `v8,v8Maglev`
- output: `/tmp/v8-vrp-<timestamp>`
- `v8` hunts assertions/crashes, `v8Maglev` hunts Maglev vs. reference
  output/behavior differences.
- `--canary` additionally runs `v8MaglevFaultInjection`; its crashes are
  injected and are labeled as such in the summary/report.
- `--resume` imports the existing corpus and continues an existing storage.

Outputs:
- `metadata.txt` — revision, d8 hashes/versions, profiles, duration.
- `SUMMARY.txt` — crash/differential counts per campaign.
- `logs/<profile>.log` — Fuzzilli logs.
- `storage/<profile>/crashes/` — crash programs (`.fzil` + `.js`).
- `storage/<profile>/differentials/` — differential programs.
- `storage/<profile>/corpus/` — corpus for resuming.
- `storage/<profile>/stats/` — statistics snapshots.

For multi-day campaigns, use a stable `--out`, a long `--duration`, and
`--resume` on subsequent runs. Run against several configurations (dcheck,
ASan, sandbox-enabled, `--future`, `--js-staging`) to broaden coverage.

## 3. Triage artifacts

The triage tool extracts the recorded target arguments, reproduces every crash
and differential, checks determinism, optionally runs ASan, and writes a
Markdown + JSON report:

```bash
Tools/v8-vrp-triage.py \
  /tmp/v8-vrp-run/storage/v8 \
  --d8 /path/to/v8/out/fuzzbuild/d8 \
  --asan-d8 /path/to/v8/out/asan/d8 \
  --out /tmp/v8-vrp-run/triage-v8
```

Useful flags:
- `--runs N` — reproduction attempts (default 3).
- `--include-duplicates` — also triage `crashes/duplicates`.
- `--fail-on-finding` — exit 2 if a deterministic, non-injected crash or
  differential is found (suitable for CI).
- `--json` — only write `report.json`.

The report marks each candidate with:
- crash vs. differential,
- deterministic or flaky,
- whether the injected fault flag is present,
- ASan result,
- contributors (templates/generators),
- a ready-to-run reproduction command and stderr excerpt.

Programs are copied to the triage directory for easy reproduction. The tools
use the `TARGET ARGS` / `ARGS` / `REFERENCE ARGS` footer that Fuzzilli writes
into stored programs; `settings.json` is used as a fallback.

### Manual checks for a candidate

1. Reproduce on a clean, non-fault d8 with the recorded arguments.
2. Run it several times and with a fresh process to confirm determinism.
3. Confirm the fault flag is absent.
4. Run under ASan/MSan and look for `AddressSanitizer` /
   `UndefinedBehaviorSanitizer` output.
5. Minimize the JS if needed (`FuzzILTool --liftToJS`, then manual reduction,
   or Fuzzilli's automatic minimizer).
6. Compare Maglev and reference runs for differentials; ensure output
   differences are not due to nondeterminism (Date, `Math.random`,
   `performance.now`, GC timing, timeouts).
7. Decide whether the behavior is security-relevant: type confusion, OOB
   read/write, UAF, sandbox violation, etc.

Common false positives:
- **Reference timeout**: the interpreter/Sparkplug run is slower. The
  differential oracle gives the reference a larger timeout and ignores its
  timeout as a differential. Re-check with a larger `--timeout` if a program is
  close to the boundary.
- **Nondeterministic output**: use the determinism check and fresh processes.
- **Injected fault**: anything with `--maglev-fuzz-drop-heapobject-check` is a
  harness test, not a V8 bug.

## 4. Report to the VRP

Report security-sensitive V8 bugs through the Chrome VRP / Chromium security
tracker. A good report contains:

- V8 revision/commit and build configuration (dcheck/ASan/sandbox).
- The exact d8 flags and the minimized JS (or `.fzil` plus lifted JS).
- Expected vs. actual behavior.
- Crash/sanitizer output and signal/exit code.
- Security impact analysis (how the bug yields OOB/UAF/type confusion and
  whether it is sandbox-relevant).
- Confirmation that the issue is reproducible and not already fixed.

Suggested process:
1. Search for an existing report and check the V8/Chromium revision.
2. File a **Security** issue in the Chromium issue tracker with component
   `Blink>JavaScript` if applicable.
3. Mark it security-sensitive until fixed.
4. Submit through the Chrome Vulnerability Reward Program:
   <https://bughunters.google.com/report>

## 5. What the profiles target

- `v8`: general JavaScript/Maglev crash and assertion hunting.
- `v8Maglev`: Maglev vs. `--no-maglev --no-turbofan` differential; catches
  silent representation/type-confusion miscompiles.
- `v8Sandbox`: sandbox testing (`--sandbox-testing`).
- `v8holefuzzing`: hole/undefined-related bugs.

Maglev-focused templates cover elements kinds, maps/field representations,
typed arrays, binary feedback, call/inlining, loops/Phis, value-equal
HeapNumber vs. Smi, mixed-representation Phis, backedge-only changes, and
inlined Smi proofs.

## 6. Automation checklist

- [ ] Non-fault fuzzbuild (and optionally ASan build) ready.
- [ ] `v8` campaign finished; crashes saved.
- [ ] `v8Maglev` differential campaign finished; differentials saved.
- [ ] Triage report generated with determinism/ASan fields.
- [ ] No `--maglev-fuzz-drop-heapobject-check` on reported candidates.
- [ ] Candidate reproduces on a clean d8 and under ASan.
- [ ] Security impact assessed and VRP report filed.

