if (typeof output === 'undefined') output = console.log;

// This tests makes sure that we don't create additional block statements during compilation.
// For example, a typical AST for an if statement (ignoring the condition) would look like this:
//
//     IfStatement
//          |
//    BlockStatement
//     /    |     \
//  Foo    Bar    Baz
//
//  In that case, we want to generate the following IL code:
//
//    BeginIf
//      Foo
//      Bar
//      Baz
//    EndIf
//
// And not
//
//    BeginIf
//      BeginBlock
//        Foo
//        Bar
//        Baz
//      EndBlock
//    EndIf
//
function test() {
  function f1() {}
  function* f2() {}
  async function f3() {}
  let f4 = () => {};
  {}
  if (true) {}
  else {}
  for (let i = 0; i < 1; i++) {}
  for (let p of {}) {}
  for (let p in {}) {}
  while (false) {}
  do {} while (false);
  try {} catch (e) {} finally {}
  with ({}) {}
  let o = {
    m() {},
    get a() {},
    set a(v) {}
  };
  class C {
    constructor() {}
    m() {}
    get a() {}
    set a(v) {}
    static n() {}
    static get b() {}
    static set b(v) {}
    static {}
  }
}

let source = test.toString();
let num_braces = source.split('{').length - 1;
output(num_braces);
