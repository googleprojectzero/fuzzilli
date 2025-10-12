// Minimizing 54BB878D-1B61-4413-9837-A44646F55891
const v2 = new Uint16Array();
const v7 = new Int16Array(1907);
function f8(a9, a10, a11, a12) {
    const v18 = {
        a: a10,
        h: a9,
        __proto__: v2,
        ...a11,
        get f() {
            try { this.toString(v7, 3, BigUint64Array, this); } catch (e) {}
            const v15 = super[1907];
            try { v15["toString"](); } catch (e) {}
            return a9;
        },
    };
    return v18;
}
f8(7, 7, v7);
f8(7, 7, f8());
// Program is interesting due to new coverage: 126 newly discovered edges in the CFG of the target
