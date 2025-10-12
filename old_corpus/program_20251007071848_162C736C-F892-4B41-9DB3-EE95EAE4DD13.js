// Minimizing 605A468F-E835-4E6C-876E-6A96E294C973
function f1() {
    return "toString";
}
for (let v2 = 0; v2 < 500; v2++) {
    f1();
}
new Int16Array();
Math.log1p(255);
// Program is interesting due to new coverage: 65 newly discovered edges in the CFG of the target
