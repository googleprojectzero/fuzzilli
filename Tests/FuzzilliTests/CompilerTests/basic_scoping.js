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

let obj = { x: 45, y: 9001 };
with (obj) {
  output(x);
  output(y);
}
