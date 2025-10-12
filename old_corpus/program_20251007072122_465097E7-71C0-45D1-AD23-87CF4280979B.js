// Minimizing 83BE9F09-8357-42CB-A524-DBCC078CA784
const v0 = [-951142966,1,5,268435440,-7];
v0.flat(v0);
const v2 = [-9223372036854775807,31754,-1583478162,2061316964,-4096,-9007199254740990,65535,-1857689020,-9223372036854775807,9];
const v3 = ~v2;
let v5;
try { v5 = new Uint8ClampedArray(v3); } catch (e) {}
const v6 = [-2147483647,23958,9223372036854775807,2147483647];
const v8 = new Date(v3);
function f9() {
    return Date;
}
class C10 {
}
try { C10.apply(v2, v8); } catch (e) {}
function f12(a13, a14) {
    v6[7] = f9;
    const v16 = Symbol.dispose;
    const v18 = {
        value: a14,
        [v16]() {
        },
    };
    using v19 = v18;
    return v5;
}
f12();
// Program is interesting due to new coverage: 142 newly discovered edges in the CFG of the target
