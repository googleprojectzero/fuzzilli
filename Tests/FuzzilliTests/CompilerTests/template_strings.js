if (typeof output === 'undefined') output = console.log;

output(`simple template string`);

output(`template ${"string"} with ${2} interleaved expressions`);

output(`${`nested template string`}`);

output(`${'template string'} with one part surrounded by ${'two expressions'}`);

output(`template \t string \\ with \n escape \" sequences`);
