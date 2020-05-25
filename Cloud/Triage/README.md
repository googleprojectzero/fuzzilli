# Triage

Small script to help with crash triaging.

## Usage

The script requires a local build of the target JS engine. For JavaScriptCore and Spidermonkey an ASAN build is recommended. Once the build is complete, simply run the script, providing it with the path to the JS shell, the path to the crashes/ directory that fuzzilli produced, and the commandline arguments for the JS shell (get those from the [respective profile](../../Sources/FuzzilliCli/Profiles)):

    ./check.sh ./crashes ~/WebKit/AsanBuild/Debug/bin/jsc --validateOptions=true --useConcurrentJIT=false --useConcurrentGC=false --thresholdForJITSoon=10 --thresholdForJITAfterWarmUp=10 --thresholdForOptimizeAfterWarmUp=100 --thresholdForOptimizeAfterLongWarmUp=100 --thresholdForOptimizeAfterLongWarmUp=100 --thresholdForFTLOptimizeAfterWarmUp=1000 --thresholdForFTLOptimizeSoon=1000 --gcAtEnd=true

The file will produce a log with all output from stdout and stderr (which includes Asan crash reports). Afterwards, you can grep (and uniquify) the log for certain keywords such as
- for JSC: "trap", "assert", "segv", "Sanitizer"
- for Spidernmonkey: "trap", "assert", "segv", "Sanitizer"
- for V8: "Debug check failed", "Check failed", "assert", "fatal", "received"
