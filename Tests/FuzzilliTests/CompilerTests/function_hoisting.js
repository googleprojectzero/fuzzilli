if (typeof output === 'undefined') output = console.log;

output("foo");

bar();

output("baz");

function bar() {
  inner();
  function inner() {
    output("bar");
  }
}

output("bla");
