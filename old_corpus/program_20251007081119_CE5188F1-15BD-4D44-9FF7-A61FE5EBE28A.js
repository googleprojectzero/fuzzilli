// Minimizing 51FA716B-F995-4CFE-A69C-FE3E4EC72FAA
function f0() {
    const t2 = 16;
    let v2 = t2();
    const v5 = {
        next() {
            v2--;
            return this;
        },
    };
    return f0;
}
try { f0(); } catch (e) {}
// Program is interesting due to new coverage: 1 newly discovered edge in the CFG of the target
