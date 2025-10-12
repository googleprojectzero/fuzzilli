// TODO(https://crbug.com/446634535): Not yet supported cases are commented
// out below.

console.log("Computed object property");
(() => {
  const p = 'theAnswerIs';
  const obj = { [p] : 42 };
  console.log(obj.theAnswerIs);
})();

console.log("Computed object method");
(() => {
  const p = 'theAnswerIs';
  const obj = { [p]() { return 42; } };
  console.log(obj.theAnswerIs());
})();

console.log("Computed class property (field)");
(() => {
  function classify (name) {
    return class {
      [name] = 42;
    }
  }

  console.log(new (classify("theAnswerIs"))().theAnswerIs);
})();

console.log("Computed static class property (field)");
(() => {
  function classify (name) {
    return class {
      static [name] = 42;
    }
  }

  console.log((classify("theAnswerIs")).theAnswerIs);
})();

/*
console.log("Computed class property (getter/setter)");
(() => {
  function classify (name) {
    return class {
      answer = 7;

      get [name]() {
        console.log("Heavy calculations");
        return this.answer;
      }

      set [name](answer) {
        console.log(`The answer was ${this.answer}`);
        this.answer = answer;
        console.log(`Now the answer is ${this.answer}`);
      }
    }
  }

  const c = new (classify("theAnswerIs"))();
  console.log(c.theAnswerIs);
  c.theAnswerIs = 42;
  console.log(c.theAnswerIs);
})();
*/

/*
console.log("Computed static class property (getter/setter)");
(() => {
  function classify (name) {
    return class {
      static answer = 7;

      static get [name]() {
        console.log("Heavy calculations");
        return this.answer;
      }

      static set [name](answer) {
        console.log(`The answer was ${this.answer}`);
        this.answer = answer;
        console.log(`Now the answer is ${this.answer}`);
      }
    }
  }

  const c = classify("theAnswerIs");
  console.log(c.theAnswerIs);
  c.theAnswerIs = 42;
  console.log(c.theAnswerIs);
})();
*/

console.log("Computed class property (method)");
(() => {
  function classify (name) {
    return class {
      [name]() {
        console.log("Heavy calculations");
        return 42;
      }
    }
  }

  console.log(new (classify("theAnswerIs"))().theAnswerIs());
})();

console.log("Computed static class property (method)");
(() => {
  function classify (name) {
    return class {
      static [name]() {
        console.log("Heavy calculations");
        return 42;
      }
    }
  }

  console.log(classify("theAnswerIs").theAnswerIs());
})();

console.log("Indexed class property (field)");
(() => {
  class C {
    42 = 42;
  }
  const c = new C();
  console.log(c[42]);
})();

console.log("Indexed static class property (field)");
(() => {
  class C {
    static 42 = 42;
  }
  console.log(C[42]);
})();

/*
console.log("Indexed class property (method)");
(() => {
  class C {
    42() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  const c = new C();
  console.log(c[42]());
})();
*/

/*
console.log("Indexed static class property (method)");
(() => {
  class C {
    static 42() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  console.log(C[42]());
})();
*/

/*
console.log("Indexed class property (getter/setter)");
(() => {
  class C {
    answer = 7;

    get 42() {
      console.log("Heavy calculations");
      return this.answer;
    }

    set 42(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  const c = new C();
  console.log(c[42]);
  c[42] = 42;
  console.log(c[42]);
})();
*/

/*
console.log("Indexed static class property (getter/setter)");
(() => {
  class C {
    static answer = 7;

    static get 42() {
      console.log("Heavy calculations");
      return this.answer;
    }

    static set 42(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  console.log(C[42]);
  C[42] = 42;
  console.log(C[42]);
})();
*/

console.log("String-indexed class property (field)");
(() => {
  class C {
    "42" = 42;
  }
  const c = new C();
  console.log(c["42"]);
})();

console.log("String-indexed static class property (field)");
(() => {
  class C {
    static "42" = 42;
  }
  console.log(C["42"]);
})();

console.log("String-indexed class property (method)");
(() => {
  class C {
    "42"() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  const c = new C();
  console.log(c["42"]());
})();

console.log("String-indexed static class property (method)");
(() => {
  class C {
    static "42"() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  console.log(C["42"]());
})();

/*
console.log("String-indexed class property (getter/setter)");
(() => {
  class C {
    constructor() {
      this.answer = 7;
    }

    get "42"() {
      console.log("Heavy calculations");
      return this.answer;
    }

    set "42"(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  const c = new C();
  console.log(c["42"]);
  c["42"] = 42;
  console.log(c["42"]);
})();
*/

/*
console.log("String-indexed static class property (getter/setter)");
(() => {
  class C {
    static answer = 7;

    static get "42"() {
      console.log("Heavy calculations");
      return this.answer;
    }

    static set "42"(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  console.log(C["42"]);
  C["42"] = 42;
  console.log(C["42"]);
})();
*/

console.log("String-literal class property (field)");
(() => {
  class C {
    "theAnswerIs" = 42;
  }
  const c = new C();
  console.log(c.theAnswerIs);
})();

console.log("String-literal static class property (field)");
(() => {
  class C {
    static "theAnswerIs" = 42;
  }
  console.log(C.theAnswerIs);
})();

console.log("String-literal class property (method)");
(() => {
  class C {
    "theAnswerIs"() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  const c = new C();
  console.log(c.theAnswerIs());
})();

console.log("String-literal static class property (method)");
(() => {
  class C {
    static "theAnswerIs"() {
      console.log("Heavy calculations");
      return 42;
    }
  }
  console.log(C.theAnswerIs());
})();

/*
console.log("String-literal class property (getter/setter)");
(() => {
  class C {
    answer = 7;

    get "theAnswerIs"() {
      console.log("Heavy calculations");
      return this.answer;
    }

    set "theAnswerIs"(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  const c = new C();
  console.log(c.theAnswerIs);
  c.theAnswerIs = 42;
  console.log(c.theAnswerIs);
})();
*/

/*
console.log("String-literal static class property (getter/setter)");
(() => {
  class C {
    static answer = 7;

    static get "theAnswerIs"() {
      console.log("Heavy calculations");
      return this.answer;
    }

    static set "theAnswerIs"(answer) {
      console.log(`The answer was ${this.answer}`);
      this.answer = answer;
      console.log(`Now the answer is ${this.answer}`);
    }
  }
  console.log(C.theAnswerIs);
  C.theAnswerIs = 42;
  console.log(C.theAnswerIs);
})();
*/
