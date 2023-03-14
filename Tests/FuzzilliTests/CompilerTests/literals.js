if (typeof output === 'undefined') output = console.log;

output(42);
output(13.37);
output(123n);
output("a string literal");
output('another string literal');
output(`a template literal`);
output(/regex/gs);
output(true);
output(false);
output(null);
output(undefined);
