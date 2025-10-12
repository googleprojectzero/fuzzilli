if (typeof output === 'undefined') output = console.log;

const obj = { a: 1 };
console.log(delete obj.a);
console.log(obj);

const propName = 'b';
obj[propName] = 2;
console.log(delete obj[propName]);
console.log(obj);

const arr = [1, 2, 3];
console.log(delete arr[1]);
console.log(arr);

const index = 0;
console.log(delete arr[index]);
console.log(arr);

const nestedObj = { a: { b: 2 } };
console.log(delete nestedObj?.a?.b);
console.log(nestedObj);

try {
    delete null.a;
} catch(e) {
    console.log(e.message);
}
console.log(delete null?.a);