if (typeof output === 'undefined') output = console.log;

function foo(a, b, c) {
  output(a);
  output(b);
  output(c);
}

let a = [1, 2, 3, 4];

foo(...a);
foo(100, ...a);
foo(100, 101, ...a);
foo(100, 101, 102, ...a);

new foo(...a);
new foo(100, ...a);
new foo(100, 101, ...a);
new foo(100, 101, 102, ...a);

let o = { foo };
o.foo(...a);
o.foo(100, ...a);
o.foo(100, 101, ...a);
o.foo(100, 101, 102, ...a);

// Array spreading tests
let array1 = [10, 20, 30];
let array2 = [...array1];

output(array1);
output(array2);

array1[0] = 100;
output(array1);
output(array2);

let combinedArray = [5, ...array1, 50];
output(combinedArray);

// Spread with array-like objects
function testArguments() {
  let argsArray = [...arguments];
  output(argsArray);
}

testArguments(1, 2, 3);

let nestedArray = [...[...[1, 2, 3]], ...[4, 5]];
output(nestedArray);
