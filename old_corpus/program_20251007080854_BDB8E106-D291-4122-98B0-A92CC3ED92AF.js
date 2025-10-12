// Minimizing 451735F6-3D6A-4D6D-A821-8389940474C0
function F0(a2, a3, a4) {
    if (!new.target) { throw 'must be called with new'; }
    const t3 = this.constructor;
    t3(F0);
}
F0.prototype = F0;
const v7 = new F0(F0, F0, F0);
new F0(v7, v7, F0);
new F0();
// Program is interesting due to new coverage: 9 newly discovered edges in the CFG of the target
