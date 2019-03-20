# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Apply firefox.patch. The patch should apply cleanly to git commit 165f0d8c1c52595dde13db317c001503e0a54865
3. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
4. ./fuzzbuild_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
