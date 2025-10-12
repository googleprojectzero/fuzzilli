if (typeof output === 'undefined') output = console.log;

let u = undefined;
try { u.a; } catch (e) { output("Property access on 'undefined' failed as expected"); }
try { u[0]; } catch (e) { output("Property access on 'undefined' failed as expected"); }
try { u.foo(); } catch (e) { output("Method call on 'undefined' failed as expected"); }
output(u?.a);
output(u?.[0]);
output(u?.foo());

let o = {0: "foo", a: 42, foo() { output("foo called"); return "bar"; }};
output(o.a);
output(o[0]);
output(o.foo());
output(o?.a);
output(o?.[0]);
output(o?.foo());
