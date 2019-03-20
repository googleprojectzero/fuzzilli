# Target: v8

To build v8 for fuzzing:

1. Follow the instructions at https://v8.dev/docs/build
2. Apply v8.patch. The patch should apply cleanly to commit 1ca088652d3aad04caceb648bcffef100bc4abc0
3. Run the fuzzbuild.sh script in the v8 root directory
4. out/fuzzbuild/d8 will be the JavaScript shell for the fuzzer


Note that sanitizer coverage for v8 is currently not supported on macOS as it is missing from v8's custom clang toolchain.
