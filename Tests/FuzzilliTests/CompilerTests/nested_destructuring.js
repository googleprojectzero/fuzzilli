if (typeof output === 'undefined') output = console.log;

// Basic & Shorthand
let { a, b } = { a: 1, b: 2 };
output(a, b);

// Aliasing (Renaming)
let { c: charlie } = { c: 3 };
output(charlie);

// Default Values
let { d = 4, e = 5, f = 6 } = { d: undefined, e: null, f: false };
output(d, e, f);

// Aliasing + Default Values
let { g: renamedG = 7 } = {};
output(renamedG);

// Computed Property Names
const dynKey = "dynamic";
let { [dynKey]: h, ["comp" + "uted"]: i } = { dynamic: 8, computed: 9 };
output(h, i);

// Computed Property + Alias + Default
let { ["missing" + "Key"]: j = 10 } = {};
output(j);

// Rest Properties
let { k, ...restProps } = { k: 11, l: 12, m: 13 };
output(k, restProps.l, restProps.m);

// Deep / Nested Object Destructuring
let { user: { profile: { id } } } = { user: { profile: { id: 14 } } };
output(id);

// Missing Properties
let { missingProp } = { present: true };
output(missingProp);

// Empty Object Pattern
let { } = { x: 15 };

// Destructuring Primitives
let { length, toUpperCase } = "hello";
output(length, typeof toUpperCase);

// JSON-style Objects
const parsedJSON = JSON.parse('{"first-name": "Alice", "status": 200}');
let { "first-name": firstName, status } = parsedJSON;
output(firstName, status);

// Basic Non-nested
let [first, second] = [10, 20];
output(second);

// Elision
let [a2, , b2, , , c2] = [1, 2, 3, 4, 5, 6];
output(b2, c2);

// Trailing Elision
let [d2, e2, ,] = [7, 8, 9, 10];
output(e2);

// Default Values
let [f2 = 100, g2 = 200] = [undefined, null];
output(f2, g2);

// Rest Elements
let [head, ...tail] = [1, 2, 3, 4];
output(tail[0], tail[1], tail[2]);

// Nested Array Destructuring
let [x, [y, z]] = [1, [2, 3]];
output(z);

// Rest Elements as a Pattern
let [start, ...[...restUnpacked]] = [10, 20, 30];
output(restUnpacked[0], restUnpacked[1]);

// Array Rest resolving into an Object pattern
let [n, ...{ length: len, 0: p }] = [37, 38, 39];
output(n, len, p);

// Works on ANY Iterable
const mySet = new Set([88, 99]);
let [setFirst] = mySet;
output(setFirst);

// Object inside Array
let [{ id: id1 }, { id: id2 = "default" }] = [{ id: 1 }, {}];
output(id2);

// Array inside Object
let { coords: [x2, y2] } = { coords: [45.5, -122.6] };
output(y2);

// Deeply mixed
let [, { tags: [, secondTag, ...otherTags], status: status2 = "active" }] = [
    { tags: ["ignore"] },
    { tags: ["js", "web", "node"] }
];
output(secondTag, status2, otherTags[0]);

// Rest properties with aliasing and defaults
let { j2=10, k2: renamedK2, ...restProps2 } = { k2: 11, l: 12, m: 13 };
output(j2, renamedK2, restProps2.l, restProps2.m);

// Multiple nested rest elements, defaults, and aliasing
let { user2: { profile2: { id: I, ...rest1 }, type=0, ...rest2 } } = { user2: { profile2: { id: 14, name: "foo" }, active: false } };
output(I, type, rest1.name, rest2.active);

// Elision + rest
let [head2, , ...tail2] = [1, 2, 3, 4];
output(tail2[0], tail2[1]);


