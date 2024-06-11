# Target: NJS

To build njs for fuzzing:
* Step 1 - prepare env
    * Run `fuzzbuild.sh`, this will:
        * Clone the NJS repo from https://github.com/nginx/njs/
        * Apply the relevant patches & add a _fuzzilli_ JS module
* Step 2 - navigate to the njs root directory & run `./configure --cc=clang --cc-opt="-g -fsanitize-coverage=trace-pc-guard"`
* Step 3 - To compile a fuzzable binary run `make njs_fuzzilli`
    * The build will be saved at `<njs-dir>/build/njs_fuzzilli`

