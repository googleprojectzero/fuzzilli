# Processing Model

Fuzzilli's processing and threading model is fairly simple: every Fuzzer
instance has an associated sequential
[DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
on which all interactions with the fuzzer must happen. This architecture avoids
race conditions as work items are processed sequentially. It also makes it
rather straight forward to run multiple Fuzzer instances in one process.
Whenever code wants to interact with a fuzzer instance (i.e. call methods on
it, access properties, etc.) but (potentially) executes on a different
DispatchQueue, it has to first enqueue an operation into the Fuzzer's queue.
For that, the Fuzzer class exposes the `sync` and `async` functions which
essentially just enqueue the given work item into the fuzzer's DispatchQueue
and which can safely be called from a separate thread:

    fuzzer.async {
        // Can now interact with the fuzzer        
        fuzzer.importProgram(someProgram)
    }

Any code that is invoked by Fuzzilli (e.g. Mutators, Module initializers,
CodeGenerators, Event and Timer handlers, etc.) will always execute on the
fuzzer's dispatch queue and thus does not need to worry about enqueuing tasks
first. Only if code uses separate DispatchQueues, threads, etc. must it ensure
that it always interacts with the fuzzer on the correct queue. See e.g. the
ThreadSync or NetworkSync module for examples of this.

The dispatch queue of a typical Fuzzer instance commonly contains (some of) the
following items:

* A call to Fuzzer.fuzzOne to perform one iteration of fuzzing. When fuzzOne
  finishes, it will schedule the next fuzzing iteration.
* Handler blocks for any timers scheduled via the Fuzzer.timers API that have
  recently triggered
* Handlers for incoming network connections and data if the NetworkSync module
  is active
* Handlers for messages from other fuzzers if any of the fuzzer synchronization
  modules are active
* Program executions scheduled by the minimizer (which runs on a separate queue
  since it often takes a long time to complete)
