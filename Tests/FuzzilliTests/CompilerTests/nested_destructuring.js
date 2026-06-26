if (typeof output === 'undefined') output = console.log;

// Basic & Shorthand (Declaration)
let { a, b } = { a: 1, b: 2 };
output(a, b);

// Basic & Shorthand (Reassignment)
let r_a, r_b;
({ a: r_a, b: r_b } = { a: 1, b: 2 });
output(r_a, r_b);

// Aliasing (Renaming) (Declaration)
let { c: charlie } = { c: 3 };
output(charlie);

// Aliasing (Renaming) (Reassignment)
let r_charlie;
({ c: r_charlie } = { c: 3 });
output(r_charlie);

// Default Values (Declaration)
let { d = 4, e = 5, f = 6 } = { d: undefined, e: null, f: false };
output(d, e, f);

// Default Values (Reassignment)
let r_d, r_e, r_f;
({ d: r_d = 4, e: r_e = 5, f: r_f = 6 } = { d: undefined, e: null, f: false });
output(r_d, r_e, r_f);

// Aliasing + Default Values (Declaration)
let { g: renamedG = 7 } = {};
output(renamedG);

// Aliasing + Default Values (Reassignment)
let r_renamedG;
({ g: r_renamedG = 7 } = {});
output(r_renamedG);

// Computed Property Names (Declaration)
const dynKey = "dynamic";
let { [dynKey]: h, ["comp" + "uted"]: i } = { dynamic: 8, computed: 9 };
output(h, i);

// Computed Property Names (Reassignment)
let r_h, r_i;
({ [dynKey]: r_h, ["comp" + "uted"]: r_i } = { dynamic: 8, computed: 9 });
output(r_h, r_i);

// Computed Property + Alias + Default (Declaration)
let { ["missing" + "Key"]: j = 10 } = {};
output(j);

// Computed Property + Alias + Default (Reassignment)
let r_j;
({ ["missing" + "Key"]: r_j = 10 } = {});
output(r_j);

// Rest Properties (Declaration)
let { k, ...restProps } = { k: 11, l: 12, m: 13 };
output(k, restProps.l, restProps.m);

// Rest Properties (Reassignment)
let r_k, r_restProps;
({ k: r_k, ...r_restProps } = { k: 11, l: 12, m: 13 });
output(r_k, r_restProps.l, r_restProps.m);

// Deep / Nested Object Destructuring (Declaration)
let { user: { profile: { id } } } = { user: { profile: { id: 14 } } };
output(id);

// Deep / Nested Object Destructuring (Reassignment)
let r_id;
({ user: { profile: { id: r_id } } } = { user: { profile: { id: 14 } } });
output(r_id);

// Missing Properties (Declaration)
let { missingProp } = { present: true };
output(missingProp);

// Missing Properties (Reassignment)
let r_missingProp;
({ missingProp: r_missingProp } = { present: true });
output(r_missingProp);

// Empty Object Pattern (Declaration)
let { } = { x: 15 };

// Empty Object Pattern (Reassignment)
({} = { x: 15 });

// Destructuring Primitives (Declaration)
let { length, toUpperCase } = "hello";
output(length, typeof toUpperCase);

// Destructuring Primitives (Reassignment)
let r_length, r_toUpperCase;
({ length: r_length, toUpperCase: r_toUpperCase } = "hello");
output(r_length, typeof r_toUpperCase);

// JSON-style Objects (Declaration)
const parsedJSON = JSON.parse('{"first-name": "Alice", "status": 200}');
let { "first-name": firstName, status } = parsedJSON;
output(firstName, status);

// JSON-style Objects (Reassignment)
let r_firstName, r_status;
({ "first-name": r_firstName, status: r_status } = parsedJSON);
output(r_firstName, r_status);

// Basic Non-nested (Declaration)
let [first, second] = [10, 20];
output(second);

// Basic Non-nested (Reassignment)
let r_first, r_second;
[r_first, r_second] = [10, 20];
output(r_second);

// Elision (Declaration)
let [a2, , b2, , , c2] = [1, 2, 3, 4, 5, 6];
output(b2, c2);

// Elision (Reassignment)
let r_a2, r_b2, r_c2;
[r_a2, , r_b2, , , r_c2] = [1, 2, 3, 4, 5, 6];
output(r_b2, r_c2);

// Trailing Elision (Declaration)
let [d2, e2, , f3] = [7, 8, 9, 10];
output(e2, f3);

// Trailing Elision (Reassignment)
let r_d2, r_e2, r_f3;
[r_d2, r_e2, , r_f3] = [7, 8, 9, 10];
output(r_e2, r_f3);

// Default Values (Array) (Declaration)
let [f2 = 100, g2 = 200] = [undefined, null];
output(f2, g2);

// Default Values (Array) (Reassignment)
let r_f2, r_g2;
[r_f2 = 100, r_g2 = 200] = [undefined, null];
output(r_f2, r_g2);

// Rest Elements (Declaration)
let [head, ...tail] = [1, 2, 3, 4];
output(tail[0], tail[1], tail[2], tail.length);

// Rest Elements (Reassignment)
let r_head, r_tail;
[r_head, ...r_tail] = [1, 2, 3, 4];
output(r_tail[0], r_tail[1], r_tail[2], r_tail.length);

// Nested Array Destructuring (Declaration)
let [x, [y, z]] = [1, [2, 3]];
output(z);

// Nested Array Destructuring (Reassignment)
let r_x, r_y, r_z;
[r_x, [r_y, r_z]] = [1, [2, 3]];
output(r_z);

