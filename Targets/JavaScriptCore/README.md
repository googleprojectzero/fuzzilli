# Target: JavaScriptCore

To build JavaScriptCore (jsc) for fuzzing:

1. Clone the WebKit mirror from https://github.com/WebKit/webkit
2. Apply Patches/\*. The patches should apply cleanly to the git revision specified in [./REVISION](./REVISION)
   (_Note_: If you clone WebKit from `git.webkit.org`, the commit hash will differ)
3. Run the fuzzbuild.sh script in the webkit root directory
4. FuzzBuild/Debug/bin/jsc will be the JavaScript shell for the fuzzer
