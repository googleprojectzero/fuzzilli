// Minimizing 37786F97-9596-4E9A-9FBA-86DD69361ED4
class C1 {
}
const v2 = new C1();
const v3 = new C1();
function f4() {
    function f5(a6) {
    }
    return f5;
}
function f7(a8) {
    return C1;
}
Object.defineProperty(v3, Symbol.toPrimitive, { configurable: true, enumerable: true, get: f4, set: f7 });
function f11() {
    return f11;
}
v2[Symbol] = f11;
C1[v3] = 1.3015274434576854e+308;
// Program is interesting due to new coverage: 11 newly discovered edges in the CFG of the target
