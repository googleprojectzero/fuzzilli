# Target: JerryScript

To build JerryScript for fuzzing:

1. Clone the JerryScript repository from https://github.com/jerryscript-project/jerryscript
2. Apply Patches/\*. The patches should apply cleanly to the git revision specified in [./REVISION](./REVISION)
3. Run the fuzzbuild.sh script in the jerryscript directory
4. ./build/bin/jerry will be the JavaScript shell for the fuzzer
