function f(x, ...rest) {
    return x * rest.length;
}
console.log(f(7, 2, 3, 4));

// A function expression is parsed differently than a function declaration.
console.log((function funcExpression(...rest) { return rest[2]; })(null, null, 75, null));

let arrow = (...values) => values.length;
console.log(arrow(1, 1, 1, 1, 1, 1, 1));
console.log(((x, y, ...rest) => rest.length)(0, 0, 1, 2, 3, 2, 1));

class C {
  constructor(...rest) {
    this.args = rest;
  }

  method(...args) {
    return this.args.length * args.length;
  }

  static staticMethod(...rest) {
    return rest.length;
  }
}

console.log(new C(1, 1, 1, 1, 1, 1).method(2, 2, 2));
console.log(C.staticMethod(1, 1));
