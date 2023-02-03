if (typeof output === 'undefined') output = console.log;

function f(v) {
  if (v > 1) {
    return f(v - 1) * v;
  } else {
    return 1;
  }
}
output(f(42));

