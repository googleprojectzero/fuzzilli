# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Apply Patches/\*. The patches should apply cleanly to the git revision specified in [./REVISION](./REVISION)
3. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
4. ./fuzzbuild\_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
