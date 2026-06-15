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

while ((function () { let c = countdown(); output("inside temporary function, c = " + c); return c; })()) {
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
} while ((function () { let c = countdown(); output("inside temporary function, c = " + c); return c; })())
resetCounter();


//
// For loops
//
for (; ;) {
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

// ForInOf Loops
// -------------
const syncDataset = [10, 11, 12];
const arrayDataset = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
const objectDataset = [{ a: 1, b: 2, c: 3 }, { a: 4, b: 5, c: 6 }, { a: 7, b: 8, c: 9 }];
const complexObjectDataset = [{ user: { profile: { id: 14 } } }, { user: { profile: { id: 15 } } }];
const mixedDataset = [[{ id: 1 }, {}], [{ id: 2 }, { id: 3 }]];
const arrayRestDataset = [[37, 38, 39], [40, 41, 42]];

const objForIn = { a: 100, b: 200, c: 300 };
for (const key in objForIn) {
  output("for-in key: " + key + " value: " + objForIn[key]);
}

for (const x of syncDataset) {
  output("sync var: " + x);
}

for (const [a, b] of arrayDataset) {
  output("sync destruct_array a: " + a + " b: " + b);
}

for (const [a, ...b] of arrayDataset) {
  output("sync destruct_array_rest a: " + a + " b: " + b);
}

for (const { a, b } of objectDataset) {
  output("sync destruct_object a: " + a + " b: " + b);
}

for (const { a, ...b } of objectDataset) {
  output("sync destruct_object_rest a: " + a + " b.b: " + b.b + " b.c: " + b.c);
}

for (const { user: { profile: { id } } } of complexObjectDataset) {
  output("sync destruct_nested_object id: " + id);
}

for (const [{ id: id1 }, { id: id2 = "default" }] of mixedDataset) {
  output("sync destruct_mixed id1: " + id1 + " id2: " + id2);
}

for (const [n, ...{ length: len, 0: p }] of arrayRestDataset) {
  output("sync destruct_array_rest_object n: " + n + " len: " + len + " p: " + p);
}

async function runAsyncTests() {
  for await (const x of syncDataset) {
    output("async var: " + x);
  }

  for await (const [a, b] of arrayDataset) {
    output("async destruct_array a: " + a + " b: " + b);
  }

  for await (const [a, ...b] of arrayDataset) {
    output("async destruct_array_rest a: " + a + " b: " + b);
  }

  for await (const { a, b } of objectDataset) {
    output("async destruct_object a: " + a + " b: " + b);
  }

  for await (const { a, ...b } of objectDataset) {
    output("async destruct_object_rest a: " + a + " b.b: " + b.b + " b.c: " + b.c);
  }

  for await (const { user: { profile: { id } } } of complexObjectDataset) {
    output("async destruct_nested_object id: " + id);
  }

  for await (const [{ id: id1 }, { id: id2 = "default" }] of mixedDataset) {
    output("async destruct_mixed id1: " + id1 + " id2: " + id2);
  }

  for await (const [n, ...{ length: len, 0: p }] of arrayRestDataset) {
    output("async destruct_array_rest_object n: " + n + " len: " + len + " p: " + p);
  }
}

runAsyncTests();

// Explicit Resource Management in Loops
// -------------------------------------

const disposableResource = {
  [Symbol.dispose]() {
    output("disposed sync resource");
  }
};

for (using x of [disposableResource]) {
  output("inside sync using loop");
}

async function runExplicitResourceManagementAsyncTests() {
  for await (using x of [disposableResource]) {
    output("inside async loop with sync resource");
  }
}

runExplicitResourceManagementAsyncTests();

let asyncLog = [];
async function runAsyncTimingTest() {
  asyncLog.push("start");
  for await (const x of [1, 2]) {
    asyncLog.push("loop_" + x);
  }
  asyncLog.push("end");
}

runAsyncTimingTest();
asyncLog.push("main_end");

setTimeout(() => {
  output("async timing outcome: " + asyncLog.join(", "));
}, 0);
