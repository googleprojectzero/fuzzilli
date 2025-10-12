// Minimizing EDAB3DE6-2EAC-4662-989D-B8C1990FBF82
function f1() {
    const v4 = {
        get e() {
            return this;
        },
        next() {
            return f1;
        },
    };
    return v4;
}
f1();
const v6 = f1();
function f7() {
    return v6;
}
function f8(a9) {
    const v14 = {
        toString(a11, a12, a13) {
            return a13;
        },
    };
    return a9;
}
let v15 = f8(f8);
const v16 = class {
    get d() {
    }
    static #f = v15;
}
let v18;
try { v18 = v16(); } catch (e) {}
const v19 = new v16();
({"d":f8,"h":v15,} = v19);
let v20;
try { v20 = v6.hasOwnProperty(v15, v15, f1, v19, f8); } catch (e) {}
!v20;
const v22 = [9007199254740990,-8,-2147483647,31588,64692,1073741823,65536,-44927];
try { v22.lastIndexOf(v22, v18); } catch (e) {}
const v24 = [2138507042,1051933470,45352,5,59081,-4096,-14];
v24[6] = v24;
function f26() {
    return false;
}
const v27 = {};
let v28 = 268435456;
v28++;
-1024 / -1024;
const v33 = new Int8Array();
const v34 = v33[532];
v34 >>> v34;
try { Float64Array(); } catch (e) {}
const v39 = new Float64Array();
const t54 = "+19:00";
t54[5] = "+19:00";
const v48 = {
    [v39](a43, a44, a45, a46) {
    },
    get g() {
        return v15;
    },
};
const v49 = new Int32Array(4294967295, v20, -1024);
class C50 {
    h = Int8Array;
    static [Int8Array];
    constructor(a52, a53) {
        this.propertyIsEnumerable(v33);
    }
    #n(a56) {
    }
}
const v57 = new C50();
const v58 = v57.h;
try { v58(f26, undefined, false); } catch (e) {}
const v60 = /foo(?=bar)bazc(a)X?/dgmu;
const v61 = v60.apply;
try { v61(f26, v60); } catch (e) {}
Symbol.e = Symbol;
Symbol.for(Symbol.description);
let v67;
try { v67 = new String(4294967295); } catch (e) {}
v67[2] = v67;
v49.buffer;
// Program is interesting due to new coverage: 264 newly discovered edges in the CFG of the target
