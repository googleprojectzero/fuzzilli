// Minimizing 3AD8CC5A-9449-4E3B-905B-1AB88EACAAB4
class C0 {
}
C0[2];
function F4(a6, a7, a8, a9) {
    if (!new.target) { throw 'must be called with new'; }
    const v10 = this.constructor;
    try { new v10(); } catch (e) {}
}
new F4();
new F4(684504293, 3.8607079113389884e+307);
// Program is interesting due to new coverage: 1 newly discovered edge in the CFG of the target
