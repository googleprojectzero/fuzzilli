// DO NOT EDIT!
// Generated by generateSwift.sh
// Copyright 2020 Google LLC
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
public let helpersScript = """
var maxCollectedProperties = 200
var possibleGroups = [
    {name: "Symbol", belongsToGroup: function(obj){typeof obj == 'symbol'}},
    {name: "String", belongsToGroup: function(obj){return obj instanceof String}},
    {name: "RegExp", belongsToGroup: function(obj){return obj instanceof RegExp}},
    {name: "Array", belongsToGroup: function(obj){return obj instanceof Array}},
    {name: "Map", belongsToGroup: function(obj){return obj instanceof Map}},
    {name: "Promise", belongsToGroup: function(obj){return obj instanceof Promise}},
    {name: "WeakMap", belongsToGroup: function(obj){return obj instanceof WeakMap}},
    {name: "Set", belongsToGroup: function(obj){return obj instanceof Set}},
    {name: "WeakSet", belongsToGroup: function(obj){return obj instanceof WeakSet}},
    {name: "ArrayBuffer", belongsToGroup: function(obj){return obj instanceof ArrayBuffer}},
    {name: "DataView", belongsToGroup: function(obj){return obj instanceof DataView}},
    {name: "Uint8Array", belongsToGroup: function(obj){return obj instanceof Uint8Array}},
    {name: "Int8Array", belongsToGroup: function(obj){return obj instanceof Int8Array}},
    {name: "Uint16Array", belongsToGroup: function(obj){return obj instanceof Uint16Array}},
    {name: "Int16Array", belongsToGroup: function(obj){return obj instanceof Int16Array}},
    {name: "Uint32Array", belongsToGroup: function(obj){return obj instanceof Uint32Array}},
    {name: "Int32Array", belongsToGroup: function(obj){return obj instanceof Int32Array}},
    {name: "Float32Array", belongsToGroup: function(obj){return obj instanceof Float32Array}},
    {name: "Float64Array", belongsToGroup: function(obj){return obj instanceof Float64Array}},
    {name: "Uint8ClampedArray", belongsToGroup: function(obj){return obj instanceof String}},
    {name: "Object", belongsToGroup: function(obj){return obj instanceof Object}},
]
var baseTypes = {
    nothing: 0,
    undefined: 1 << 0,
    integer: 1 << 1,
    float: 1 << 2,
    string: 1 << 3,
    boolean: 1 << 4,
    object: 1 << 5,
    function: 1 << 6,
    constructor: 1 << 7,
    unknown: 1 << 8,
    bigint: 1 << 9,
    regexp: 1 << 10,
}
var isInteger = Number.isInteger
var getObjectPropertyNames = Object.getOwnPropertyNames
function isValidPropName(name) {
    return /^[a-zA-Z_$][0-9a-zA-Z_$]*$/.test(name)
}
function arrayIntersection(a1, a2) {
    if (a1 == null || a2 == null) return null
    return a1.filter(function(x) {
        return a2.indexOf(x) !== -1
    })
}
"""
