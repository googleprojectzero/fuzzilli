# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Apply firefox.patch. The patch should apply cleanly to git commit 1068d61acb8a68101e6c922f27c82fbdf65d53d7
3. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
4. ./fuzzbuild_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
