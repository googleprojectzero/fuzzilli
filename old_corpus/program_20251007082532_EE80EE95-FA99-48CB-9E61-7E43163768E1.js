// Minimizing 828C290A-2BF0-4C6B-9E66-821F17BA4F3A
class C0 {
    constructor(a2, a3) {
        this[1094839906] = a3;
        try {
            super.getInt8();
        } catch(e5) {
        }
    }
}
const v6 = new C0();
const v7 = new C0(v6, v6);
const v8 = new C0(v7, v7);
class C9 extends C0 {
}
const v10 = new C9();
const v11 = new C9();
const v12 = new C9();
const v13 = class {
    constructor(a15, a16, a17, a18) {
        new C9();
    }
}
new v13(v8, v7, v12, v10);
new v13(v12, v8, v7, v12);
new v13(C0, C9, v10, v11);
// Program is interesting due to new coverage: 12 newly discovered edges in the CFG of the target
