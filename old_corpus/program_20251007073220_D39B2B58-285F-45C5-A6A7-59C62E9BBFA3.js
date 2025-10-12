// Minimizing C0EF1A32-8DB3-426E-816A-31709F87E0B7
function F3(a5, a6, a7, a8) {
    if (!new.target) { throw 'must be called with new'; }
    this.p6 = 1e-15;
    this.c = a5;
}
F3[684504293] = Uint16Array;
const v9 = new F3();
const v10 = new F3(684504293);
for (let v11 = 0; v11 < 10; v11++) {
    v9["p" + v11] = v11;
}
F3[v10.c] **= 684504293;
// Program is interesting due to new coverage: 8 newly discovered edges in the CFG of the target
