// Minimizing CAB0017A-D9D8-4BB5-9AD3-6D8F54C6A072
const v1 = class {
    constructor(a3) {
        this[1073741824] = 1000.0;
    }
}
class C4 extends v1 {
}
const v5 = new C4();
v5[1073741824] = v5;
// Program is interesting due to new coverage: 6 newly discovered edges in the CFG of the target
