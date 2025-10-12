// Minimizing 64B21C15-7AA5-4C81-86BE-D8EBF21D7263
Object.defineProperty(Date, Symbol.toPrimitive, { writable: true, value: Date });
class C3 extends Date {
    constructor(a5, a6) {
        super(a6, Date);
    }
}
new C3();
// Program is interesting due to new coverage: 5 newly discovered edges in the CFG of the target
