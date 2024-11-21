# Target: Spidermonkey

To build Spidermonkey for fuzzing:

1. Clone the Firefox mirror from https://github.com/mozilla/gecko-dev
2. Run the fuzzbuild.sh script in the gecko-dev root directory of the firefox checkout
3. gecko-dev/obj-fuzzbuild/dist/bin/js will be the JavaScript shell for the fuzzer
