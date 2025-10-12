// Minimizing 75F9BDA6-C6B8-4C0E-BC1B-0DED506015E1
function f1() {
    return ([f1,f1,f1,f1,f1]).toSorted(127n);
}
try { f1(); } catch (e) {}
// Program is interesting due to new coverage: 34 newly discovered edges in the CFG of the target
