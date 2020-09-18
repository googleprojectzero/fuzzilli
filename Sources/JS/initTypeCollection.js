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

// Type object must be kept in sync with the Type protobuf message.
function Type(rawValue) {
    this.definiteType = rawValue
    this.possibleType = rawValue
    this.extension = {}
}
Type.prototype.mergeBaseType = function(otherType) {
    this.definiteType |= otherType
    this.possibleType |= otherType
}
Type.prototype.union = function(otherType) {
    var newType = new Type(baseTypes.nothing)
    newType.definiteType = this.definiteType & otherType.definiteType
    newType.possibleType = this.possibleType | otherType.possibleType

    if (this.extension.group === otherType.extension.group) newType.extension.group = this.extension.group
    newType.extension.properties = arrayIntersection(this.extension.properties, otherType.extension.properties)
    newType.extension.methods = arrayIntersection(this.extension.methods, otherType.extension.methods)

    return newType
}
Type.prototype.setGroup = function(obj) {
    for (var i=0;i<orderedGroups.length;i++) {
        try {
            if (orderedGroups[i].belongsToGroup(obj)) {
                this.extension.group = orderedGroups[i].name
                if (orderedGroups[i].iterable) this.mergeBaseType(baseTypes.iterable)
                return orderedGroups[i]
            }
        } catch(err) {}
    }
}
Type.prototype.collectProps = function(obj) {
    this.extension.methods = []
    this.extension.properties = []
    while (obj != null) {
        var propertyNames = getObjectPropertyNames(obj)
        for (var i=0;i<propertyNames.length;i++) {
            var name = propertyNames[i]
            if (this.extension.properties.length >= maxCollectedProperties) break
            if (!isValidPropName(name)) continue
            try {
                if (typeof obj[name] === 'function') {
                    this.extension.methods.push(name)
                    continue
                }
            } catch (err) { continue }

            this.extension.properties.push(name)
        }
        obj = obj.__proto__
    }
}

// variableNumber: {instructionNumber: Type}
var types = {}
function getCurrentType(value){
    try {
        // Fuzzilli handles both null/undefined as undefined
        if (value == null) return new Type(baseTypes.undefined)
        try {
            if (isInteger(value)) return new Type(baseTypes.integer)
        } catch(err) {}
        if (typeof value === 'number') return new Type(baseTypes.float)
        if (typeof value === 'string') {
            var currentType = new Type(baseTypes.string + baseTypes.object + baseTypes.iterable)
            currentType.extension.group = groups.string.name
            currentType.collectProps(value)
            return currentType
        }
        if (typeof value === 'boolean') return new Type(baseTypes.boolean)
        if (typeof value === 'bigint') return new Type(baseTypes.bigint)
        try {
            if (value instanceof RegExp) {
                var currentType = new Type(baseTypes.regexp + baseTypes.object)
                currentType.extension.group = groups.regexp.name
                currentType.collectProps(value)
                return currentType
            }
        } catch(err) {}
        if (typeof value === 'object' || typeof value === 'symbol') {
            var currentType = new Type(baseTypes.object)
            var group = currentType.setGroup(value)
            // handle long arrays specially to reduce time spent on properties collection
            if (group && group.slowTypeCollection && value.length > maxArrayLength) {
                currentType.extension.properties.push('length')
                value = value.__proto__
            }
            currentType.collectProps(value)
            return currentType
        }
    } catch(err) {}

    // Set unknown if no type was matched or error occurred
    return new Type(baseTypes.unknown)
}
function updateType(varNumber, instrIndex, value) {
    var currentType = getCurrentType(value)

    // Initialize structure for this variable if it is not already
    if (types[varNumber] == null) types[varNumber] = {}

    if (types[varNumber][instrIndex] == null) types[varNumber][instrIndex] = currentType
    else types[varNumber][instrIndex] = types[varNumber][instrIndex].union(currentType)
}
