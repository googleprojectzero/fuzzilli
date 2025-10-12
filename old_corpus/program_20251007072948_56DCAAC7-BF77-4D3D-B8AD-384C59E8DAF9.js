// Minimizing 2B4A9B9B-F149-4BD1-A0D1-EF34EA3B7010
Object.defineProperty(Date, "toTemporalInstant", { writable: true, configurable: true, value: "Z" });
class C2 extends Date {
}
Date.toTemporalInstant = Date;
// Program is interesting due to new coverage: 3 newly discovered edges in the CFG of the target
