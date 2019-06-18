# Processing Model

Fuzzilli's processing and threading model is fairly simple: one Fuzzer instance has an associated
sequential [OperationQueue](https://developer.apple.com/documentation/foundation/operationqueue) on
which all interactions with the fuzzer must happen. The OperationQueue basically behaves like a
serial [DispathQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) but allows a
bit more control, e.g. setting a priority on an operation. This architecture avoids race conditions
as all actions happen sequentially on the queue. It also makes it rather straight forward to run
multiple Fuzzer instances in one process.

Essentially, in any code that is interacting with a Fuzzer instance the following assertion thus has
to hold: `assert(OperationQueue.current == fuzzer.queue)`. This assertion is actually in place in a
few central APIs in Fuzzilli to verify everything runs as expected. Whenever code wants to interact
with a fuzzer instance (i.e. call methods on it, access properties, etc.) but (potentially) executes
on a different OperationQueue/DispatchQueue than the instance's, it has to first enqueue an
operation into the Fuzzer's queue:

    fuzzer.queue.addOperation {        
        // Can now interact with the fuzzer        
        fuzzer.importProgram(someProgram)
    }

Any code that is invoked by Fuzzilli (e.g. Mutators, Module initializers, CodeGenerators, Event and
Timer handlers, etc.) will always execute on the fuzzer's operation queue and thus does not need to
worry about enqueuing tasks first. Only if code uses further DispatchQueues, threads, etc. must it
ensure that it only interacts with the fuzzer on the correct queue. See e.g. the ThreadSync module
for an example of this.

The operation queue of a typical fuzzer commonly contains (some of) the following items:

* A call to Fuzzer.fuzzOne to perform the next round of fuzzing. This operation is enqueued with  
  lowest priority so actual fuzzing is only performed when there is nothing else (e.g. worker  
  synchronization) to do. When fuzzOne finishes one round of fuzzing it will enqueue the next  
  fuzzOne operation. As such there will always be a fuzzOne operation queued
* Handler blocks for any timers scheduled via the Fuzzer.timers API that have recently triggered
* Event handlers for asynchronously dispatched events (See Events.swift). Synchronously dispatched  
  events on the other hand execute directly in the context of the code that dispatches the event,  
  which must, of course, also execute on the fuzzer's operation queue
* Handlers for incoming network connections and data if the NetworkSync module is active
* Handlers for messages from other fuzzers in the network if any of the synchronization modules is  
  active
* ...
