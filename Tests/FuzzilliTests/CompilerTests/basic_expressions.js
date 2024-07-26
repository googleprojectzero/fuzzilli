if (typeof output === 'undefined') output = console.log;

let a = 42;
let b = 3;

output(!a);
output(+a);
output(-a);
output(~a);
output(++a);
output(--a);
output(a++);
output(a--);

output(a + b);
output(a - b);
output(a * b);
output(a / b);
output(a % b);
output(a ** b);
output(a ^ b);
output(a & b);
output(a | b);
output(a << b);
output(a >> b);
output(a >>> b);
output(a && b);
output(a || b);
output(a > b ? a : b);
output(a < b ? a : b);

let arr = [1,2];
output(typeof arr);
output(0 in arr);
output(2 in arr);
output(arr instanceof Array);
output(arr instanceof Object);
