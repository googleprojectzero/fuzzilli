// Minimizing 80775726-6064-447C-B3B6-C4CDF2083DAE
const v2 = class {
    [9] = 1000.0;
    constructor(a4) {
        let v5;
        try { v5 = a4(9); } catch (e) {}
        this[1073741824] = 1000.0;
        this?.[this];
        const v8 = Symbol.dispose;
        const v10 = {
            value: v5,
            [v8]() {
            },
        };
        using v11 = v10;
    }
}
new v2(9);
// Program is interesting due to new coverage: 19 newly discovered edges in the CFG of the target
