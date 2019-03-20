# Target: JavaScriptCore

To build JavaScriptCore (jsc) for fuzzing:

1. Clone the WebKit mirror from https://github.com/WebKit/webkit
2. Apply webkit.patch. The patch should apply cleanly to git commit 8d7c264869ecbdd56fb46aa5762d82c318f39feb
3. Run the fuzzbuild.sh script in the webkit root directory
4. FuzzBuild/Debug/bin/jsc will be the JavaScript shell for the fuzzer
