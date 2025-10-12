if (typeof output === 'undefined') output = console.log;

let o = {};
output(o);

let b = 1337;
o = {a: 42, b, 0: "foo", 1: "bar" };
output(o.a);
output(o.b);
output(o[0]);
output(o[1]);

o = {b: 42, ["baz"]: 13.37, get c() { return this.b; }, set c(v) { this.b = v; output(v); }};
output(o.b);
output(o.baz);
output(o.c);
o.c = 1234;
output(o.c);

o = {x: 2, m(arg) { return arg * this.x; }};
output(o.m(13.37));

o = {['v']: 42, [Symbol.toPrimitive]() { return this.v; }};
output(3 + o);

let a = [1,2,3];
output(a.length);
output(a[1]);

a = [1.1,,3.3,,5.5,];
output(a.length);
output(a[0]);
output(a[1]);
output(a[2]);

function C(foo) {
  this.foo = foo;
}
o = new C(1337);
output(o.foo);
