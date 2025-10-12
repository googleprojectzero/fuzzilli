// Minimizing 590F6A5E-F83D-4F2C-9453-1A4564F6BEA8
function f0() {
    return f0;
}
const v3 = new Proxy(f0, {});
v3.name = v3;
// Program is interesting due to new coverage: 3 newly discovered edges in the CFG of the target
