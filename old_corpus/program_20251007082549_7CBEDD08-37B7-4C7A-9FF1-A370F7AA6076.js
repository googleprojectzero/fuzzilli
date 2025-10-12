// Minimizing 2C7786C3-6D7C-4AF8-9FE0-1815C7A3E953
function f0() {
    return f0;
}
const v1 = [f0,f0];
const v2 = { ...v1 };
// Program is interesting due to new coverage: 6 newly discovered edges in the CFG of the target
