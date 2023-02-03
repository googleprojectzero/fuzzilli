if (typeof output === 'undefined') output = console.log;

function foo() {
    output(v1);
    var v1 = 42;
    output(v1);

    output(v2);
    do {
        var v2 = 43;
        output(v2);
    } while(false);
    output(v2);

    let v3 = 44;
    function bar() {
        // TODO the following doesn't currently work.
        //output(v3);
        //v3 = 45;
        //output(v3);
        var v3 = 46;
        output(v3);
        v3 = 47;
        output(v3);
    }
    bar();
    output(v3);
}
foo();
