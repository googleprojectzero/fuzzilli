if (typeof output === 'undefined') output = console.log;

var a, b = 42;
a = 41;
b -= 10;
output(a + b);

let c = 1, d, e = 5;
c = 2;
d = e;
output(c + d - e);

const C = c;
output(C);
