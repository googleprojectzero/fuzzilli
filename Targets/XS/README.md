# Target: XS

To build XS for fuzzing with Fuzzilli:

1. Clone the Moddable SDK from [https://github.com/Moddable-OpenSource/moddable](https://github.com/Moddable-OpenSource/moddable)
2. Build `xst`, the XS test tool:

```console
cd $MODDABLE/xs/make/mac
FUZZILLI=1 make
```

Use the debug `xst` binary as the JavaScript shell for the fuzzer. It is located at `$MODDABLE/build/bin/mac/debug/xst`.

> **Note**: `xst` only supports Fuzzilli on macOS. It should also work on Linux with minor changes.
