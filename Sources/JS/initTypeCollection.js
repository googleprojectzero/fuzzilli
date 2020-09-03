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
function Type(rawValue) {
    if(rawValue == null) return
    this.definiteType = rawValue
    this.possibleType = rawValue
}
Type.prototype.mergeBaseType = function(otherType) {
    this.definiteType |= otherType
    this.possibleType |= otherType
}
Type.prototype.union = function(otherType) {
    var newType = new Type()
    newType.definiteType = this.definiteType & otherType.definiteType
    newType.possibleType = this.possibleType | otherType.possibleType

    if (this.group === otherType.group) newType.group = this.group
    newType.properties = arrayIntersection(this.properties, otherType.properties)
    newType.methods = arrayIntersection(this.methods, otherType.methods)

    return newType
}
Type.prototype.setGroup = function(obj) {
    for (var i=0;i<orderedGroups.length;i++) {
        try {
            if (orderedGroups[i].belongsToGroup(obj)) {
                this.group = orderedGroups[i].name
                if (orderedGroups[i].iterable) this.mergeBaseType(baseTypes.iterable)
                return orderedGroups[i]
            }
        } catch(err) {}
    }
}
Type.prototype.collectProps = function(obj) {
    this.methods = []
    this.properties = []
    while (obj != null) {
        var propertyNames = getObjectPropertyNames(obj)
        for (var i=0;i<propertyNames.length;i++) {
            var name = propertyNames[i]
            if (this.properties.length >= maxCollectedProperties) break
            if (!isValidPropName(name)) continue
            try {
                if (typeof obj[name] === 'function') {
                    this.methods.push(name)
                    continue
                }
            } catch (err) { continue }

            this.properties.push(name)
        }
        obj = obj.__proto__
    }
}

// variableNumber: Type
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
            currentType.group = groups.string.name
            currentType.collectProps(value)
            return currentType
        }
        if (typeof value === 'boolean') return new Type(baseTypes.boolean)
        if (typeof value === 'bigint') return new Type(baseTypes.bigint)
        try {
            if (value instanceof RegExp) {
                var currentType = new Type(baseTypes.regexp + baseTypes.object)
                currentType.group = groups.regexp.name
                currentType.collectProps(value)
                return currentType
            }
        } catch(err) {}
        if (typeof value === 'object' || typeof value === 'symbol') {
            var currentType = new Type(baseTypes.object)
            var group = currentType.setGroup(value)
            // handle long arrays specially to reduce time spent on properties collection
            if (group && group.slowTypeCollection && value.length > maxArrayLength) {
                currentType.properties.push('length')
                value = value.__proto__
            }
            currentType.collectProps(value)
            return currentType
        }
    } catch(err) {}

    // Set unknown if no type was matched or error occurred
    return new Type(baseTypes.unknown)
}
function updateType(number, value) {
    var currentType = getCurrentType(value)

    if (types[number] == null) types[number] = currentType
    else types[number] = types[number].union(currentType)
}