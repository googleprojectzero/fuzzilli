if (typeof output === 'undefined') output = console.log;

debugger;

function testDebugger(x) {
  debugger;
  if (x > 0) {
    debugger;
    return x * 2;
  } else {
    debugger;
  }
  return 0;
}

output(testDebugger(21));
output(testDebugger(-5));
