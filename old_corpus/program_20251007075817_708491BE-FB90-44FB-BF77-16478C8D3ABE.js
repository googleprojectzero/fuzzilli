// Minimizing 63DA22D4-860A-45D7-97DB-ED689FD30EC8
function F0(a2, a3, a4) {
    if (!new.target) { throw 'must be called with new'; }
    a2 * a2;
    const v6 = this.constructor;
    v6.c = v6;
    try { new v6(); } catch (e) {}
    this.e = a2;
    this.b = a4;
}
new F0();
new F0();
// Program is interesting due to new coverage: 21 newly discovered edges in the CFG of the target
