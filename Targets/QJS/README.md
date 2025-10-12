# Target: QuickJS

To build QuickJS for fuzzing:

1. Clone the QuickJS mirror from https://github.com/bellard/quickjs
2. Apply Patches/\*. The patches should apply cleanly to the git revision specified in [./REVISION](./REVISION)
3. Build QuickJS with `make qjs`
4. The `qjs` binary will be the JavaScript shell for the fuzzer
