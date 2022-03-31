# Target: XS

To build XS for fuzzing with Fuzzilli:

1. Install the Moddable SDK as explained in the [documentation](https://github.com/Moddable-OpenSource/moddable/blob/public/documentation/Moddable%20SDK%20-%20Getting%20Started.md#macos).<br>
(Note: Fuzzilli does not require the common Moddable development tools, so you can stop when you reach the step "Build the Moddable command line tools...")
2. Build `xst`, the XS test tool:

```console
cd $MODDABLE/xs/makefiles/mac
FUZZILLI=1 make
```

Use the debug `xst` binary as the JavaScript shell for the fuzzer. It is located at `$MODDABLE/build/bin/mac/debug/xst`.

> **Note**: `xst` only supports Fuzzilli on macOS. It should also work on Linux with minor changes.
