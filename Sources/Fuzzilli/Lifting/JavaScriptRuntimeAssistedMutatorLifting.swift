// Copyright 2023 Google LLC
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

/// This file contains the JavaScript specific implementation of common runtime-assisted logic, such as the JS
struct JavaScriptRuntimeAssistedMutatorLifting {
    static let commonCode = """
        // Note: runtime instrumentation code must generally assume that any operation performed on any object coming from the "outside", may raise an exception, for example due to triggering a Proxy trap.
        // Further, it must also assume that the environment has been modified arbitrarily. For example, the Array.prototype[@@iterator] may have been set to an invalid value, so using `for...of` syntax could trigger an exception.

        // Load all necessary routines and objects into local variables as they may be overwritten by the program.
        // We generally want to avoid triggerring observable side-effects, such as storing or loading
        // properties. For that reason, we prefer to use builtins like Object.defineProperty.

        const ProxyConstructor = Proxy;
        const BigIntConstructor = BigInt;
        const SetConstructor = Set;

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
        const truncate = Math.trunc;
        const apply = Reflect.apply;
        const construct = Reflect.construct;
        const ReflectGet = Reflect.get;
        const ReflectSet = Reflect.set;
        const ReflectHas = Reflect.has;

        // Bind methods to local variables. These all expect the 'this' object as first parameter.
        const concat = Function.prototype.call.bind(Array.prototype.concat);
        const findIndex = Function.prototype.call.bind(Array.prototype.findIndex);
        const includes = Function.prototype.call.bind(Array.prototype.includes);
        const shift = Function.prototype.call.bind(Array.prototype.shift);
        const pop = Function.prototype.call.bind(Array.prototype.pop);
        const push = Function.prototype.call.bind(Array.prototype.push);
        const filter = Function.prototype.call.bind(Array.prototype.filter);
        const execRegExp = Function.prototype.call.bind(RegExp.prototype.exec);
        const stringSlice = Function.prototype.call.bind(String.prototype.slice);
        const toUpperCase = Function.prototype.call.bind(String.prototype.toUpperCase);
        const numberToString = Function.prototype.call.bind(Number.prototype.toString);
        const bigintToString = Function.prototype.call.bind(BigInt.prototype.toString);
        const stringStartsWith = Function.prototype.call.bind(String.prototype.startsWith);
        const setAdd = Function.prototype.call.bind(Set.prototype.add);
        const setHas = Function.prototype.call.bind(Set.prototype.has);

        const MIN_SAFE_INTEGER = Number.MIN_SAFE_INTEGER;
        const MAX_SAFE_INTEGER = Number.MAX_SAFE_INTEGER;

        // Simple, seedable PRNG based on a LCG.
        class RNG {
            m = 2 ** 32;
            a = 1664525;
            c = 1013904223;
            x;

            constructor(seed) {
                this.x = seed;
            }
            randomInt() {
                this.x = (this.x * this.a + this.c) % this.m;
                if (!isInteger(this.x)) throw "RNG state is not an Integer!"
                return this.x;
            }
            randomFloat() {
                return this.randomInt() / this.m;
            }
            probability(p) {
                return this.randomFloat() < p;
            }
            reseed(seed) {
                this.x = seed;
            }
        }

        // When creating empty arrays to which elements are later added, use a custom array type that has a null prototype. This way, the arrays are not
        // affected by changes to the Array.prototype that could interfere with array builtins (e.g. indexed setters or a modified .constructor property).
        function EmptyArray() {
            let array = [];
            setPrototypeOf(array, null);
            return array;
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
        const simpleStringRegExp = /^[0-9a-zA-Z_$]+$/;
        function isSimpleString(s) {
            if (!isString(s)) throw "Non-string argument to isSimpleString: " + s;
            return s.length < 50 && execRegExp(simpleStringRegExp, s) !== null;
        }

        // Helper function to determine if a string is numeric and its numeric value representable as an integer.
        function isNumericString(s) {
            if (!isString(s)) return false;
            let number = parseInteger(s);
            return number >= MIN_SAFE_INTEGER && number <= MAX_SAFE_INTEGER && numberToString(number) === s;
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

        // Initially the rng is seeded randomly, specific mutators can reseed() the rng if they need deterministic behavior.
        // See the explore operation in JsOperations.swift for an example.
        let rng = new RNG(truncate(Math.random() * 2**32));

        function probability(p) {
            if (p < 0 || p > 1) throw "Argument to probability must be a number between zero and one";
            return rng.probability(p);
        }

        function randomIntBetween(start, end) {
            if (!isInteger(start) || !isInteger(end)) throw "Arguments to randomIntBetween must be integers";
            return (rng.randomInt() % (end - start)) + start;
        }

        function randomFloat() {
            return rng.randomFloat();
        }

        function randomBigintBetween(start, end) {
            if (!isBigint(start) || !isBigint(end)) throw "Arguments to randomBigintBetween must be bigints";
            if (!isInteger(Number(start)) || !isInteger(Number(end))) throw "Arguments to randomBigintBetween must be representable as regular intergers";
            return BigIntConstructor(randomIntBetween(Number(start), Number(end)));
        }

        function randomIntBelow(n) {
            if (!isInteger(n)) throw "Argument to randomIntBelow must be an integer";
            return rng.randomInt() % n;
        }

        function randomElement(array) {
            return array[randomIntBelow(array.length)];
        }
    """

