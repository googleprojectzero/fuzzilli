// Minimizing 01EA2959-3BA4-4F02-8496-77482CB0D3BD
function F0() {
    if (!new.target) { throw 'must be called with new'; }
}
const v2 = new F0();
const v3 = new F0();
const v4 = new F0();
const v5 = class {
    static get b() {
    }
}
const v7 = new v5();
const v8 = new v5();
function F9(a11, a12, a13) {
    if (!new.target) { throw 'must be called with new'; }
    this.b = a12;
}
new F9(v4, v8);
new F9(v2, v7);
new F9(v5, v3);
const v18 = new BigUint64Array();
const v21 = new BigInt64Array(1000);
try {
    v21.some(v21);
} catch(e23) {
}
v18.__proto__;
delete v8.f;
BigInt64Array++;
~1000;
// Program is interesting due to new coverage: 902 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 155 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 159 newly discovered edges in the CFG of the target
