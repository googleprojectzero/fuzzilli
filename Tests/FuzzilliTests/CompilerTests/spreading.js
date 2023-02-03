if (typeof output === 'undefined') output = console.log;

function foo(a, b, c) {
  output(a);
  output(b);
  output(c);
}

let a = [1,2,3,4];

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

// TODO also add tests for spreading in array literals
