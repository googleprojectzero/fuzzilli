if (typeof output === 'undefined') output = console.log;

let counter = 5;
function countdown() {
  return counter--;
}
function resetCounter() {
  counter = 5;
}

//
// While loops
//
while (countdown()) {
  output("inside while loop body");
}
resetCounter()

while (output("inside while loop header"), output("still inside while loop header"), countdown()) {
  output("inside while loop body");
}
resetCounter();

while (output("inside while loop header"), counter) {
  output("inside while loop body");
  countdown();
}
resetCounter();

while ((function() { let c = countdown(); output("inside temporary function, c = " + c); return c; })()) {
  output("inside while loop body");
}
resetCounter();

//
// Do-While loops
//
do {
  output("inside do-while loop body");
} while (countdown())
resetCounter()

do {
  output("inside do-while loop body");
} while (output("inside do-while loop header"), output("still inside do-while loop header"), countdown())
resetCounter();

do {
  output("inside do-while loop body");
  countdown();
} while (output("inside do-while loop header"), counter)
resetCounter();

do {
  output("inside do-while loop body");
} while ((function() { let c = countdown(); output("inside temporary function, c = " + c); return c; })())
resetCounter();


//
// For loops
//
for (;;) {
  if (!counter--) {
    break;
  }
  output("inside for loop body");
  continue;
  output("should not be reached");
}
resetCounter();

for (let i = 0, j = 10; i < j; i++, j--) {
  output("inside for loop body, i: " + i + " j: " + j);
}

for (; countdown();) {
  output("inside for loop body");
}
resetCounter();

for (let i = 0; ; i++) {
  output("inside for loop body");
  if (i >= 5) break;
}

for (output("inside for loop initializer"); output("inside for loop condition"), true; output("inside for loop afterthought")) {
  output("inside for loop body");
  if (!countdown()) break;
}
resetCounter();

// Test scoping in the different parts of a for loop.
{
  global = { start: 0, end: 3, step: 1, value: 42 };
}
for (let i = global.start; i < global.end; i += global.step) {
  output("inside for loop body with global value", global.value);
}

