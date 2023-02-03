if (typeof output === 'undefined') output = console.log;

let s = "abc\ndef\nghi";
output(s);

s = "abc\
def\
ghi";
output(s);

s = "abc" +
"def" +
"ghi";
output(s);

// TODO support template literals and add more tests for them
/*
s = `abc
def
ghi`;
output(s);
*/
