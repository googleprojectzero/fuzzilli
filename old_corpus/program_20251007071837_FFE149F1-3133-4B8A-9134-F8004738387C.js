// Minimizing 8FFBD1F0-C2F9-4D4D-B013-ECE7936BDACF
function f2() {
    return "toString";
}
function f3() {
    const v6 = {
        __proto__: f2,
        9: -1073741824,
        b: "toString",
        c: f2,
        set b(a5) {
        },
    };
    return v6;
}
f3();
f3();
const v9 = {};
for (let v10 = 0; v10 < 500; v10++) {
    f2();
}
// Program is interesting due to new coverage: 12 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 161 newly discovered edges in the CFG of the target
