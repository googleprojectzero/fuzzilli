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

// for-in key (Declaration)
for (const key in objForIn) {
  output("for-in key: " + key + " value: " + objForIn[key]);
}

// for-in key (Reassignment)
let r_key;
for (r_key in objForIn) {
  output("reassign for-in key: " + r_key + " value: " + objForIn[r_key]);
}

// sync var (Declaration)
for (const x of syncDataset) {
  output("sync var: " + x);
}

// sync var (Reassignment)
let r_x;
for (r_x of syncDataset) {
  output("reassign sync var: " + r_x);
}

// sync destruct_array (Declaration)
for (const [a, b] of arrayDataset) {
  output("sync destruct_array a: " + a + " b: " + b);
}

// sync destruct_array (Reassignment)
let r_a, r_b;
for ([r_a, r_b] of arrayDataset) {
  output("reassign sync destruct_array a: " + r_a + " b: " + r_b);
}

// sync destruct_array_rest (Declaration)
for (const [a, ...b] of arrayDataset) {
  output("sync destruct_array_rest a: " + a + " b: " + b);
}

// sync destruct_array_rest (Reassignment)
let r_ar_a, r_ar_b;
for ([r_ar_a, ...r_ar_b] of arrayDataset) {
  output("reassign sync destruct_array_rest a: " + r_ar_a + " b: " + r_ar_b);
}

// sync destruct_object (Declaration)
for (const { a, b } of objectDataset) {
  output("sync destruct_object a: " + a + " b: " + b);
}

// sync destruct_object (Reassignment)
let r_o_a, r_o_b;
for ({ a: r_o_a, b: r_o_b } of objectDataset) {
  output("reassign sync destruct_object a: " + r_o_a + " b: " + r_o_b);
}

// sync destruct_object_rest (Declaration)
for (const { a, ...b } of objectDataset) {
  output("sync destruct_object_rest a: " + a + " b.b: " + b.b + " b.c: " + b.c);
}

// sync destruct_object_rest (Reassignment)
let r_or_a, r_or_b;
for ({ a: r_or_a, ...r_or_b } of objectDataset) {
  output("reassign sync destruct_object_rest a: " + r_or_a + " b.b: " + r_or_b.b + " b.c: " + r_or_b.c);
}

// sync destruct_nested_object (Declaration)
for (const { user: { profile: { id } } } of complexObjectDataset) {
  output("sync destruct_nested_object id: " + id);
}

// sync destruct_nested_object (Reassignment)
let r_nested_id;
for ({ user: { profile: { id: r_nested_id } } } of complexObjectDataset) {
  output("reassign sync destruct_nested_object id: " + r_nested_id);
}

// sync destruct_mixed (Declaration)
for (const [{ id: id1 }, { id: id2 = "default" }] of mixedDataset) {
  output("sync destruct_mixed id1: " + id1 + " id2: " + id2);
}

// sync destruct_mixed (Reassignment)
let r_mixed_id1, r_mixed_id2;
for ([{ id: r_mixed_id1 }, { id: r_mixed_id2 = "default" }] of mixedDataset) {
  output("reassign sync destruct_mixed id1: " + r_mixed_id1 + " id2: " + r_mixed_id2);
}

// sync destruct_array_rest_object (Declaration)
for (const [n, ...{ length: len, 0: p }] of arrayRestDataset) {
  output("sync destruct_array_rest_object n: " + n + " len: " + len + " p: " + p);
}

// sync destruct_array_rest_object (Reassignment)
let r_aro_n, r_aro_len, r_aro_p;
for ([r_aro_n, ...{ length: r_aro_len, 0: r_aro_p }] of arrayRestDataset) {
  output("reassign sync destruct_array_rest_object n: " + r_aro_n + " len: " + r_aro_len + " p: " + r_aro_p);
}

// sync destruct_member_expression (Reassignment)
let r_mem_obj = {};
for ([r_mem_obj.prop] of arrayRestDataset) {
  output("reassign sync destruct_member_expression prop: " + r_mem_obj.prop);
}