// Rest Elements as a Pattern (Declaration)
let [start, ...[...restUnpacked]] = [10, 20, 30];
output(restUnpacked[0], restUnpacked[1], restUnpacked.length);

// Rest Elements as a Pattern (Reassignment)
let r_start, r_restUnpacked;
[r_start, ...[...r_restUnpacked]] = [10, 20, 30];
output(r_restUnpacked[0], r_restUnpacked[1], r_restUnpacked.length);

// Array Rest resolving into an Object pattern (Declaration)
let [n, ...{ length: len, 0: p }] = [37, 38, 39];
output(n, len, p);

// Array Rest resolving into an Object pattern (Reassignment)
let r_n, r_len, r_p;
[r_n, ...{ length: r_len, 0: r_p }] = [37, 38, 39];
output(r_n, r_len, r_p);

// Works on ANY Iterable (Declaration)
const mySet = new Set([88, 99]);
let [setFirst] = mySet;
output(setFirst);

// Works on ANY Iterable (Reassignment)
let r_setFirst;
[r_setFirst] = mySet;
output(r_setFirst);

// Object inside Array (Declaration)
let [{ id: id1 }, { id: id2 = "default" }] = [{ id: 1 }, {}];
output(id2);

// Object inside Array (Reassignment)
let r_id1, r_id2;
[{ id: r_id1 }, { id: r_id2 = "default" }] = [{ id: 1 }, {}];
output(r_id2);

// Array inside Object (Declaration)
let { coords: [x2, y2] } = { coords: [45.5, -122.6] };
output(y2);

// Array inside Object (Reassignment)
let r_x2, r_y2;
({ coords: [r_x2, r_y2] } = { coords: [45.5, -122.6] });
output(r_y2);

// Deeply mixed (Declaration)
let [, { tags: [, secondTag, ...otherTags], status: status2 = "active" }] = [
    { tags: ["ignore"] },
    { tags: ["js", "web", "node"] }
];
output(secondTag, status2, otherTags[0]);

// Deeply mixed (Reassignment)
let r_secondTag, r_otherTags, r_status2;
[, { tags: [, r_secondTag, ...r_otherTags], status: r_status2 = "active" }] = [
    { tags: ["ignore"] },
    { tags: ["js", "web", "node"] }
];
output(r_secondTag, r_status2, r_otherTags[0]);

// Rest properties with aliasing and defaults (Declaration)
let { j2 = 10, k2: renamedK2, ...restProps2 } = { k2: 11, l: 12, m: 13 };
output(j2, renamedK2, restProps2.l, restProps2.m);

// Rest properties with aliasing and defaults (Reassignment)
let r_j2, r_renamedK2, r_restProps2;
({ j2: r_j2 = 10, k2: r_renamedK2, ...r_restProps2 } = { k2: 11, l: 12, m: 13 });
output(r_j2, r_renamedK2, r_restProps2.l, r_restProps2.m);

// Multiple nested rest elements, defaults, and aliasing (Declaration)
let { user2: { profile2: { id: I, ...rest1 }, type = 0, ...rest2 } } = { user2: { profile2: { id: 14, name: "foo" }, active: false } };
output(I, type, rest1.name, rest2.active);

// Multiple nested rest elements, defaults, and aliasing (Reassignment)
let r_I, r_rest1, r_type, r_rest2;
({ user2: { profile2: { id: r_I, ...r_rest1 }, type: r_type = 0, ...r_rest2 } } = { user2: { profile2: { id: 14, name: "foo" }, active: false } });
output(r_I, r_type, r_rest1.name, r_rest2.active);

// Elision + rest (Declaration)
let [head2, , ...tail2] = [1, 2, 3, 4];
output(tail2[0], tail2[1]);

// Elision + rest (Reassignment)
let r_head2, r_tail2;
[r_head2, , ...r_tail2] = [1, 2, 3, 4];
output(r_tail2[0], r_tail2[1]);

// MemberExpression in array destructuring
let m_a = {};
[m_a.b] = [1];
output(m_a.b);

// MemberExpression in array destructuring rest
let m_arr = {};
[...m_arr.prop] = [1, 2];
output(m_arr.prop[0], m_arr.prop[1]);

// SuperMemberExpression in array destructuring
class A_super {
  get a() { return this._a; }
  set a(v) { this._a = v; }
}
class B_super extends A_super {
  m() {
    [...super.a] = [1, 2];
    output(super.a[0], super.a[1]);
  }
}
new B_super().m();

// MemberExpression in object destructuring
let o_obj = {};
({ key: o_obj.prop } = { key: 42 });
output(o_obj.prop);

// Destructuring reassignment with MemberExpression and SuperProperty
let obj = { x: 10, y: 20 };
let arr = [30, 40];
let targetObj = {};
let targetArr = [];
let prop = "dynamic";

class Parent {}
class Child extends Parent {
    test() {
        // Test .superProperty and .superElement
        ({ x: super.parentProp } = obj);
        ([super[0]] = arr);
        output(this.parentProp);
        output(this[0]);
    }
    testComputed() {
        ({ x: super[prop] } = obj);
        output(this[prop]);
    }
}

// Test .property
({ x: targetObj.prop1 } = obj);
output(targetObj.prop1);

// Test .computedProperty
({ y: targetObj[prop] } = obj);
output(targetObj.dynamic);

// Test .element
([targetArr[0]] = arr);
output(targetArr[0]);

let c = new Child();
c.test();
c.testComputed();

// Also test array target pattern (nested destructuring reassignment)
let nestedTarget = {};
({ a: { b: nestedTarget.b } } = { a: { b: 100 } });
output(nestedTarget.b);
