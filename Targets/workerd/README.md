# Target: workerd

To build workerd for fuzzing:

0. Clone [workerd](https://github.com/cloudflare/workerd/)
1. Follow the instructions [here](https://github.com/cloudflare/workerd/blob/main/README.md#getting-started) 
2. Run the fuzzbuild.sh script in the workerd root directory to build workerd with the fuzzili configuration
3. Test if REPRL works:
 `swift run REPRLRun <path-to-workerd> fuzzilli <path-to-capnp-config> --experimental`
4. Run Fuzzilli:
 `swift run -c release FuzzilliCli --inspect=all --profile=workerd <path-to-workerd> --additionalArguments=<path-to-workerd-config>,--experimental`
