# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Apply firefox.patch. The patch should apply cleanly to git commit b37d82a6c3a1b9e9c7d101c3c662e24d47bd226a
3. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
4. ./fuzzbuild_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
