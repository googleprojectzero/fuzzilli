if (typeof output === 'undefined') output = console.log;

function f1(a, b) {
  return a + b;
}
output(f1(1, 2));

let f2 = function(a, b) {
  return a * b;
}
output(f2(3, 4));

let f3 = (x) => x + 1;
output(f3(5));

let f4 = (x) => { return x * 2 };
output(f4(6));

function* f5(n) {
  for (let i = 0; i < n; i++) {
    yield n;
  }
}
output(Array.from(f5(3)).length);

async function f6() {
  return await 42;
}
output(f6().constructor.name);

function f7() {
  return arguments[0] + arguments.length * arguments[1];
}
output(f7(7, 8, 9));
