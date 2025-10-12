if (typeof output === 'undefined') output = console.log;

let o = {}

o.a = 1;
o.b = 2 * o.a;
o['c'] = o['a'] + 2 * o['b'];

o[0] = 1;
o[1] = 1;
o[2] = o[1] + o[0];
o[3] = o[2] + o[1];

output(JSON.stringify(o));

with(o) {
  output(a);
  output(b);
  a = 3;
  b = 4;
  c = a + b;
}

output(JSON.stringify(o));
