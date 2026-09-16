if (typeof output === "undefined") output = console.log;

const obj1 = { 42n: 42 };
output(obj1[42n]);
output(obj1["42"]);
output(Object.keys(obj1).length);

const obj2 = { 1: 1, 1n: 2n, "1": "3" };
output(Object.keys(obj2).length);
output(obj2[1n]);

const obj3 = {
  get 3n() {
    return 3;
  },
  set 3n(v) {},
};
obj3[3n] = 42;
output(obj3[3n]);

class C {
  static 2n() {
    return 2;
  }
  1n() {
    return 1;
  }
}
output(C[2n]());
output(new C()[1n]());

let { 1n: x } = { 1n: "big" };
output(x);
