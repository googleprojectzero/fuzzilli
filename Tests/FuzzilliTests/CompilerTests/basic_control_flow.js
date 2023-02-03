if (typeof output === 'undefined') output = console.log;

let a = 5;
let b = 2;

if (a > b) {
  output("inside if");
}

if (b > a) {
  output("inside if");
} else {
  output("inside else");
}

while (a > b) {
  output("inside while loop");
  a--;
}

if (b > a) {
  output("inside if");
} else if (a == b) {
  output("inside else-if");
} else {
  output("inside else");
}

do {
  output("inside do-while loop");
} while (a > b);

for (let i = 0; i < a; i++) {
  output("inside for loop");
}

for (let p in [1,2,3]) {
  output("inside for-in loop");
}

for (let v of [4,5]) {
  output("inside for-of loop");
}

try {
  output("inside try");
} catch {
  output("inside catch");
}

try {
  output("inside try");
  throw 42;
} catch (e) {
  output("caught " + e);
  output("inside catch");
}

try {
  output("inside try");
} finally {
  output("inside finally");
}
