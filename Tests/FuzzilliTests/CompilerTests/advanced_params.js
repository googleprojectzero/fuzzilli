function functionSimple(param0) {
    console.log("Param0:", param0);
}

function functionNoParam() {
    console.log("No parameters here ...");
}

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

function functionWithNestedObjectPattern(param0, { param1, param2: { subParam1, subParam2 } }) {
    console.log("Param0:", param0);
    console.log("Param1:", param1);
    console.log("SubParam1:", subParam1);
    console.log("SubParam2:", subParam2);
}

function functionWithNestedArrayPattern(param0, [param1, [subParam1, subParam2]]) {
    console.log("Param0:", param0);
    console.log("Param1:", param1);
    console.log("SubParam1:", subParam1);
    console.log("SubParam2:", subParam2);
}

function functionWithMixedPattern([param0, { objParam1, objParam2 }], { arrParam1, arrParam2: [subArr1, subArr2] }) {
    console.log("Param0 (Array pattern):", param0);
    console.log("ObjParam1 (in Array pattern):", objParam1);
    console.log("ObjParam2 (in Array pattern):", objParam2);
    console.log("ArrParam1 (in Object pattern):", arrParam1);
    console.log("SubArr1 (in Array within Object pattern):", subArr1);
    console.log("SubArr2 (in Array within Object pattern):", subArr2);
}


functionWithObjectPattern("foo", { param1: 23, param2: 42 });
functionWithArrayPattern("bar", [9000, 9001]);
functionWithNestedObjectPattern("foo", { param1: 23, param2: { subParam1: 100, subParam2: 200 } });
functionWithNestedArrayPattern("bar", [9000, [9001, 9002]]);
functionWithMixedPattern(["alpha", { objParam1: 300, objParam2: 400 }], { arrParam1: 500, arrParam2: [8000, 8001] });