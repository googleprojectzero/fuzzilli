function functionWithObjectPattern(param0, { param1, param2 }) {
    console.log("Param0:", param0);
    console.log("Param1:", param1);
    console.log("Param2:", param2);
}
 
function functionWithArrayPattern(param0, [param1, param2]) {
    console.log("Param0:", param0);
    console.log("Param1:", param1);
    console.log("Param2:", param2);
}

functionWithObjectPattern("foo", { param1: 23, param2: 42 });
functionWithArrayPattern("bar", [9000, 9001]);

/* TODO
1) Property renaming in object pattern parameters (e.g. {a: b, c: d})
2) Nested objected/array patterns (e.g. {a: {b, c}, d: [e, f]})
3) Default values for parameters (e.g. function f(a = 42) { ... })
*/