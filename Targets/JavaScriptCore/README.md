# Target: JavaScriptCore

To build JavaScriptCore (jsc) for fuzzing:

1. Clone the WebKit mirror from https://github.com/WebKit/webkit
2. Apply Patches/\*. The patches should apply cleanly to git commit 2dec5d49ff9071c73f7c33583a74cfb4779ba643
3. Run the fuzzbuild.sh script in the webkit root directory
4. FuzzBuild/Debug/bin/jsc will be the JavaScript shell for the fuzzer
