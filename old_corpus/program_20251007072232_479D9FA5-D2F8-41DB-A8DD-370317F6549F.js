// Minimizing 548C9680-046B-4747-AF47-9D3EDC3758D8
function f0() {
    const v2 = -Infinity;
    try {
    const t0 = "boolean";
    t0.__proto__ = "boolean";
    } catch (e) {}
    new BigInt64Array(123);
    const v8 = {
        [v2]: "boolean",
        ..."boolean",
        set f(a7) {
        },
    };
}
f0();
const v10 = f0();
f0();
let v17 = "8";
const v18 = class {
    a = -65535;
    static set a(a20) {
        let v19 = this;
        ({"c":v17,"e":v19,"h":a20,} = v19);
        SharedArrayBuffer();
    }
    [-14392n];
    static [16n] = -14392n;
    static [1000000000.0] = -65535;
    h = v10;
    65537 = -3n;
}
new v18();
new v18();
const v25 = /a||bc/yvsgm;
const v26 = /[B]/dimu;
let v27 = /Y1+/ysgmu;
v27 *= v26;
try { v17(v17); } catch (e) {}
Object.defineProperty(v26, "source", { configurable: true, value: v26 });
const v29 = new v18();
v25[v29];
// Program is interesting due to new coverage: 26 newly discovered edges in the CFG of the target
