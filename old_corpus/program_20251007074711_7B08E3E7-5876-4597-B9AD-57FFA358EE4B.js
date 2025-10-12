// Minimizing 1CF6CFEC-5C0B-4E7B-BB7E-74799473F684
const v1 = new Set();
const v3 = {
    __proto__: v1,
    next() {
        return Set;
    },
};
// Program is interesting due to new coverage: 7 newly discovered edges in the CFG of the target
