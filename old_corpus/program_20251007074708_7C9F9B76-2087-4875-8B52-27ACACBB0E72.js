// Minimizing FB610E2C-E70C-485F-9EF4-D85DCA481797
const v1 = [-69232989,716822506,3,-10,-6506];
const v2 = [-11,-9,-1627167252,536870912,224770006];
const v3 = [-65537];
const v4 = class {
    m(a6) {
        const v9 = {
            value: v1,
            [Symbol]() {
            },
        };
        using v10 = v9;
    }
    #f;
    3;
    static g;
}
const v11 = v4?.toString;
try { v11(); } catch (e) {}
const v13 = new v4();
const v14 = new v4();
const v15 = new v4();
function f16(a17, a18) {
    const v27 = {
        ...v15,
        [v2](a20, a21) {
        },
        set d(a23) {
            super.setUint32(v1, v14);
        },
    };
    return v27;
}
const v28 = f16(v13, v13);
v28[482618132] = v28;
const v29 = [-9,2147483648,-9007199254740990,9,1000,-4645,4096,-65537];
try { v29.with(v3); } catch (e) {}
// Program is interesting due to new coverage: 17 newly discovered edges in the CFG of the target
