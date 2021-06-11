# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
3. fuzzbuild_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