    static let introspectionCode = """
        // Note: this code assumes that the common code from above has been included before.

        //
        // Object introspection.
        //

        //
        // Enumerate all properties on the given object and its prototypes.
        //
        // These include elements and methods (callable properties). Each property is assigned a "weight" which expresses roughly how "important"/"interesting" a property is:
        // a property that exists on a prototype is considered less interesting as it can probably be reached through other objects as well, so we prefer properties closer to the start object.
        //
        // The result is returned in an array like the following:
        // [
        //   length: <total number of properties>
        //   totalWeight: <combined weight of all properties>
        //   0, 1, ..., length - 1: { name: <property name/index>, weight: <weight as number> }
        // ]
        function enumeratePropertiesOf(o) {
            // Collect all properties, including those from prototypes, in this array.
            let properties = EmptyArray();

            // Give properties from prototypes a lower weight. Currently, the weight is halved for every new level of the prototype chain.
            let currentWeight = 1.0;
            properties.totalWeight = 0.0;
            function recordProperty(p) {
                push(properties, {name: p, weight: currentWeight});
                properties.totalWeight += currentWeight;
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

                // Greatly reduce the property weights for the Object.prototype. These methods are always available and we can use more targeted mechanisms like CodeGenerators to call them if we want to.
                if (obj === ObjectPrototype) {
                    // Somewhat arbitrarily reduce the weight as if there were another 3 levels.
                    currentWeight /= 8.0;

                    // However, if we've reached the Object prototype without any other properties (i.e. are inspecting an empty, plain object), then always return an empty list since these properties are not very intersting.
                    if (properties.length == 0) {
                        return properties;
                    }
                }
            }

            return properties;
        }

        //
        // Returns a random property available on the given object or one of its prototypes.
        //
        // This will return more "interesting" properties with a higher probability. In general, properties closer to the start object
        // are preferred over properties on prototypes (as these are likely shared with other objects).
        //
        // If no (interesting) property exists, null is returned. Otherwise, the key of the property is returned.
        function randomPropertyOf(o) {
            let properties = enumeratePropertiesOf(o);

            // We need at least one property to chose from.
            if (properties.length === 0) {
                return null;
            }

            // Now choose a random property. If a property has weight 2W, it will be selected with twice the probability of a property with weight W.
            let selectedProperty;
            let remainingWeight = randomFloat() * properties.totalWeight;
            for (let i = 0; i < properties.length; i++) {
                let candidate = properties[i];
                remainingWeight -= candidate.weight;
                if (remainingWeight < 0) {
                    selectedProperty = candidate.name;
                    break;
                }
            }

            // Sanity checking. This may fail for example if Proxies are involved. In that case, just fail here.
            if (!tryHasProperty(selectedProperty, o)) return null;

            return selectedProperty;
        }
    """

