if (typeof output === 'undefined') output = console.log;

// Test to ensure that multiple uses of the same named variable compile correctly.

{
  // This named variable will go out of scope, so subsequent uses require creating a new one (with the same name).
  global = { start: 0, end: 3, step: 1, value: 42 };
}

{
  if (global.value) {
    output("inside if with global value", global.value);
  } else {
    output("inside else with global value", global.value);
  }
}

{
  for (let i = global.start; i < global.end; i += global.step) {
    output("inside for loop body with global value", global.value);
  }
}

{
  let i = 0;
  while (i < global.end) {
    i += global.step;
    output("inside while loop body with global value", global.value);
  }
}

{
  let i = 0;
  do {
    i += global.step;
    output("inside do-while loop body with global value", global.value);
  } while (i < global.end);
}
