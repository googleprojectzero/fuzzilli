# Target: NJS

To build njs for fuzzing:
* Step 1 - prepare env
    * Run `setup.sh`, this will:
        * Clone the NJS repo from https://github.com/nginx/njs/
        * Apply the relevant patches & add a _fuzzilli_ JS module
* Step 2 - Build fuzzer
    * Run `fuzzbuild.sh`, this will:
        * Configure with `./configure --cc=clang --cc-opt="-g -fsanitize-coverage=trace-pc-guard"`
        * Run `make njs_fuzzilli`

The REPRL shell/fuzzable build will be saved at `<njs-dir>/build/njs_fuzzilli`