    static let actionCode = """
        // Note: this code assumes that the common code from above has been included before.

        //
        // List of all supported operations. Must be kept in sync with the ActionOperation enum.
        //
        const OP_CALL_FUNCTION = 'CALL_FUNCTION';
        const OP_CONSTRUCT = 'CONSTRUCT';
        const OP_CALL_METHOD = 'CALL_METHOD';
        const OP_CONSTRUCT_METHOD = 'CONSTRUCT_METHOD';
        const OP_GET_PROPERTY = 'GET_PROPERTY';
        const OP_SET_PROPERTY = 'SET_PROPERTY';
        const OP_DELETE_PROPERTY = 'DELETE_PROPERTY';

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
        const OP_NULL_COALESCE = 'NULL_COALESCE';

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

        //
        // Action constructors.
        //
        function Action(operation, inputs = EmptyArray()) {
            this.operation = operation;
            this.inputs = inputs;
            this.isGuarded = false;
        }

        // A guarded action is an action that is allowed to raise an exception.
        //
        // These are for example used for by the ExplorationMutator for function/method call
        // which may throw an exception if they aren't given the right arguments. In that case,
        // we may still want to keep the function call so that it can be mutated further to
        // hopefully eventually find the correct arguments. This is especially true if finding
        // the right arguments reqires the ProbingMutator to install the right properties on an
        // argument object, in which case the ExplorationMutator on its own would (likely) never
        // be able to generate a valid call, and so the function/method may be missed entirely.
        //
        // If a guarded action succeeds (doesn't raise an exception), it will be converted to
        // a regular action to limit the number of generated try-catch blocks.
        function GuardedAction(operation, inputs = EmptyArray()) {
            this.operation = operation;
            this.inputs = inputs;
            this.isGuarded = true;
        }

        // Special value to indicate that no action should be performed.
        const NO_ACTION = null;

        //
        // Action Input constructors.
        //
        // The inputs for actions are encoded as objects that specify both the type and the value of the input. They are basically enum values with associated values.
        // These must be kept compatible with the Action.Input enum in RuntimeAssistedMutator.swift as they have to be encodable to/decodable from that enum.
        //
        function ArgumentInput(index) {
            if (!isInteger(index)) throw "ArgumentInput index is not an integer: " + index;
            return { argument: { index } };
        }
        function SpecialInput(name) {
            if (!isString(name) || !isSimpleString(name)) throw "SpecialInput name is not a (simple) string: " + name;
            return { special: { name } };
        }
        function IntInput(value) {
            if (!isInteger(value)) throw "IntInput value is not an integer: " + value;
            return { int: { value } };
        }
        function FloatInput(value) {
            if (!isNumber(value) || !isFinite(value)) throw "FloatInput value is not a (finite) number: " + value;
            return { float: { value } };
        }
        function BigintInput(value) {
            if (!isBigint(value)) throw "BigintInput value is not a bigint: " + value;
            // Bigints can't be serialized by JSON.stringify, so store them as strings instead.
            return { bigint: { value: bigintToString(value) } };
        }
        function StringInput(value) {
            if (!isString(value) || !isSimpleString(value)) throw "StringInput value is not a (simple) string: " + value;
            return { string: { value } };
        }

        // Type checkers for Input objects. We use these instead of for example 'instanceof' since we allow Input
        // objects to be decoded from JSON, in which case they will not have the right .constructor property.
        function isArgumentInput(input) { return hasOwnProperty(input, 'argument'); }
        function isSpecialInput(input) { return hasOwnProperty(input, 'special'); }
        function isIntInput(input) { return hasOwnProperty(input, 'int'); }
        function isFloatInput(input) { return hasOwnProperty(input, 'float'); }
        function isBigintInput(input) { return hasOwnProperty(input, 'bigint'); }
        function isStringInput(input) { return hasOwnProperty(input, 'string'); }

        // Helper routines to extract the associated values from Input objects.
        function getArgumentInputIndex(input) { return input.argument.index; }
        function getSpecialInputName(input) { return input.special.name; }
        function getIntInputValue(input) { return input.int.value; }
        function getFloatInputValue(input) { return input.float.value; }
        function getBigintInputValue(input) { return BigIntConstructor(input.bigint.value); }
        function getStringInputValue(input) { return input.string.value; }

        // Handlers for executing actions.
        // These will receive the array of concrete inputs (i.e. JavaScript values) as first parameter and the current value of |this| as second parameter (which can be ignored if not needed).
        const ACTION_HANDLERS = {
          [OP_CALL_FUNCTION]: (inputs, currentThis) => { let f = shift(inputs); return apply(f, currentThis, inputs); },
          [OP_CONSTRUCT]: (inputs) => { let c = shift(inputs); return construct(c, inputs); },
          [OP_CALL_METHOD]: (inputs) => { let o = shift(inputs); let m = shift(inputs); return apply(o[m], o, inputs); },
          [OP_CONSTRUCT_METHOD]: (v, inputs) => { let o = shift(inputs); let m = shift(inputs); return construct(o[m], inputs); },
          [OP_GET_PROPERTY]: (inputs) => { let o = inputs[0]; let p = inputs[1]; return o[p]; },
          [OP_SET_PROPERTY]: (inputs) => { let o = inputs[0]; let p = inputs[1]; let v = inputs[2]; o[p] = v; },
          [OP_DELETE_PROPERTY]: (inputs) => { let o = inputs[0]; let p = inputs[1]; return delete o[p]; },
          [OP_ADD]: (inputs) => inputs[0] + inputs[1],
          [OP_SUB]: (inputs) => inputs[0] - inputs[1],
          [OP_MUL]: (inputs) => inputs[0] * inputs[1],
          [OP_DIV]: (inputs) => inputs[0] / inputs[1],
          [OP_MOD]: (inputs) => inputs[0] % inputs[1],
          [OP_INC]: (inputs) => inputs[0]++,
          [OP_DEC]: (inputs) => inputs[0]--,
          [OP_NEG]: (inputs) => -inputs[0],
          [OP_LOGICAL_AND]: (inputs) => inputs[0] && inputs[1],
          [OP_LOGICAL_OR]: (inputs) => inputs[0] || inputs[1],
          [OP_LOGICAL_NOT]: (inputs) => !inputs[0],
          [OP_NULL_COALESCE]: (inputs) => inputs[0] ?? inputs[1],
          [OP_BITWISE_AND]: (inputs) => inputs[0] & inputs[1],
          [OP_BITWISE_OR]: (inputs) => inputs[0] | inputs[1],
          [OP_BITWISE_XOR]: (inputs) => inputs[0] ^ inputs[1],
          [OP_LEFT_SHIFT]: (inputs) => inputs[0] << inputs[1],
          [OP_SIGNED_RIGHT_SHIFT]: (inputs) => inputs[0] >> inputs[1],
          [OP_UNSIGNED_RIGHT_SHIFT]: (inputs) => inputs[0] >>> inputs[1],
          [OP_BITWISE_NOT]: (inputs) => ~inputs[0],
          [OP_COMPARE_EQUAL]: (inputs) => inputs[0] == inputs[1],
          [OP_COMPARE_STRICT_EQUAL]: (inputs) => inputs[0] === inputs[1],
          [OP_COMPARE_NOT_EQUAL]: (inputs) => inputs[0] != inputs[1],
          [OP_COMPARE_STRICT_NOT_EQUAL]: (inputs) => inputs[0] !== inputs[1],
          [OP_COMPARE_GREATER_THAN]: (inputs) => inputs[0] > inputs[1],
          [OP_COMPARE_LESS_THAN]: (inputs) => inputs[0] < inputs[1],
          [OP_COMPARE_GREATER_THAN_OR_EQUAL]: (inputs) => inputs[0] >= inputs[1],
          [OP_COMPARE_LESS_THAN_OR_EQUAL]: (inputs) => inputs[0] <= inputs[1],
          [OP_TEST_IS_NAN]: (inputs) => Number.isNaN(inputs[0]),
          [OP_TEST_IS_FINITE]: (inputs) => Number.isFinite(inputs[0]),
          [OP_SYMBOL_REGISTRATION]: (inputs) => Symbol.for(inputs[0].description),
        };

        // Executes the given action.
        //
        // This will convert the inputs to concrete JavaScript values, then execute the operation with these inputs.
        // Executing an action may change its guarding state: if a guarded action executes without raising an exception,
        // it will be converted to an unguarded operation (as the guarding apears to not be needed). This way, we will
        // ultimately end up emitting fewer try-catch (or equivalent) constructs in the final JavaScript code generated
        // from these actions.
        //
        // Returns true if either the action succeeded without raising an exception or if the action is guarded, false otherwise.
        // The output of the action is stored in |context.output| upon successful execution.
        function execute(action, context) {
            if (action === NO_ACTION) {
                return true;
            }

            // Convert the action's inputs to the concrete JS values to use for executing the action.
            let concreteInputs = EmptyArray();
            for (let i = 0; i < action.inputs.length; i++) {
                let input = action.inputs[i];
                if (isArgumentInput(input)) {
                    let index = getArgumentInputIndex(input);
                    if (index >= context.arguments.length) throw "Invalid argument index: " + index;
                    push(concreteInputs, context.arguments[index]);
                } else if (isSpecialInput(input)) {
                    let name = getSpecialInputName(input);
                    if (!hasOwnProperty(context.specialValues, name)) throw "Unknown special value: " + name;
                    push(concreteInputs, context.specialValues[name]);
                } else if (isIntInput(input)) {
                    push(concreteInputs, getIntInputValue(input));
                } else if (isFloatInput(input)) {
                    push(concreteInputs, getFloatInputValue(input));
                } else if (isBigintInput(input)) {
                    // These need special handling because BigInts cannot be serialized into JSON, so are stored as strings.
                    push(concreteInputs, getBigintInputValue(input));
                } else if (isStringInput(input)) {
                    push(concreteInputs, getStringInputValue(input));
                } else {
                    throw "Unknown action input: " + stringify(input);
                }
            }

            let handler = ACTION_HANDLERS[action.operation];
            if (isUndefined(handler)) throw "Unhandled operation " + action.operation;

            try {
                context.output = handler(concreteInputs, context.currentThis);
                // If the action succeeded, mark it as non-guarded so that we don't emit try-catch blocks for it later on.
                // We could alternatively only do that if all executions succeeded, but it's probably fine to do it if at least one execution succeeded.
                if (action.isGuarded) action.isGuarded = false;
            } catch (e) {
                return action.isGuarded;
            }

            return true;
        }
    """

}
