// Minimizing D968EBBE-4D54-467B-AE9F-B7CC63C95847
const v2 = new Uint16Array(7);
function f3(a4, a5, a6, a7) {
    const v9 = {
        __proto__: v2,
        ...a6,
        get f() {
            return this;
        },
    };
    v9[6] = v9;
    return v9;
}
f3(7, 7, f3());
// Program is interesting due to new coverage: 6 newly discovered edges in the CFG of the target
