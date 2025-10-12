// Minimizing 6CA4C133-1F29-4FB9-B0C3-83D4518FBC02
Object.defineProperty(Symbol, "toString", { configurable: true, value: Symbol });
function f1() {
    const v7 = {
        ..."find",
        a: -2.220446049250313e-16,
        get b() {
            return "find";
        },
        [Symbol]() {
        },
        [Symbol]() {
        },
    };
    return v7;
}
f1();
f1();
// Program is interesting due to new coverage: 17 newly discovered edges in the CFG of the target
