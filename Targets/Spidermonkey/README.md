# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Apply Patches/\*. The patches should apply cleanly to git commit 118a44681c35112a1c4f473d194509aeb5529a5d
3. Run the fuzzbuild.sh script in the js/src directory of the firefox checkout
4. ./fuzzbuild_OPT.OBJ/dist/bin/js will be the JavaScript shell for the fuzzer
