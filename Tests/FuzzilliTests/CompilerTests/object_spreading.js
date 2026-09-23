if (typeof output === 'undefined') output = console.log;

let obj1 = { a: 1, b: 2 };
let obj2 = { ...obj1 };
output(obj2.a, obj2.b);

// Mutating original does not affect shallow copy
obj1.a = 99;
output(obj1.a, obj2.a);

// Overriding properties before and after spread
let obj3 = { a: 10, ...obj2, b: 20, c: 30 };
output(obj3.a, obj3.b, obj3.c);

// Multiple spreads and computed keys in order
let order = [];
function track(label, val) {
  order.push(label);
  return val;
}
let combined = {
  [track('k1', 'x')]: track('v1', 1),
  ...track('s1', { x: 2, y: 3 }),
  [track('k2', 'y')]: track('v2', 4),
  ...track('s2', { z: 5 }),
};
output(order.join(','));
output(combined.x, combined.y, combined.z);

// Spreading inline object literal and null/undefined
let nested = { ...{ p: 42 }, ...null, ...undefined };
output(nested.p, Object.keys(nested).length);
