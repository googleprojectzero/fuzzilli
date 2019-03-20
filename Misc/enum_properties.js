// Copyright 2019 Google LLC
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

//
// Enumerate and print the names of properties and methods on the builtin objects.
///

var builtins = ["Object", "Function", "Array", "Number", "Boolean", "String", "Symbol", /*"Date",*/ "Promise", "RegExp", "Error", "ArrayBuffer", "Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "DataView", "Map", "Set", "WeakMap", "WeakSet", "Proxy", "Reflect", /*"JSON",*/ "Math", /*"escape", "unescape",*/]

var allPropertyNames = "";
var allMethodNames = "";
var propertyNames = new Set();
var methodNames = new Set();

function enumerate(obj, name, followPrototypeChain) {
    allMethodNames += `/* ${name} */ `
    allPropertyNames += `/* ${name} */ `
    while (obj !== null) {
        for (p of Object.getOwnPropertyNames(obj)) {
            var prop;
            try {
                prop = obj[p];
            } catch (e) { continue; }
            if (typeof(prop) === 'function' && !methodNames.has(p)) {
                allMethodNames += '"' + p + '", ';
                methodNames.add(p);
            }
            // Every method is also a property
            if (!propertyNames.has(p)) {
                allPropertyNames += '"' + p + '", ';
                propertyNames.add(p);
            }
        }

        if (!followPrototypeChain)
            break;

        obj = Object.getPrototypeOf(obj);
    }
}


// Properties of the builtins
for (name of builtins) {
    var builtin = this[name];
    enumerate(builtin, name);
}

// Properties of the builtin prototypes
for (name of builtins) {
    var builtin = this[name];
    if (!builtin.hasOwnProperty('prototype'))
        continue

    enumerate(builtin.prototype, name + '.prototype', true);
}

print(allPropertyNames);
print(allMethodNames);
