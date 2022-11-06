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
struct JavaScriptExploreHelper {
    static let prefixCode = """
    const explore = (function() {
        // Note: this code must generally assume that any operation performed on the object to explore, or any object obtained through it (e.g. a prototype), may raise an exception, for example due to triggering a Proxy trap.
        // Further, it must also assume that the environment has been modified arbitrarily. For example, the Array.prototype[@@iterator] may have been set to an invalid value, so using `for...of` syntax could trigger an exception.

        // Load all necessary routines into local variables as they may be overwritten by the program.
        // We generally want to avoid triggerring observable side-effects, such as storing or loading
        // properties. For that reason, we prefer to use builtins like Object.defineProperty.
        const ObjectPrototype = Object.prototype;
        const getOwnPropertyNames = Object.getOwnPropertyNames;
        const getPrototypeOf = Object.getPrototypeOf;
        const setPrototypeOf = Object.setPrototypeOf;
        const stringify = JSON.stringify;
        const hasOwnProperty = Object.hasOwn;
        const defineProperty = Object.defineProperty;
        const propertyValues = Object.values;
        const parseInteger = parseInt;
        const NumberIsInteger = Number.isInteger;
        const isNaN = Number.isNaN;
        const isFinite = Number.isFinite;
        const random = Math.random;
        const truncate = Math.trunc;
        const apply = Reflect.apply;
        const construct = Reflect.construct;
        const makeBigInt = BigInt;
        // Bind methods to local variables. These all expect the 'this' object as first parameter.
        const concat = Function.prototype.call.bind(Array.prototype.concat);
        const findIndex = Function.prototype.call.bind(Array.prototype.findIndex);
        const includes = Function.prototype.call.bind(Array.prototype.includes);
        const shift = Function.prototype.call.bind(Array.prototype.shift);
        const pop = Function.prototype.call.bind(Array.prototype.pop);
        const push = Function.prototype.call.bind(Array.prototype.push);
        const match = Function.prototype.call.bind(RegExp.prototype[Symbol.match]);
        const stringSlice = Function.prototype.call.bind(String.prototype.slice);
        const toUpperCase = Function.prototype.call.bind(String.prototype.toUpperCase);
        const numberToString = Function.prototype.call.bind(Number.prototype.toString);
        const bigintToString = Function.prototype.call.bind(BigInt.prototype.toString);

        // When creating empty arrays to which elements are later added, use a custom array type that has a null prototype. This way, the arrays are not
        // affected by changes to the Array.prototype that could interfere with array builtins (e.g. indexed setters or a modified .constructor property).
        function EmptyArray() {
            let array = [];
            setPrototypeOf(array, null);
            return array;
        }


        //
        // Global constants.
        //

        const MIN_SAFE_INTEGER = Number.MIN_SAFE_INTEGER;
        const MAX_SAFE_INTEGER = Number.MAX_SAFE_INTEGER;

        // Property names to use when defining new properties. Should be kept in sync with the equivalent set in JavaScriptEnvironment.swift
        const customPropertyNames = ['a', 'b', 'c', 'd', 'e'];

        // Special value to indicate that no action should be performed, usually because there was an error performing the chosen action.
        const NO_ACTION = null;

        // Maximum number of parameters for function/method calls. Everything above this is consiered an invalid .length property of the function.
        const MAX_PARAMETERS = 10;

        // Well known integer/number values to use when generating random values.
        const WELL_KNOWN_INTEGERS = [-4294967296, -4294967295, -2147483648, -2147483647, -4096, -1024, -256, -128, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64, 128, 256, 1024, 4096, 65535, 65536, 2147483647, 2147483648, 4294967295, 4294967296];
        const WELL_KNOWN_NUMBERS = concat(WELL_KNOWN_INTEGERS, [-1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6]);
        const WELL_KNOWN_BIGINTS = [-18446744073709551616n, -9223372036854775808n, -9223372036854775807n, -9007199254740991n, -9007199254740990n, -4294967297n, -4294967296n, -4294967295n, -2147483648n, -2147483647n, -4096n, -1024n, -256n, -128n, -2n, -1n, 0n, 1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n, 16n, 64n, 128n, 256n, 1024n, 4096n, 65535n, 65536n, 2147483647n, 2147483648n, 4294967295n, 4294967296n, 4294967297n, 9007199254740990n, 9007199254740991n, 9223372036854775806n,  9223372036854775807n, 9223372036854775808n, 18446744073709551616n];

        //
        // List of all supported operations. Must be kept in sync with the ExplorationMutator.
        //
        const OP_CALL_FUNCTION = 'CALL_FUNCTION';
        const OP_CONSTRUCT = 'CONSTRUCT';
        const OP_CALL_METHOD = 'CALL_METHOD';
        const OP_CONSTRUCT_MEMBER = 'CONSTRUCT_MEMBER';
        const OP_GET_PROPERTY = 'GET_PROPERTY';
        const OP_SET_PROPERTY = 'SET_PROPERTY';
        const OP_DEFINE_PROPERTY = 'DEFINE_PROPERTY';
        const OP_GET_ELEMENT = 'GET_ELEMENT';
        const OP_SET_ELEMENT = 'SET_ELEMENT';

        const OP_ADD = 'ADD';
        const OP_SUB = 'SUB';
        const OP_MUL = 'MUL';
        const OP_DIV = 'DIV';
        const OP_MOD = 'MOD';
        const OP_INC = 'INC';
        const OP_DEC = 'DEC';
        const OP_NEG = 'NEG';

        const OP_LOGICAL_AND = 'LOGICAL_AND';
        const OP_LOGICAL_OR = 'LOGICAL_OR';
        const OP_LOGICAL_NOT = 'LOGICAL_NOT';

        const OP_BITWISE_AND = 'BITWISE_AND';
        const OP_BITWISE_OR = 'BITWISE_OR';
        const OP_BITWISE_XOR = 'BITWISE_XOR';
        const OP_LEFT_SHIFT = 'LEFT_SHIFT';
        const OP_SIGNED_RIGHT_SHIFT = 'SIGNED_RIGHT_SHIFT';
        const OP_UNSIGNED_RIGHT_SHIFT = 'UNSIGNED_RIGHT_SHIFT';
        const OP_BITWISE_NOT = 'BITWISE_NOT';

        const OP_COMPARE_EQUAL = 'COMPARE_EQUAL';
        const OP_COMPARE_STRICT_EQUAL = 'COMPARE_STRICT_EQUAL';
        const OP_COMPARE_NOT_EQUAL = 'COMPARE_NOT_EQUAL';
        const OP_COMPARE_STRICT_NOT_EQUAL = 'COMPARE_STRICT_NOT_EQUAL';
        const OP_COMPARE_GREATER_THAN = 'COMPARE_GREATER_THAN';
        const OP_COMPARE_LESS_THAN = 'COMPARE_LESS_THAN';
        const OP_COMPARE_GREATER_THAN_OR_EQUAL = 'COMPARE_GREATER_THAN_OR_EQUAL';
        const OP_COMPARE_LESS_THAN_OR_EQUAL = 'COMPARE_LESS_THAN_OR_EQUAL';
        const OP_TEST_IS_NAN = 'TEST_IS_NAN';
        const OP_TEST_IS_FINITE = 'TEST_IS_FINITE';

        const OP_SYMBOL_REGISTRATION = 'SYMBOL_REGISTRATION';

        // Operation groups. See e.g. exploreNumber() for examples of how they are used.
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
        // Global variables.
        //
        // The arguments given to the Explore operation which can be used by the concrete action.
        let exploreArguments;

        // The current value of |this| when exploring. Needed to correctly set the |this| value when performing a regular function call (see OP_CALL_FUNCTION handler).
        let currentThis;

        // Whether exploration is currently happening. This is required to detect recursive exploration, where for example a callback
        // triggered during property enumeration triggers further exploration calls. See explore().
        let currentlyExploring = false;

        //
        // Error and result reporting.
        // The concrete action performed by an Explore operation is encoded and transmitted as an object: {operation: OP_SOMETHING, inputs: inputs_array}.
        // The operation is one of the above constants, the inputs is an array of input objects, see below.
        //

        // Results (indexed by their ID) will be stored in here.
        const results = { __proto__: null };

        function reportError(msg) {
            fuzzilli('FUZZILLI_PRINT', 'EXPLORE_ERROR: ' + msg);
        }

        function recordFailure(id) {
            // Delete the property if it already exists (from recordAction).
            delete results[id];
            defineProperty(results, id, {__proto__: null, value: null});

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
        // Misc. helper functions.
        //
        // Type check helpers. These are less error-prone than manually using typeof and comparing against a string.
        function isObject(v) {
            return typeof v === 'object';
        }
        function isFunction(v) {
            return typeof v === 'function';
        }
        function isString(v) {
            return typeof v === 'string';
        }
        function isNumber(v) {
            return typeof v === 'number';
        }
        function isBigint(v) {
            return typeof v === 'bigint';
        }
        function isSymbol(v) {
            return typeof v === 'symbol';
        }
        function isBoolean(v) {
            return typeof v === 'boolean';
        }
        function isUndefined(v) {
            return typeof v === 'undefined';
        }

        // Helper function to determine if a value is an integer, and within [MIN_SAFE_INTEGER, MAX_SAFE_INTEGER].
        function isInteger(n) {
            return isNumber(n) && NumberIsInteger(n) && n>= MIN_SAFE_INTEGER && n <= MAX_SAFE_INTEGER;
        }

        // Helper function to determine if a string is "simple". We only include simple strings for property/method names or string literals.
        // A simple string is basically a valid, property name with a maximum length.
        function isSimpleString(s) {
            if (!isString(s)) throw "Non-string argument to isSimpleString: " + s;
            return s.length < 50 && match(/^[0-9a-zA-Z_$]+$/, s);
        }

        // Helper function to determine whether a property can be accessed without raising an exception.
        function tryAccessProperty(prop, obj) {
            try {
                obj[prop];
                return true;
            } catch (e) {
                return false;
            }
        }

        // Helper function to determine if a property exists on an object or one of its prototypes. If an exception is raised, false is returned.
        function tryHasProperty(prop, obj) {
            try {
                return prop in obj;
            } catch (e) {
                return false;
            }
        }

        // Helper function to load a property from an object. If an exception is raised, undefined is returned.
        function tryGetProperty(prop, obj) {
            try {
                return obj[prop];
            } catch (e) {
                return undefined;
            }
        }

        // Helper function to obtain the own properties of an object. If that raises an exception (e.g. on a Proxy object), an empty array is returned.
        function tryGetOwnPropertyNames(obj) {
            try {
                return getOwnPropertyNames(obj);
            } catch (e) {
                return new Array();
            }
        }

        // Helper function to fetch the prototype of an object. If that raises an exception (e.g. on a Proxy object), null is returned.
        function tryGetPrototypeOf(obj) {
            try {
                return getPrototypeOf(obj);
            } catch (e) {
                return null;
            }
        }

        // Helper function to that creates a wrapper function for the given function which will call it in a try-catch and return false on exception.
        function wrapInTryCatch(f) {
            return function() {
                try {
                    return apply(f, this, arguments);
                } catch (e) {
                    return false;
                }
            };
        }


        //
        // Basic random number generation utility functions.
        //
        function probability(p) {
            if (p < 0 || p > 1) throw "Argument to probability must be a number between zero and one";
            return random() < p;
        }

        function randomIntBetween(start, end) {
            if (!isInteger(start) || !isInteger(end)) throw "Arguments to randomIntBetween must be integers";
            return truncate(random() * (end - start) + start);
        }

        function randomBigintBetween(start, end) {
            if (!isBigint(start) || !isBigint(end)) throw "Arguments to randomBigintBetween must be bigints";
            if (!isInteger(Number(start)) || !isInteger(Number(end))) throw "Arguments to randomBigintBetween must be representable as regular intergers";
            return makeBigInt(randomIntBetween(Number(start), Number(end)));
        }

        function randomIntBelow(n) {
            if (!isInteger(n)) throw "Argument to randomIntBelow must be an integer";
            return truncate(random() * n);
        }

        function randomElement(array) {
            return array[randomIntBelow(array.length)];
        }


        //
        // Input constructors.
        // The inputs for actions are encoded as objects that specify both the type and the value of the input:
        //  {argumentIndex: i}      Use the ith argument of the Explore operation (index 0 corresponds to the 2nd input of the Explore operation, the first input is the value to explore)
        //  {methodName: m}         Contains the method name as string for method calls. Always the first input.
        //  {propertyName: p}       Contains the property name as string for property operations. Always the first input.
        //  {elementIndex: i}       Contains the element index as integer for element operations. Always the first input.
        //  {intValue: v}
        //  {floatValue: v}
        //  {bigintValue: v}        As bigints are not encodable using JSON.stringify, they are stored as strings.
        //  {stringValue: v}
        //
        // These must be kept in sync with the Action.Input struct in the ExplorationMutator.
        //
        function ArgumentInput(idx) {
            this.argumentIndex = idx;
        }
        function MethodNameInput(name) {
            this.methodName = name;
        }
        function PropertyNameInput(name) {
            this.propertyName = name;
        }
        function ElementIndexInput(idx) {
            this.elementIndex = idx;
        }
        function IntInput(v) {
            if (!isInteger(v)) throw "IntInput value is not an integer: " + v;
            this.intValue = v;
        }
        function FloatInput(v) {
            if (!isNumber(v) || !isFinite(v)) throw "FloatInput value is not a (finite) number: " + v;
            this.floatValue = v;
        }
        function BigintInput(v) {
            if (!isBigint(v)) throw "BigintInput value is not a bigint: " + v;
            // Bigints can't be serialized by JSON.stringify, so store them as strings instead.
            this.bigintValue = bigintToString(v);
        }
        function StringInput(v) {
            if (!isString(v) || !isSimpleString(v)) throw "StringInput value is not a (simple) string: " + v;
            this.stringValue = v;
        }

        //
        // Access to random inputs.
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
            },

            // Returns a random property, element, or method on the given object or one of its prototypes.
            randomPropertyElementOrMethod(o) {
                // TODO: Add special handling for ArrayBuffers: most of the time, wrap these into a Uint8Array to be able to modify them.

                // Collect all properties, including those from prototypes, in this array.
                let properties = EmptyArray();

                // Give properties from prototypes a lower weight. Currently, the weight is halved for every new level of the prototype chain.
                let currentWeight = 1.0;
                let totalWeight = 0.0;
                function recordProperty(p) {
                    push(properties, {name: p, weight: currentWeight});
                    totalWeight += currentWeight;
                }

                // Iterate over the prototype chain and record all properties.
                let obj = o;
                while (obj !== null) {
                    // Special handling for array-like things: if the array is too large, skip this level and just include a couple random indices.
                    // We need to be careful when accessing the length though: for TypedArrays, the length property is defined on the prototype but
                    // must be accessed with the TypedArray as |this| value (not the prototype).
                    let maybeLength = tryGetProperty('length', obj);
                    if (isInteger(maybeLength) && maybeLength > 100) {
                        for (let i = 0; i < 10; i++) {
                            let randomElement = randomIntBelow(maybeLength);
                            recordProperty(randomElement);
                        }
                    } else {
                        // TODO do we want to also enumerate symbol properties here (using Object.getOwnPropertySymbols)? If we do, we should probable also add IL-level support for Symbols (i.e. a `LoadSymbol` instruction that ensures the symbol is in the global Symbol registry).
                        let allOwnPropertyNames = tryGetOwnPropertyNames(obj);
                        let allOwnElements = EmptyArray();
                        for (let i = 0; i < allOwnPropertyNames.length; i++) {
                            let p = allOwnPropertyNames[i];
                            let index = parseInteger(p);
                            // TODO should we allow negative indices here as well?
                            if (index >= 0 && index <= MAX_SAFE_INTEGER && numberToString(index) === p) {
                                push(allOwnElements, index);
                            } else if (isSimpleString(p) && tryAccessProperty(p, o)) {
                                // Only include properties with "simple" names and only if they can be accessed on the original object without raising an exception.
                                recordProperty(p);
                            }
                        }

                        // Limit array-like objects to at most 10 random elements.
                        for (let i = 0; i < 10 && allOwnElements.length > 0; i++) {
                            let index = randomIntBelow(allOwnElements.length);
                            recordProperty(allOwnElements[index]);
                            allOwnElements[index] = pop(allOwnElements);
                        }
                    }

                    obj = tryGetPrototypeOf(obj);
                    currentWeight /= 2.0;

                    // Greatly reduce the property weights for the Object.prototype. These methods are always available and we can use more targeted things like CodeGenerators to call them if we want to.
                    if (obj === ObjectPrototype) {
                      // Somewhat arbitrarily reduce the weight as if there were another 3 levels.
                      currentWeight /= 8.0;

                      // However, if we've reached the Object prototype without any other properties (i.e. are exploring an empty, plain object), then always abort, in which case we'll define a new property instead.
                      if (properties.length == 0) {
                        return null;
                      }
                    }
                }

                // Require at least 3 different properties to chose from.
                if (properties.length < 3) {
                    return null;
                }

                // Now choose a random property. If a property has weight 2W, it will be selected with twice the probability of a property with weight W.
                let p;
                let remainingWeight = random() * totalWeight;
                for (let i = 0; i < properties.length; i++) {
                    let candidate = properties[i];
                    remainingWeight -= candidate.weight;
                    if (remainingWeight < 0) {
                        p = candidate.name;
                        break;
                    }
                }

                // Sanity checking. This may fail for example if Proxies are involved. In that case, just fail here.
                if (!tryHasProperty(p, o)) return null;

                // Determine what type of property it is.
                if (isNumber(p)) {
                    return new ElementIndexInput(p);
                } else if (isFunction(tryGetProperty(p, o))) {
                    return new MethodNameInput(p);
                } else {
                    return new PropertyNameInput(p);
                }
            }
        }


        //
        // Explore implementation for different basic types.
        //
        // These all return an "action" object of the form {operation: SOME_OPERATION, inputs: array_of_inputs}. They may also return the special NO_ACTION value (null).
        //
        function Action(operation, inputs = EmptyArray()) {
            this.operation = operation;
            this.inputs = inputs;
        }

        // Heuristic to determine when a function should be invoked as a constructor.
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

        function exploreObject(o) {
            if (o === null) {
                // Can't do anything with null.
                return NO_ACTION;
            }

            // Determine a random property, which can generally either be a method, an element, or a "regular" property.
            let input = Inputs.randomPropertyElementOrMethod(o);

            // Determine the appropriate action to perform.
            // If the property lookup failed (for whatever reason), we always define a new property.
            if (input === null) {
                return new Action(OP_DEFINE_PROPERTY, [new PropertyNameInput(randomElement(customPropertyNames)), Inputs.randomArgument()]);
            } else if (input instanceof MethodNameInput) {
                let f = tryGetProperty(input.methodName, o);
                // More sanity checks. These may rarely fail e.g. due to non-deterministically behaving Proxies. In that case, just give up.
                if (!isFunction(f)) return NO_ACTION;
                let numParameters = tryGetProperty('length', f);
                if (!isInteger(numParameters) || numParameters > MAX_PARAMETERS || numParameters < 0) return NO_ACTION;
                // Small hack, generate n+1 input arguments, then replace index 0 with the method name input.
                let inputs = Inputs.randomArguments(numParameters + 1);
                inputs[0] = input;
                if (shouldTreatAsConstructor(f)) {
                  return new Action(OP_CONSTRUCT_MEMBER, inputs);
                } else {
                  return new Action(OP_CALL_METHOD, inputs);
                }
            } else if (input instanceof ElementIndexInput) {
                if (probability(0.5)) {
                    return new Action(OP_GET_ELEMENT, [input]);
                } else {
                    let newValue = Inputs.randomArgumentForReplacing(input.elementIndex, o);
                    return new Action(OP_SET_ELEMENT, [input, newValue]);
                }
            } else if (input instanceof PropertyNameInput) {
                // Besides getting and setting the property, we also sometimes define a new property instead.
                if (probability(1/3)) {
                    input.propertyName = randomElement(customPropertyNames);
                    return new Action(OP_SET_PROPERTY, [input, Inputs.randomArgument()]);
                } else if (probability(0.5)) {
                    return new Action(OP_GET_PROPERTY, [input]);
                } else {
                    let newValue = Inputs.randomArgumentForReplacing(input.propertyName, o);
                    return new Action(OP_SET_PROPERTY, [input, newValue]);
                }
            } else {
              throw "Got unexpected input " + input;
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
            let operation = shouldTreatAsConstructor(f) ? OP_CONSTRUCT : OP_CALL_FUNCTION;
            return new Action(operation, Inputs.randomArguments(numParameters));
        }

        function exploreString(s) {
            // Sometimes (rarely) compare the string against it's original value. Otherwise, treat the string as an object.
            if (probability(0.1) && isSimpleString(s)) {
                return new Action(OP_COMPARE_EQUAL, [new StringInput(s)]);
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
            return new Action(OP_SYMBOL_REGISTRATION);
        }

        const ALL_BOOLEAN_OPERATIONS = concat(BOOLEAN_BINARY_OPS, BOOLEAN_UNARY_OPS);
        function exploreBoolean(b) {
            let operation = randomElement(ALL_BOOLEAN_OPERATIONS);

            let action = new Action(operation);
            if (includes(BOOLEAN_BINARY_OPS, operation)) {
                // It probably doesn't make sense to hardcode boolean constants, so always use an existing argument.
                push(action.inputs, Inputs.randomArgument());
            }
            return action;
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
                // Can't do anything with undefined.
                return NO_ACTION;
            } else {
                throw "Unexpected value type: " + typeof v;
            }
        }

        //
        // Execution of actions determined through exploration.
        //
        // Handlers for all supported operations;
        const actionHandlers = {
          [OP_CALL_FUNCTION]: (v, inputs) => apply(v, currentThis, inputs),
          [OP_CONSTRUCT]: (v, inputs) => construct(v, inputs),
          [OP_CALL_METHOD]: (v, inputs) => { let m = shift(inputs); apply(v[m], v, inputs); },
          [OP_CONSTRUCT_MEMBER]: (v, inputs) => { let m = shift(inputs); construct(v[m], inputs); },
          [OP_GET_PROPERTY]: (v, inputs) => v[inputs[0]],
          [OP_SET_PROPERTY]: (v, inputs) => v[inputs[0]] = inputs[1],
          [OP_DEFINE_PROPERTY]: (v, inputs) => v[inputs[0]] = inputs[1],
          [OP_GET_ELEMENT]: (v, inputs) => v[inputs[0]],
          [OP_SET_ELEMENT]: (v, inputs) => v[inputs[0]] = inputs[1],
          [OP_ADD]: (v, inputs) => v + inputs[0],
          [OP_SUB]: (v, inputs) => v - inputs[0],
          [OP_MUL]: (v, inputs) => v * inputs[0],
          [OP_DIV]: (v, inputs) => v / inputs[0],
          [OP_MOD]: (v, inputs) => v % inputs[0],
          [OP_INC]: (v, inputs) => v++,
          [OP_DEC]: (v, inputs) => v--,
          [OP_NEG]: (v, inputs) => -v,
          [OP_LOGICAL_AND]: (v, inputs) => v && inputs[0],
          [OP_LOGICAL_OR]: (v, inputs) => v || inputs[0],
          [OP_LOGICAL_NOT]: (v, inputs) => !v,
          [OP_BITWISE_AND]: (v, inputs) => v & inputs[0],
          [OP_BITWISE_OR]: (v, inputs) => v | inputs[0],
          [OP_BITWISE_XOR]: (v, inputs) => v ^ inputs[0],
          [OP_LEFT_SHIFT]: (v, inputs) => v << inputs[0],
          [OP_SIGNED_RIGHT_SHIFT]: (v, inputs) => v >> inputs[0],
          [OP_UNSIGNED_RIGHT_SHIFT]: (v, inputs) => v >>> inputs[0],
          [OP_BITWISE_NOT]: (v, inputs) => ~v,
          [OP_COMPARE_EQUAL]: (v, inputs) => v == inputs[0],
          [OP_COMPARE_STRICT_EQUAL]: (v, inputs) => v === inputs[0],
          [OP_COMPARE_NOT_EQUAL]: (v, inputs) => v != inputs[0],
          [OP_COMPARE_STRICT_NOT_EQUAL]: (v, inputs) => v !== inputs[0],
          [OP_COMPARE_GREATER_THAN]: (v, inputs) => v > inputs[0],
          [OP_COMPARE_LESS_THAN]: (v, inputs) => v < inputs[0],
          [OP_COMPARE_GREATER_THAN_OR_EQUAL]: (v, inputs) => v >= inputs[0],
          [OP_COMPARE_LESS_THAN_OR_EQUAL]: (v, inputs) => v <= inputs[0],
          [OP_TEST_IS_NAN]: (v, inputs) => Number.isNaN(v),
          [OP_TEST_IS_FINITE]: (v, inputs) => Number.isFinite(v),
          [OP_SYMBOL_REGISTRATION]: (v, inputs) => Symbol.for(v.description),
        };

        // Performs the given action on the given value. Returns true on success, false otherwise.
        function perform(v, action) {
            if (action === NO_ACTION) {
                return true;
            }

            // Compute the concrete inputs: the actual runtime values of all inputs.
            let concreteInputs = EmptyArray();
            for (let i = 0; i < action.inputs.length; i++) {
                let input = action.inputs[i];
                if (input instanceof ArgumentInput) {
                    push(concreteInputs, exploreArguments[input.argumentIndex]);
                } else if (input instanceof BigintInput) {
                    // These need special handling because BigInts cannot be serialized into JSON, so are stored as strings.
                    push(concreteInputs, makeBigInt(input.bigintValue));
                } else {
                    let value = propertyValues(input)[0];
                    if (isUndefined(value)) throw "Unexpectedly obtained 'undefined' as concrete input";
                    push(concreteInputs, value);
                }
            }

            let handler = actionHandlers[action.operation];
            if (isUndefined(handler)) throw "Unhandled operation " + action.operation;

            try {
                handler(v, concreteInputs);
            } catch (e) {
                return false;
            }

            return true;
        }

        //
        // Exploration entrypoint.
        //
        function explore(id, v, thisValue, args) {
            // The given arguments may be used as inputs for the action.
            if (isUndefined(args) || args.length < 1) throw "Exploration requires at least one additional argument";
            exploreArguments = args;
            currentThis = thisValue;

            // We may get here recursively for example if a Proxy is being explored which triggers further explore calls during e.g. property enumeration.
            // Probably the best way to deal with these cases is to just bail out from recursive explorations.
            if (currentlyExploring) return;
            currentlyExploring = true;

            // Check if we already have a result for this id, and if so repeat the same action again. Otherwise, explore.
            let action;
            if (hasActionFor(id)) {
                action = getActionFor(id);
            } else {
                action = exploreValue(id, v);
                recordAction(id, action);
            }

            // Now perform the selected action on the value.
            let success = perform(v, action);

            // If the action failed, mark this explore operation as failing so it won't be retried.
            if (!success) {
                recordFailure(id);
            }

            currentlyExploring = false;
        }

        function exploreWithErrorHandling(id, v, thisValue, args) {
            try {
                explore(id, v, thisValue, args);
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
