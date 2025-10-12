// Minimizing D9A3D86E-7F7A-4642-8DCB-077434628251
function f0() {
}
function f1() {
    const v8 = {
        e: f0,
        __proto__: f0,
        ...f0,
        f: f0,
        6: f0,
        set b(a3) {
            let v4 = super[f0];
            v4 &&= a3;
        },
        ...f0,
    };
    return v8;
}
f1();
const v10 = f1();
f1();
[2];
[-430481039,9007199254740991,536870889,-10,1073741823,4,-6,4294967297,9007199254740990,10];
[-12,-28134];
new Int32Array(723);
new Int32Array(4);
new Float64Array(1078);
new Proxy(v10, { deleteProperty: f0 });
let v27 = 0;
while (v27 < 5) {
    for (let v30 = 0; v30 < 100; v30++) {
        f0();
    }
    v27++;
}
// Program is interesting due to new coverage: 4766 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 667 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 4433 newly discovered edges in the CFG of the target
