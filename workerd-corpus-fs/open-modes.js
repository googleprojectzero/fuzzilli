function modes() {

    // Different open modes
    let fd;
    try {
        fd = fs.openSync('/tmp/modes.txt', 'r+');
    } catch (e) {
        fd = fs.openSync('/tmp/modes.txt', 'w+');
    }
    fs.writeSync(fd, 'mode test');
    fs.closeSync(fd);
    fs.unlinkSync('/tmp/modes.txt');
}
modes();