# Target: v8

To build v8 for fuzzing:

1. Follow the instructions at https://v8.dev/docs/build
2. Optionally apply `Patches/maglev-fault-injection.patch` to test the Maglev
   Phi-untagging fault-injection profile.
3. Run the fuzzbuild.sh script in the v8 root directory
4. out/fuzzbuild/d8 will be the JavaScript shell for the fuzzer

Note that sanitizer coverage for v8 is currently not supported on macOS as it is missing from v8's custom clang toolchain.

## Maglev fault injection

`Patches/maglev-fault-injection.patch` adds
`--maglev-fuzz-drop-heapobject-check`. It simulates the 486657483
Phi-untagging HeapObjectness loss in `ConvertTaggedPhiTo`: the flag drops the
HeapObject bits of numeric Phis, corrupts a converted input, and removes the
subsequent `CheckHeapObject`. This makes the dedicated
`MaglevPhiHeapObjectnessFaultFuzzer` template crash deterministically.

Build the patched shell and run:

```bash
swift build -c release --product FuzzilliCli
.build/release/FuzzilliCli --profile=v8MaglevFaultInjection \
  --engine=hybrid --jobs=1 \
  --storagePath=/tmp/fuzzilli-maglev-fault \
  /path/to/v8/out/fuzzbuild/d8
```

See [Docs/V8VRPWorkflow.md](../../Docs/V8VRPWorkflow.md) for the full VRP
campaign, triage, and reporting workflow.
