if (typeof output === 'undefined') output = console.log;

// Test variable names.
a = 1;
var b = 2;
let c = 3;

eval('output(a)');
eval('output(b)');
eval('output(c)');

// Test uninitialized variables.
var d, e;
d = 4;
e = 5;
eval('output(d)');
eval('output(e)');

// Test variable scoping.
function foo() {
  var f;
  h = 7;
  if (true) {
    f = 6;
    var g = 8;
    output(f);
    var h;
    output(h);
  }
  output(g);
}
foo();

// Test const variable assignment.
const i = 9;
try {
  i++;
} catch (e) {}
output(i);

// Test variable overwriting.
var j = 9;
var j = 10;
output(j);

// Test multiple references to the same existing variable.
k = 9;
k++;
k++;
output(k);
