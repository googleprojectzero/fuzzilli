if (typeof output === 'undefined') output = console.log;

function foo() {
  a = 42;
  output(a);
  output(this.a);
  {
    let a = 1337;
    output(a);
  }
  output(a);
}
foo();
output(a);
