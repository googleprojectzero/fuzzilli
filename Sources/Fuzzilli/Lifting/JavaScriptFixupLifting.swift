// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// This file contains the JavaScript specific implementation of the Fixup operation. See FixupMutator.swift for an overview of this feature.
struct JavaScriptFixupLifting {
    static let prefixCode = """
    // If a sample with this instrumentation crashes, it may need the `fuzzilli` function to reproduce the crash.
    if (typeof fuzzilli === 'undefined') fuzzilli = function() {};

    const fixup = (function() {
        //
        // "Import" the common runtime-assisted mutator code. This will make various utility functions available.
        //
        \(JavaScriptRuntimeAssistedMutatorLifting.commonCode)


        //
        // "Import" the Action implementation code.
        //
        \(JavaScriptRuntimeAssistedMutatorLifting.actionCode)


        //
        // Error and result reporting.
        //
        // The actions to perform (indexed by their ID) will be stored in here.
        // TODO: here and in ExploreLifting, should this be a Map instead?
        const actions = { __proto__: null };
        // We remember which actions have failed in the past, so we only report failures once.
        const failures = new SetConstructor();

        function reportError(msg) {
            fuzzilli('FUZZILLI_PRINT', 'FIXUP_ERROR: ' + msg);
        }

        function recordFailure(id) {
            setAdd(failures, id);
            fuzzilli('FUZZILLI_PRINT', 'FIXUP_FAILURE: ' + id);
        }

        function recordAction(id, action) {
            if (action.id !== id) throw "Inconsistent action for id " + id;
            if (hasOwnProperty(actions, id)) throw "Duplicate action for " + id;

            // These are configurable as they may need to be overwritten (by recordFailure) in the future.
            defineProperty(actions, id, {__proto__: null, value: action, configurable: true});

            fuzzilli('FUZZILLI_PRINT', 'FIXUP_ACTION: ' + stringify(action));
        }

        function hasActionFor(id) {
            return hasOwnProperty(actions, id);
        }

        function getActionFor(id) {
            return actions[id];
        }

        function hasPreviouslyFailed(id) {
            return setHas(failures, id);
        }

        //
        // Fixup function.
        //
        function fixup(id, originalAction, args, currentThis) {
            // See if this is the first time that we're executing this action. If it is, then now is the (only) timewhen  we can modify the action.
            let action;
            if (hasActionFor(id)) {
                action = getActionFor(id);
            } else {
                // TODO: this is where we could change the action.
                // If changing actions, we should try to not change the type of inputs though. For example, we probably should not
                // turn a computed property load (where the property name is an argument input) into a "regular" property load
                // (where the property name is a string input).
                action = originalAction;
            }

            // Now perform the selected action.
            let context = { arguments: args, specialValues: {}, currentThis: currentThis, output: undefined };
            let success = execute(action, context);

            // If the action failed and isn't guarded (either because it wasn't in the first place or because we've previously removed the guard), then record a failure.
            // This will signal to Fuzzilli that the action either needs a guard or should be removed.
            // As we may execute this action again, we remember which actions have failed in the past and only report the first failure.
            if (!success && !hasPreviouslyFailed(id)) {
                recordFailure(id);
            }

            // If this was the first time the action was executed, report the (possibly modified) action.
            // This has to happen after executing the action as that may remove unecessary guards.
            if (!hasActionFor(id)) {
                recordAction(id, action);
            }

            // Return the action's output value as it may be used by subsequent code.
            return context.output;
        }

        function fixupWithErrorHandling(id, originalAction, args, currentThis) {
            try {
                return fixup(id, originalAction, args, currentThis);
            } catch (e) {
                let line = tryHasProperty('line', e) ? tryGetProperty('line', e) : tryGetProperty('lineNumber', e);
                if (isNumber(line)) {
                    reportError("In line " + line + ": " + e);
                } else {
                    reportError(e);
                }
            }
        }

        return fixupWithErrorHandling;
    })();
    """

    static let fixupFunc = "fixup"
}
