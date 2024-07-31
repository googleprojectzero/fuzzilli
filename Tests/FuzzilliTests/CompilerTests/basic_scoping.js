if (typeof output === 'undefined') output = console.log;

let x = 42;
let y = 1337;

output(x);
output(y);

function foo(x) {
  output(x);
  output(y);
  {
    let x = 43;
    output(x);
    output(y);
  }
  output(x);
  output(y);
}
foo(44);

// Note: this test will currently fail if 'a' and 'b' are replaced by
// 'x' and 'y' in the object. That's because the compiler will still used
// regular/numbered variables for x and y, and so will effectively rename
// them to something like `v1` and `v2`, while keeping the property names
// of the object. This isn't easy to fix, unfortunately. One option might
// be to change the compiler to only use named variables in testcases that
// use `with` statements, but that would be quite an invasive change and
// result in a FuzzIL program that is less suited for mutations.
let obj = { a: 45, b: 9001 };
with (obj) {
  output(x);
  output(y);
  output(a);
  output(b);
}
