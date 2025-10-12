(() => {
  function f() {
    using x = null;
    console.log(x);
  }
  f();
})();

(() => {
  async function f() {
    await using x = null;
    console.log(x);
  }
  f();
})();

(() => {
  function * f() {
    try {
      yield 1;
      yield 2;
      yield 3;
    } finally {
      console.log("finally");
    }
  }

  {
    using o = f(), p = f();
    console.log(o.next());
    console.log(p.next());
    console.log(o.next());
  }
  console.log("the end")
})();

async function test(){
  async function * f() {
    try {
      yield 1;
      yield 2;
      yield 3;
    } finally {
      console.log("finally");
    }
  }

  {
    await using o = f(), p = f();
    console.log(await o.next());
    console.log(await p.next());
    console.log(await o.next());
  }
  console.log("the end")
};
test();
