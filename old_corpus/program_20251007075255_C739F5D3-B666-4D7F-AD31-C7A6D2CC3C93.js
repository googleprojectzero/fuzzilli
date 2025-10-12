// Minimizing 48B36A80-D253-4688-BAFF-D294AB0D4D29
function F0() {
    if (!new.target) { throw 'must be called with new'; }
    this.a = 268435440;
    this.f = 268435440;
}
new F0();
const v4 = new F0();
const v5 = new F0();
const v6 = v5?.constructor;
try { new v6(); } catch (e) {}
const v10 = new Uint16Array(3212);
try { v10.indexOf(v4); } catch (e) {}
new Int8Array(1);
3 % 3;
new Float64Array(3);
-536870912;
const v23 = [-1073741824,476388605,536870912];
const v24 = [v23,536870912,v23];
let v25 = 1073741824n;
v25--;
const v29 = {};
Float32Array.d = Float32Array;
new Float32Array();
function f34() {
}
f34.name = f34;
function f35() {
    const v39 = {
        ...f34,
        f: f34,
        6: f34,
        set b(a37) {
        },
    };
    v39[6];
    return v39;
}
f35();
const v42 = f35();
const v43 = [-430481039,9007199254740991,536870889,-10,1073741823,4,-6,4294967297,9007199254740990,10];
[-12,-28134];
try { v25.call(v24, 1849); } catch (e) {}
Symbol.e = Symbol;
Math[Symbol.iterator] = v43;
try { new Int32Array(Symbol, Int32Array, v42); } catch (e) {}
new Int32Array(723);
new Int32Array(4);
new Float64Array(1078);
const v61 = new Proxy(f35, { deleteProperty: f34 });
v61.d = v61;
let v62 = 0;
while ((() => {
        const v64 = v62 < 5;
        v64 && v64;
        return v64;
    })()) {
    for (let v66 = 0; v66 < 100; v66++) {
        v66 >>> v66;
        const v68 = f34();
        v68 ?? v68;
    }
    v62++;
}
// Program is interesting due to new coverage: 64 newly discovered edges in the CFG of the target
