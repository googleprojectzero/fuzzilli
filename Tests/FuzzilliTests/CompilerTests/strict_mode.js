if (typeof output === 'undefined') output = console.log;

// Note: we currently don't support global strict mode. It would be easy
// to add support in the parser and compiler for that, but the problem
// is that for compiler tests and, more importantly, during fuzzing, we
// often add a program prefix, which would render the "use strict"
// directive ineffective.

function strict() {
  "use strict";

  try {
    nonexistant = "foo";
  } catch (e) {
    output(e.message);
  }

  let o = {};
  Object.defineProperty(o, 'x', { value: 42, writable: false, configurable: false });

  if (true) {
    try {
      o.x = 43;
    } catch (e) {
      output(e.message);
    }
  }

  function inner() {
    try {
      delete o.x;
    } catch (e) {
      output(e.message);
    }
  }
  inner();
}

strict();