async function runAsyncTests() {
  // async sync var (Declaration)
  for await (const x of syncDataset) {
    output("async var: " + x);
  }

  // async sync var (Reassignment)
  let ra_x;
  for await (ra_x of syncDataset) {
    output("reassign async var: " + ra_x);
  }

  // async sync destruct_array (Declaration)
  for await (const [a, b] of arrayDataset) {
    output("async destruct_array a: " + a + " b: " + b);
  }

  // async sync destruct_array (Reassignment)
  let ra_a, ra_b;
  for await ([ra_a, ra_b] of arrayDataset) {
    output("reassign async destruct_array a: " + ra_a + " b: " + ra_b);
  }

  // async sync destruct_array_rest (Declaration)
  for await (const [a, ...b] of arrayDataset) {
    output("async destruct_array_rest a: " + a + " b: " + b);
  }

  // async sync destruct_array_rest (Reassignment)
  let ra_ara_a, ra_ara_b;
  for await ([ra_ara_a, ...ra_ara_b] of arrayDataset) {
    output("reassign async destruct_array_rest a: " + ra_ara_a + " b: " + ra_ara_b);
  }

  // async sync destruct_object (Declaration)
  for await (const { a, b } of objectDataset) {
    output("async destruct_object a: " + a + " b: " + b);
  }

  // async sync destruct_object (Reassignment)
  let ra_o_a, ra_o_b;
  for await ({ a: ra_o_a, b: ra_o_b } of objectDataset) {
    output("reassign async destruct_object a: " + ra_o_a + " b: " + ra_o_b);
  }

  // async sync destruct_object_rest (Declaration)
  for await (const { a, ...b } of objectDataset) {
    output("async destruct_object_rest a: " + a + " b.b: " + b.b + " b.c: " + b.c);
  }

  // async sync destruct_object_rest (Reassignment)
  let ra_ora_a, ra_ora_b;
  for await ({ a: ra_ora_a, ...ra_ora_b } of objectDataset) {
    output("reassign async destruct_object_rest a: " + ra_ora_a + " b.b: " + ra_ora_b.b + " b.c: " + ra_ora_b.c);
  }

  // async sync destruct_nested_object (Declaration)
  for await (const { user: { profile: { id } } } of complexObjectDataset) {
    output("async destruct_nested_object id: " + id);
  }

  // async sync destruct_nested_object (Reassignment)
  let ra_nested_id;
  for await ({ user: { profile: { id: ra_nested_id } } } of complexObjectDataset) {
    output("reassign async destruct_nested_object id: " + ra_nested_id);
  }

  // async sync destruct_mixed (Declaration)
  for await (const [{ id: id1 }, { id: id2 = "default" }] of mixedDataset) {
    output("async destruct_mixed id1: " + id1 + " id2: " + id2);
  }

  // async sync destruct_mixed (Reassignment)
  let ra_mixed_id1, ra_mixed_id2;
  for await ([{ id: ra_mixed_id1 }, { id: ra_mixed_id2 = "default" }] of mixedDataset) {
    output("reassign async destruct_mixed id1: " + ra_mixed_id1 + " id2: " + ra_mixed_id2);
  }

  // async sync destruct_array_rest_object (Declaration)
  for await (const [n, ...{ length: len, 0: p }] of arrayRestDataset) {
    output("async destruct_array_rest_object n: " + n + " len: " + len + " p: " + p);
  }

  // async sync destruct_array_rest_object (Reassignment)
  let ra_aro_n, ra_aro_len, ra_aro_p;
  for await ([ra_aro_n, ...{ length: ra_aro_len, 0: ra_aro_p }] of arrayRestDataset) {
    output("reassign async destruct_array_rest_object n: " + ra_aro_n + " len: " + ra_aro_len + " p: " + ra_aro_p);
  }

  // async sync destruct_member_expression (Reassignment)
  let ra_mem_obj = {};
  for await ([ra_mem_obj.prop] of arrayRestDataset) {
    output("reassign async destruct_member_expression prop: " + ra_mem_obj.prop);
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
