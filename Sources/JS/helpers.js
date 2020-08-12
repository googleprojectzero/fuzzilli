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
var maxCollectedProperties = 200
var maxArrayLength = 1000
var groups = {
    symbol: {name: "Symbol", belongsToGroup: function(obj){return typeof obj === 'symbol'}},
    string: {name: "String", belongsToGroup: function(obj){return obj instanceof String}},
    regexp: {name: "RegExp", belongsToGroup: function(obj){return obj instanceof RegExp}},
    array: {name: "Array", belongsToGroup: function(obj){return obj instanceof Array}},
    map: {name: "Map", belongsToGroup: function(obj){return obj instanceof Map}},
    promise: {name: "Promise", belongsToGroup: function(obj){return obj instanceof Promise}},
    weakMap: {name: "WeakMap", belongsToGroup: function(obj){return obj instanceof WeakMap}},
    set: {name: "Set", belongsToGroup: function(obj){return obj instanceof Set}},
    weakSet: {name: "WeakSet", belongsToGroup: function(obj){return obj instanceof WeakSet}},
    arrayBuffer: {name: "ArrayBuffer", belongsToGroup: function(obj){return obj instanceof ArrayBuffer}},
    dataView: {name: "DataView", belongsToGroup: function(obj){return obj instanceof DataView}},
    uint8Array: {name: "Uint8Array", belongsToGroup: function(obj){return obj instanceof Uint8Array}, slowTypeCollection: true},
    int8Array: {name: "Int8Array", belongsToGroup: function(obj){return obj instanceof Int8Array}, slowTypeCollection: true},
    uint16Array: {name: "Uint16Array", belongsToGroup: function(obj){return obj instanceof Uint16Array}, slowTypeCollection: true},
    int16Array: {name: "Int16Array", belongsToGroup: function(obj){return obj instanceof Int16Array}, slowTypeCollection: true},
    uint32Array: {name: "Uint32Array", belongsToGroup: function(obj){return obj instanceof Uint32Array}, slowTypeCollection: true},
    int32Array: {name: "Int32Array", belongsToGroup: function(obj){return obj instanceof Int32Array}, slowTypeCollection: true},
    float32Array: {name: "Float32Array", belongsToGroup: function(obj){return obj instanceof Float32Array}, slowTypeCollection: true},
    float64Array: {name: "Float64Array", belongsToGroup: function(obj){return obj instanceof Float64Array}, slowTypeCollection: true},
    uint8ClampedArray: {name: "Uint8ClampedArray", belongsToGroup: function(obj){return obj instanceof Uint8ClampedArray}, slowTypeCollection: true},
    object: {name: "Object", belongsToGroup: function(obj){return obj instanceof Object}}
}
// Note that order of the groups is important because we assign object to the first matching group.
// For example Object is group containing other groups, so it should be placed at the end
var orderedGroups = [
    groups.symbol, groups.string, groups.regexp, groups.array, groups.map, groups.promise, groups.weakMap, groups.set,
    groups.weakSet, groups.arrayBuffer, groups.dataView, groups.uint8Array, groups.int8Array, groups.uint16Array,
    groups.int16Array, groups.uint32Array, groups.int32Array, groups.float32Array, groups.float64Array,
    groups.uint8ClampedArray, groups.object,
]
// Must be kept in sync with TypeSystem.swift
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
// Back up important functions needed to type collection
var isInteger = Number.isInteger
var getObjectPropertyNames = Object.getOwnPropertyNames
var getObjectKeys = Object.keys
var mathMin = Math.min
var jsonStringify = JSON.stringify
// Check if we can use property name in form obj.prop
// http://www.ecma-international.org/ecma-262/6.0/#sec-names-and-keywords
function isValidPropName(name) {
    return /^[a-zA-Z_$][0-9a-zA-Z_$]*$/.test(name)
}
function arrayIntersection(a1, a2) {
    if (a1 == null || a2 == null) return null
    return a1.filter(function(x) {
        return a2.indexOf(x) !== -1
    })
}