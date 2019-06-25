# Target: ChakraCore

To build ChakraCore (ch) for fuzzing:

1. Clone the ChakraCore from https://github.com/microsoft/ChakraCore
2. Apply chakracore.patch. The patch should apply cleanly to git commit 9296ec533c56ba50696868e531d3ec5d0994ed62
3. Run the fuzzbuild.sh script in the ChakraCore root directory
4. FuzzBuild/Debug/ch will be the JavaScript shell for the fuzzer
