# Target: v8

To build v8 for fuzzing:

1. Follow the instructions at https://v8.dev/docs/build
2. Run the fuzzbuild.sh script in the v8 root directory
3. out/fuzzbuild/d8 will be the JavaScript shell for the fuzzer

Note that sanitizer coverage for v8 is currently not supported on macOS as it is missing from v8's custom clang toolchain.
