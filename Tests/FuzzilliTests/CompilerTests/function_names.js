if (typeof output === 'undefined') output = console.log;

function plain1() {
  output(plain1.name);
}
plain1();

let f = function plain2() {
  output(plain2.name);
}
f();

function* generator1() {
  output(generator1.name);
}
generator1();

f = function* generator2() {
  output(generator2.name);
}
f();

async function asyncfunc1() {
  output(asyncfunc1.name);
}
asyncfunc1();

f = async function asyncfunc2() {
  output(asyncfunc2.name);
}
f();
