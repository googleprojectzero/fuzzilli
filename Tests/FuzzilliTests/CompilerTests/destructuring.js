if (typeof output === 'undefined') output = console.log;

let obj = { x: 1, y: 2 };
let { x, y } = obj;
output(x);
output(y);

let [a, b] = [3, 4];
output(a);
output(b);

const { z, ...restObj } = { z: 5, w: 6, v: 7 };
output(z);
output(restObj.w);
output(restObj.v);

const [c, ...restArr] = [8, 9, 10];
output(c);
output(restArr[0]);
output(restArr[1]);

let [d, , e] = [11, 12, 13];
output(d);
output(e);

var f = 14;
var { f, g } = { f: 15, g: 16 };
output(f);
output(g);

var h = 17;
var [h, i] = [18, 19];
output(h);
output(i);
