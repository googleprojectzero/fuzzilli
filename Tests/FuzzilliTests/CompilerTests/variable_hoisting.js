if (typeof output === 'undefined') output = console.log;

function foo() {
    output(a);
    var a = 42;
    output(a);

    output(b);
    do {
        var b = 43;
        output(b);
    } while(false);
    output(b);

    let c = 44;
    function bar() {
        output(c);
        c = 45;
        output(c);
        var c = 46;
        output(c);
        c = 47;
        output(c);
    }
    bar();
    output(c);
}
foo();
