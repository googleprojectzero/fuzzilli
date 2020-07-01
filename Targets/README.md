# Adding New Targets

This covers how to add a new Javascript engine as a Fuzzilli target.
Please note that particular configuration decisions are not "one size fits all", due to the range of requirements between various Javascript engines.

## Modifications to Target JS Engine

### Compilation Changes
The target Javascript engine should be compiled with appropriate debug parameters in order to catch errors that would not crash the production build.
Examples include debug asserts and heap validation.
Note that some sanitizers modify program return values, which Fuzzilli uses to determine when and how the engine crashes.
For example, clang's undefined behavior sanitizer requires processEnv in its profile (see below) to be `"UBSAN_OPTIONS": "handle_segv=0"`.

### Code Coverage
Fuzzilli performs guided fuzzing based on code coverage.
In order to implement this, [coverage.c](./coverage.c) needs to be included in the build, and `__sanitizer_cov_reset_edgeguards()` needs to be available for the REPRL implementation. 

### Adding Read-Eval-Print-Reset-Loop
In order to iterate quickly with minimal overhead, Fuzzilli operates with a Read-Eval-Print-Reset loop, where 1 process of the engine runs many test cases, resetting itself between each one.
This is done to reduce the overhead occurred when starting a new instance of the JS engine. 
The max number of iterations value is set by the `maxExecsBeforeRespawn` constant [here](../Sources/Fuzzilli/Execution/REPRL.swift).
This loop needs to be triggered by a unique command line option (make sure to include as processArgument in the profile, see below).

#### REPRL Psuedocode
This is only rough psuedocode as an overview. Please reference the appropriate lines in one of the patch files for an example implementation.

```
(Must include the 4 defined File Descriptor numbers REPRL_CRFD, REPRL_CWFD, REPRL_DRFD, REPRL_DWFD)

if REPRL_MODE on commandline:
    write "HELO" on REPRL_CWFD
    read 4 bytes on REPRL_CRFD
    break if 4 read bytes do not equal "HELO"
    optionally, mmap the REPRL_DRFD with size REPRL_MAX_DATA_SIZE
    while true:
        read 4 bytes on REPRL_CRFD
        break if 4 read bytes do not equal "cexe"
        read 8 bytes on REPRL_CRFD, store as unsigned 64 bit integer size
        allocate size+1 bytes
        read size bytes from REPRL_DRFD into allocated buffer, either via memory mapped IO or the read syscall (make sure to account for short reads in the latter case)
        Execute buffer as javascript code
        Store return value from JS execution
        Flush stdout and stderr. As REPRL sets them to regular files, libc uses full bufferring for them, which means they need to be flushed after every execution
        Mask return value with 0xff and shift it left by 8, then write that value over REPRL_CWFD
        Reset the Javascript engine
        Call __sanitizer_cov_reset_edgeguards to reset coverage
```

REPRL's exit status format is similar to the one used on e.g. Linux or macOS: the lower 8 bits contain the number of the terminating signal (if any), the next 8 bits contain the exit status.
As such, it is also possible to "emulate" a crash in the target by setting the lower 8 bits of the exit status to a nonzero value. In that case, Fuzzilli would treat the execution as a crash.

### Adding Custom "fuzzilli" Javascript Builtin
At start, Fuzzilli calls functions specified in `crashTests` in the profile, in order to validate detection of crashes.
Thus, current targets add a custom function as a builtin, that either segfaults or fails a debug assertion when given particular strings as input.
The input strings are designed to be hard for the fuzzer to accidentally trigger, to prevent false positives.
This function should be added to the Javascript Engine under test, and listed with crashing inputs in the profile.

## Creation of Fuzzilli Profile

A profile provides the fuzzer information on the particulars of a Javascript engine, such as unique builtins for that engine.
Example profiles for v8, Spidermonkey, and JavaScriptCore can be found [here](../Sources/FuzzilliCli/Profiles).
Once a profile has been made, it also needs to be added to the list in [Profile.swift](../Sources/FuzzilliCli/Profiles/Profile.swift).

### Profile Fields

- `processArguments`: Command line arguments to call the Javascript engine with
- `processEnv`: Environment variables to set when calling the Javascript engine
- `codePrefix` and `codeSuffix`: Javascript code that is added to the beginning/end of each generated test case. This can setup and call `main`, force garbage collection, etc. 
- `crashTests`: Functions to call that intentionally fault, in order to validate that Fuzzilli properly detects crashes and assertion failures in the JS engine.
- `additionalCodeGenerators`: Additional code generators, called the fuzzer in building test cases. An example use case is producing code to trigger JIT compilation in V8.
- `additionalBuiltins`: Additional unique builtins for the JS engine. This list does not have to exhaustive, but should include functionality likely to cause bugs. An example would be a function that triggers garbage collection. 
