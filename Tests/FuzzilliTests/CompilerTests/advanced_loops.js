var foo = 0
console.log(foo)
// ------------------ Plain For-of loops ------------------
for (const a of ["a"]) {}
for (let b of ["b"]) {}
for (var c of ["c"]) {}
for (d of ["d"]) {}

try {foo = a }
catch (err) { console.log("Test 1 successful");}
try {foo = b }
catch (err) { console.log("Test 2 successful");}
if (c === "c") console.log("Test 3 successful");
if (d === "d") console.log("Test 4 successful");

// --------------- Reassigning For-of loops ---------------

const e = "e";
let f = "f";
var g = "g";
h = "h";

try { for (e of ["e_new"]) {} } 
catch (err) { console.log("Test 5 successful");} // can not reassign const
for (f of ["f_new"]) {}
for (g of ["g_new"]) {}
for (h of ["h_new"]) {}

if (e == "e") console.log("Test 6 successful");
if (f == "f_new") console.log("Test 7 successful");
if (g == "g_new") console.log("Test 8 successful");
if (h == "h_new") console.log("Test 9 successful");

// ------------------ Plain For-in loops ------------------


for (const i in ["i"]) {}
for (let j in ["j"]) {}
for (var k in ["k"]) {}
for (l in ["l"]) {}

try {foo = i }
catch (err) { console.log("Test 10 successful");}
try {foo = j }
catch (err) { console.log("Test 11 successful");}
if (k === "0") console.log("Test 12 successful");
if (l === "0") console.log("Test 13 successful");

// --------------- Reassigning For-in loops ---------------

const m = "m";
let n = "n";
var o = "o";
p = "p";

try { for (m in ["m_new"]) {} } 
catch (err) { console.log("Test 14 successful");}
for (n in ["n_new"]) {}
for (o in ["o_new"]) {}
for (p in ["p_new"]) {}

if (m == "m") console.log("Test 15 successful");
if (n != "n") console.log("Test 16 successful");
if (o != "o") console.log("Test 17 successful");
if (p != "p") console.log("Test 18 successful");
