// Minimizing A974F694-E21B-4B63-8217-3F21B5BEACD4
const v0 = /UVja\n/ygiu;
const v1 = /\xed\xa0\x80((\xed\xb0\x80)\x01Ca\W?)?/ysiu;
const v2 = /Xx*/ysgimu;
class C3 {
    [v1];
}
new C3();
let v5 = 9223372036854775807;
v5 &= 10;
function F8(a10, a11, a12) {
    if (!new.target) { throw 'must be called with new'; }
    this.d = a12;
    this.e = C3;
}
new F8(10, v2, v5);
new F8(10, v0, 1073741824);
// Program is interesting due to new coverage: 10 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 24 newly discovered edges in the CFG of the target
// Imported program is interesting due to new coverage: 71 newly discovered edges in the CFG of the target
