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

s = `abc
def
ghi`;
output(s);
