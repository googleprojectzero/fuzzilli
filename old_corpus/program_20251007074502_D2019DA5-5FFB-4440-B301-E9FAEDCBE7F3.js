// Minimizing 7A6F9EB3-D3C6-428B-92A9-C5CF40CB0D1C
function F0(a2, a3) {
    if (!new.target) { throw 'must be called with new'; }
}
function F4(a6, a7, a8, a9) {
    if (!new.target) { throw 'must be called with new'; }
}
for (let v10 = 0; v10 < 5; v10++) {
    F4[F0 + v10] = F4;
}
// Program is interesting due to new coverage: 4 newly discovered edges in the CFG of the target
