function functionSimple(paramA) {
    console.log("paramA:", paramA);
}

function functionNoParam() {
    console.log("No parameters here ...");
}

function functionWithObjectPattern(argPrimary, { keyA, keyB }) {
    console.log("keyB:", keyB);
    console.log("argPrimary:", argPrimary);
    console.log("keyA:", keyA);
}

function functionWithArrayPattern(firstElem, [secondElem, thirdElem]) {
    console.log("secondElem:", secondElem);
    console.log("thirdElem:", thirdElem);
    console.log("firstElem:", firstElem);
}

function functionWithNestedObjectPattern(mainArg, { nestedKey1, nestedKey2: { subKeyX, subKeyY } }) {
    console.log("mainArg:", mainArg);
    console.log("subKeyY:", subKeyY);
    console.log("nestedKey1:", nestedKey1);
    console.log("subKeyX:", subKeyX);
}

function functionWithNestedArrayPattern(primaryElem, [secondaryElem, [nestedElemX, nestedElemY]]) {
    console.log("primaryElem:", primaryElem);
    console.log("nestedElemY:", nestedElemY);
    console.log("secondaryElem:", secondaryElem);
    console.log("nestedElemX:", nestedElemX);
}

function functionWithMixedPattern(
    [arrayElem1, { objKey1, objKey2 }],
    { arrKey1, arrKey2: [nestedArrElem1, nestedArrElem2] }
) {
    console.log("objKey2:", objKey2);
    console.log("arrKey1:", arrKey1);
    console.log("nestedArrElem1:", nestedArrElem1);
    console.log("objKey1:", objKey1);
    console.log("arrayElem1:", arrayElem1);
    console.log("nestedArrElem2:", nestedArrElem2);
}

functionWithObjectPattern("foo", { keyA: 23, keyB: 42 });
functionWithArrayPattern("bar", [9000, 9001]);
functionWithNestedObjectPattern("foo", { nestedKey1: 23, nestedKey2: { subKeyX: 100, subKeyY: 200 } });
functionWithNestedArrayPattern("bar", [9000, [9001, 9002]]);
functionWithMixedPattern(
    ["alpha", { objKey1: 300, objKey2: 400 }],
    { arrKey1: 500, arrKey2: [8000, 8001] }
);