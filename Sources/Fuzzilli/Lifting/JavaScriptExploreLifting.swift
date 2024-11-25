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

/// This file contains the JavaScript specific implementation of the Explore operation. See ExplorationMutator.swift for an overview of this feature.
struct JavaScriptExploreLifting {
    static let prefixCode = """
    // If a sample with this instrumentation crashes, it may need the `fuzzilli` function to reproduce the crash.
    if (typeof fuzzilli === 'undefined') fuzzilli = function() {};

    const explore = (function() {
        //
        // "Import" the common runtime-assisted mutator code. This will make various utility functions available.
        //
        \(JavaScriptRuntimeAssistedMutatorLifting.commonCode)


        //
        // "Import" the object introspection code. This is used to find properties and methods when exploring an object.
        //
        \(JavaScriptRuntimeAssistedMutatorLifting.introspectionCode)


        //
        // "Import" the Action implementation code.
        //
        \(JavaScriptRuntimeAssistedMutatorLifting.actionCode)

        // JS Action Operation groups. See e.g. exploreNumber() for examples of how they are used.
        const SHIFT_OPS = [OP_LEFT_SHIFT, OP_SIGNED_RIGHT_SHIFT, OP_UNSIGNED_RIGHT_SHIFT];
        // Unsigned shift is not defined for bigints.
        const BIGINT_SHIFT_OPS = [OP_LEFT_SHIFT, OP_SIGNED_RIGHT_SHIFT];
        const BITWISE_OPS = [OP_BITWISE_OR, OP_BITWISE_AND, OP_BITWISE_XOR];
        const ARITHMETIC_OPS = [OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD];
        const UNARY_OPS = [OP_INC, OP_DEC, OP_NEG, OP_BITWISE_NOT];
        const COMPARISON_OPS = [OP_COMPARE_EQUAL, OP_COMPARE_STRICT_EQUAL, OP_COMPARE_NOT_EQUAL, OP_COMPARE_STRICT_NOT_EQUAL, OP_COMPARE_GREATER_THAN, OP_COMPARE_LESS_THAN, OP_COMPARE_GREATER_THAN_OR_EQUAL, OP_COMPARE_LESS_THAN_OR_EQUAL];
        const BOOLEAN_BINARY_OPS = [OP_LOGICAL_AND, OP_LOGICAL_OR];
        const BOOLEAN_UNARY_OPS = [OP_LOGICAL_NOT];


        //
        // Global constants.
        //
        // Property names to use when defining new properties. Should be kept in sync with the equivalent set in JavaScriptEnvironment.swift
        const customPropertyNames = [\(JavaScriptEnvironment.CustomPropertyNames.map({ "\"\($0)\"" }).joined(separator: ", "))];

        // Maximum number of parameters for function/method calls. Everything above this is consiered an invalid .length property of the function.
        const MAX_PARAMETERS = 10;

        // Well known integer/number values to use when generating random values.
        const WELL_KNOWN_INTEGERS = filter([\(JavaScriptEnvironment.InterestingIntegers.map(String.init).joined(separator: ", "))], isInteger);
        const WELL_KNOWN_NUMBERS = concat(WELL_KNOWN_INTEGERS, [-1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6]);
        const WELL_KNOWN_BIGINTS = [\(JavaScriptEnvironment.InterestingIntegers.map({ "\($0)n" }).joined(separator: ", "))];


        //
        // Global state.
        //

        // The concrete argument values that will be used when executing the Action for the current exploration operation.
        let exploreArguments;

        // The input containing the value being explored. This should always be the first input to every Action created during exploration.
        let exploredValueInput;

        // Whether exploration is currently happening. This is required to detect recursive exploration, where for example a callback
        // triggered during property enumeration triggers further exploration calls. See explore().
        let currentlyExploring = false;


        //
        // Error and result reporting.
        //
        // Results (indexed by their ID) will be stored in here.
        const results = { __proto__: null };

        function reportError(msg) {
            fuzzilli('FUZZILLI_PRINT', 'EXPLORE_ERROR: ' + msg);
        }

        function recordFailure(id) {
            // Delete the property if it already exists (from recordAction).
            delete results[id];
            defineProperty(results, id, {__proto__: null, value: NO_ACTION});

            fuzzilli('FUZZILLI_PRINT', 'EXPLORE_FAILURE: ' + id);
        }

        function recordAction(id, action) {
            if (hasOwnProperty(results, id)) {
                throw "Duplicate action for " + id;
            }

            if (action === NO_ACTION) {
                // This is equivalent to a failure.
                return recordFailure(id);
            }

            action.id = id;

            // These are configurable as they may need to be overwritten (by recordFailure) in the future.
            defineProperty(results, id, {__proto__: null, value: action, configurable: true});

            fuzzilli('FUZZILLI_PRINT', 'EXPLORE_ACTION: ' + stringify(action));
        }

        function hasActionFor(id) {
            return hasOwnProperty(results, id);
        }

        function getActionFor(id) {
            return results[id];
        }

        //
        // Access to random inputs.
        //
        // These functions prefer to take an existing variable from the arguments to the Explore operations if it satistifes the specified criteria. Otherwise, they generate a new random value.
        // Testing whether an argument satisfies some criteria (e.g. be a value in a certain range) may trigger type conversions. This is expected as it may lead to interesting values being used.
        // These are grouped into a namespace object to make it more clear that they return an Input object (from one of the above constructors), rather than a value.
        //
        let Inputs = {
            randomArgument() {
                return new ArgumentInput(randomIntBelow(exploreArguments.length));
            },

            randomArguments(n) {
                let args = EmptyArray();
                for (let i = 0; i < n; i++) {
                    push(args, new ArgumentInput(randomIntBelow(exploreArguments.length)));
                }
                return args;
            },

            randomArgumentForReplacing(propertyName, obj) {
                let curValue = tryGetProperty(propertyName, obj);
                if (isUndefined(curValue)) {
                    return Inputs.randomArgument();
                }

                function isCompatible(arg) {
                    let sameType = typeof curValue === typeof arg;
                    if (sameType && isObject(curValue)) {
                        sameType = arg instanceof curValue.constructor;
                    }
                    return sameType;
                }

                let idx = findIndex(exploreArguments, wrapInTryCatch(isCompatible));
                if (idx != -1) return new ArgumentInput(idx);
                return Inputs.randomArgument();
            },

            randomInt() {
                let idx = findIndex(exploreArguments, isInteger);
                if (idx != -1) return new ArgumentInput(idx);
                return new IntInput(randomElement(WELL_KNOWN_INTEGERS));
            },

            randomNumber() {
                let idx = findIndex(exploreArguments, isNumber);
                if (idx != -1) return new ArgumentInput(idx);
                return new FloatInput(randomElement(WELL_KNOWN_NUMBERS));
            },

            randomBigint() {
                let idx = findIndex(exploreArguments, isBigint);
                if (idx != -1) return new ArgumentInput(idx);
                return new BigintInput(randomElement(WELL_KNOWN_BIGINTS));
            },

            randomIntBetween(start, end) {
                if (!isInteger(start) || !isInteger(end)) throw "Arguments to randomIntBetween must be integers";
                let idx = findIndex(exploreArguments, wrapInTryCatch((e) => NumberIsInteger(e) && (e >= start) && (e < end)));
                if (idx != -1) return new ArgumentInput(idx);
                return new IntInput(randomIntBetween(start, end));
            },

            randomBigintBetween(start, end) {
                if (!isBigint(start) || !isBigint(end)) throw "Arguments to randomBigintBetween must be bigints";
                if (!isInteger(Number(start)) || !isInteger(Number(end))) throw "Arguments to randomBigintBetween must be representable as regular integers";
                let idx = findIndex(exploreArguments, wrapInTryCatch((e) => (e >= start) && (e < end)));
                if (idx != -1) return new ArgumentInput(idx);
                return new BigintInput(randomBigintBetween(start, end));
            },

            randomNumberCloseTo(v) {
                if (!isFinite(v)) throw "Argument to randomNumberCloseTo is not a finite number: " + v;
                let idx = findIndex(exploreArguments, wrapInTryCatch((e) => (e >= v - 10) && (e <= v + 10)));
                if (idx != -1) return new ArgumentInput(idx);
                let step = randomIntBetween(-10, 10);
                let value = v + step;
                if (isInteger(value)) {
                  return new IntInput(value);
                } else {
                  return new FloatInput(v + step);
                }
            },

            randomBigintCloseTo(v) {
                if (!isBigint(v)) throw "Argument to randomBigintCloseTo is not a bigint: " + v;
                let idx = findIndex(exploreArguments, wrapInTryCatch((e) => (e >= v - 10n) && (e <= v + 10n)));
                if (idx != -1) return new ArgumentInput(idx);
                let step = randomBigintBetween(-10n, 10n);
                let value = v + step;
                return new BigintInput(value);
            }
        }

        // Heuristic to determine when a function should be invoked as a constructor. Used by the object and function exploration code.
        function shouldTreatAsConstructor(f) {
            let name = tryGetProperty('name', f);

            // If the function has no name (or a non-string name), it's probably a regular function (or something like an arrow function).
            if (!isString(name) || name.length < 1) {
                return probability(0.1);
            }

            // If the name is something like `f42`, it's probably a function defined by Fuzzilli. These can typicall be used as function or constructor, but prefer to call them as regular functions.
            if (name[0] === 'f' && !isNaN(parseInteger(stringSlice(name, 1)))) {
              return probability(0.2);
            }

            // Otherwise, the basic heuristic is that functions that start with an uppercase letter (e.g. Object, Uint8Array, etc.) are probably constructors (but not always, e.g. BigInt).
            // This is also compatible with Fuzzilli's lifting of classes, as they will look something like this: `class V3 { ...`.
            if (name[0] === toUpperCase(name[0])) {
              return probability(0.9);
            } else {
              return probability(0.1);
            }
        }

        //
        // Explore implementation for different basic types.
        //
        // These all return an Action object or the special NO_ACTION value (null).
        //
        function exploreObject(o) {
            if (o === null) {
                return exploreNullish(o);
            }

            // TODO: Add special handling for ArrayBuffers: most of the time, wrap these into a Uint8Array to be able to modify them.
            // TODO: Sometimes iterate over iterable objects (e.g. Arrays)?

            // Determine a random property, which can generally either be a method, an element, or a "regular" property.
            let propertyName = randomPropertyOf(o);

            // Determine the appropriate action to perform given the selected property.
            // If the property lookup failed (for whatever reason), we always define a new property.
            if (propertyName === null) {
                let propertyNameInput = new StringInput(randomElement(customPropertyNames));
                return new Action(OP_SET_PROPERTY, [exploredValueInput, propertyNameInput, Inputs.randomArgument()]);
            } else if (isInteger(propertyName)) {
                let propertyNameInput = new IntInput(propertyName);
                if (probability(0.5)) {
                    return new Action(OP_GET_PROPERTY, [exploredValueInput, propertyNameInput]);
                } else {
                    let newValue = Inputs.randomArgumentForReplacing(propertyName, o);
                    return new Action(OP_SET_PROPERTY, [exploredValueInput, propertyNameInput, newValue]);
                }
            } else if (isString(propertyName)) {
                let propertyNameInput = new StringInput(propertyName);
                let propertyValue = tryGetProperty(propertyName, o);
                if (isFunction(propertyValue)) {
                    // Perform a method call/construct.
                    let numParameters = tryGetProperty('length', propertyValue);
                    if (!isInteger(numParameters) || numParameters > MAX_PARAMETERS || numParameters < 0) return NO_ACTION;
                    let inputs = EmptyArray();
                    push(inputs, exploredValueInput);
                    push(inputs, propertyNameInput);
                    for (let i = 0; i < numParameters; i++) {
                        push(inputs, Inputs.randomArgument());
                    }
                    if (shouldTreatAsConstructor(propertyValue)) {
                      return new GuardedAction(OP_CONSTRUCT_METHOD, inputs);
                    } else {
                      return new GuardedAction(OP_CALL_METHOD, inputs);
                    }
                } else {
                    // Perform a property access.
                    // Besides getting and setting the property, we also sometimes define a new property instead.
                    if (probability(1/3)) {
                        propertyNameInput = new StringInput(randomElement(customPropertyNames));
                        return new Action(OP_SET_PROPERTY, [exploredValueInput, propertyNameInput, Inputs.randomArgument()]);
                    } else if (probability(0.5)) {
                        return new Action(OP_GET_PROPERTY, [exploredValueInput, propertyNameInput]);
                    } else {
                        let newValue = Inputs.randomArgumentForReplacing(propertyName, o);
                        return new Action(OP_SET_PROPERTY, [exploredValueInput, propertyNameInput, newValue]);
                    }
                }
            } else {
              throw "Got unexpected property name from Inputs.randomPropertyOf(): " + propertyName;
            }
        }

        function exploreFunction(f) {
            // Sometimes treat functions as objects.
            // This will cause interesting properties like 'arguments' or 'prototype' to be accessed, methods like 'apply' or 'bind' to be called, and methods on builtin constructors like 'Array', and 'Object' to be used.
            if (probability(0.5)) {
                return exploreObject(f);
            }

            // Otherwise, call or construct the function/constructor.
            let numParameters = tryGetProperty('length', f);
            if (!isInteger(numParameters) || numParameters > MAX_PARAMETERS || numParameters < 0) {
                numParameters = 0;
            }
            let inputs = EmptyArray();
            push(inputs, exploredValueInput);
            for (let i = 0; i < numParameters; i++) {
                push(inputs, Inputs.randomArgument());
            }
            let operation = shouldTreatAsConstructor(f) ? OP_CONSTRUCT : OP_CALL_FUNCTION;
            return new GuardedAction(operation, inputs);
        }

        function exploreString(s) {
            // Sometimes (rarely) compare the string against it's original value. Otherwise, treat the string as an object.
            // TODO: sometimes access a character of the string or iterate over it?
            if (probability(0.1) && isSimpleString(s)) {
                return new Action(OP_COMPARE_EQUAL, [exploredValueInput, new StringInput(s)]);
            } else {
                return exploreObject(new String(s));
            }
        }

        const ALL_NUMBER_OPERATIONS = concat(SHIFT_OPS, BITWISE_OPS, ARITHMETIC_OPS, UNARY_OPS);
        const ALL_NUMBER_OPERATIONS_AND_COMPARISONS = concat(ALL_NUMBER_OPERATIONS, COMPARISON_OPS);
        function exploreNumber(n) {
            // Somewhat arbitrarily give comparisons a lower probability when choosing the operation to perform.
            let operation = randomElement(probability(0.5) ? ALL_NUMBER_OPERATIONS : ALL_NUMBER_OPERATIONS_AND_COMPARISONS);

            let action = new Action(operation);
            push(action.inputs, exploredValueInput);
            if (includes(COMPARISON_OPS, operation)) {
                if (isNaN(n)) {
                    // In that case, regular comparisons don't make sense, so just test for isNaN instead.
                    action.operation = OP_TEST_IS_NAN;
                } else if (!isFinite(n)) {
                    // Similar to the NaN case, just test for isFinite here.
                    action.operation = OP_TEST_IS_FINITE;
                } else {
                    push(action.inputs, Inputs.randomNumberCloseTo(n));
                }
            } else if (includes(SHIFT_OPS, operation)) {
                push(action.inputs, Inputs.randomIntBetween(1, 32));
            } else if (includes(BITWISE_OPS, operation)) {
                push(action.inputs, Inputs.randomInt());
            } else if (includes(ARITHMETIC_OPS, operation)) {
                if (isInteger(n)) {
                    push(action.inputs, Inputs.randomInt());
                } else {
                    push(action.inputs, Inputs.randomNumber());
                }
            }
            return action;
        }

        const ALL_BIGINT_OPERATIONS = concat(BIGINT_SHIFT_OPS, BITWISE_OPS, ARITHMETIC_OPS, UNARY_OPS);
        const ALL_BIGINT_OPERATIONS_AND_COMPARISONS = concat(ALL_BIGINT_OPERATIONS, COMPARISON_OPS);
        function exploreBigint(b) {
            // Somewhat arbitrarily give comparisons a lower probability when choosing the operation to perform.
            let operation = randomElement(probability(0.5) ? ALL_BIGINT_OPERATIONS : ALL_BIGINT_OPERATIONS_AND_COMPARISONS);

            let action = new Action(operation);
            push(action.inputs, exploredValueInput);
            if (includes(COMPARISON_OPS, operation)) {
                push(action.inputs, Inputs.randomBigintCloseTo(b));
            } else if (includes(BIGINT_SHIFT_OPS, operation)) {
                push(action.inputs, Inputs.randomBigintBetween(1n, 128n));
            } else if (includes(BITWISE_OPS, operation) || includes(ARITHMETIC_OPS, operation)) {
                push(action.inputs, Inputs.randomBigint());
            }
            return action;
        }

        function exploreSymbol(s) {
            // Lookup or insert the symbol into the global symbol registry. This will also allow static typing of the output.
            return new Action(OP_SYMBOL_REGISTRATION, [exploredValueInput]);
        }

        const ALL_BOOLEAN_OPERATIONS = concat(BOOLEAN_BINARY_OPS, BOOLEAN_UNARY_OPS);
        function exploreBoolean(b) {
            let operation = randomElement(ALL_BOOLEAN_OPERATIONS);

            let action = new Action(operation);
            push(action.inputs, exploredValueInput);
            if (includes(BOOLEAN_BINARY_OPS, operation)) {
                // It probably doesn't make sense to hardcode boolean constants, so always use an existing argument.
                push(action.inputs, Inputs.randomArgument());
            }
            return action;
        }

        function exploreNullish(v) {
            // Best thing we can do with nullish values is a NullCoalescing (??) operation.
            return new Action(OP_NULL_COALESCE, [exploredValueInput, Inputs.randomArgument()])
        }

        // Explores the given value and returns an action to perform on it.
        function exploreValue(id, v) {
            if (isObject(v)) {
                return exploreObject(v);
            } else if (isFunction(v)) {
                return exploreFunction(v);
            } else if (isString(v)) {
                return exploreString(v);
            } else if (isNumber(v)) {
                return exploreNumber(v);
            } else if (isBigint(v)) {
                return exploreBigint(v);
            } else if (isSymbol(v)) {
                return exploreSymbol(v);
            } else if (isBoolean(v)) {
                return exploreBoolean(v);
            } else if (isUndefined(v)) {
                return exploreNullish(v);
            } else {
                throw "Unexpected value type: " + typeof v;
            }
        }

        //
        // Exploration entrypoint.
        //
        function explore(id, v, currentThis, args, rngSeed) {
            rng.reseed(rngSeed);

            // The given arguments may be used as inputs for the action.
            if (isUndefined(args) || args.length < 1) throw "Exploration requires at least one additional argument";

            // We may get here recursively for example if a Proxy is being explored which triggers further explore calls during e.g. property enumeration.
            // Probably the best way to deal with these cases is to just bail out from recursive explorations.
            if (currentlyExploring) return;
            currentlyExploring = true;

            // Set the global state for this explore operation.
            exploreArguments = args;
            exploredValueInput = new SpecialInput("exploredValue");

            // Check if we already have a result for this id, and if so repeat the same action again. Otherwise, explore.
            let action;
            if (hasActionFor(id)) {
                action = getActionFor(id);
            } else {
                action = exploreValue(id, v);
                recordAction(id, action);
            }

            // Now perform the selected action.
            let context = { arguments: args, specialValues: { "exploredValue": v }, currentThis: currentThis };
            let success = execute(action, context);

            // If the action failed, mark this explore operation as failing (which will set the action to NO_ACTION) so it won't be retried again.
            if (!success) {
                recordFailure(id);
            }

            currentlyExploring = false;
        }

        function exploreWithErrorHandling(id, v, thisValue, args, rngSeed) {
            try {
                explore(id, v, thisValue, args, rngSeed);
            } catch (e) {
                let line = tryHasProperty('line', e) ? tryGetProperty('line', e) : tryGetProperty('lineNumber', e);
                if (isNumber(line)) {
                    reportError("In line " + line + ": " + e);
                } else {
                    reportError(e);
                }
            }
        }

        return exploreWithErrorHandling;
    })();

    """

    static let exploreFunc = "explore"
}
