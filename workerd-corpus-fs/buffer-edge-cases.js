// Buffer edge cases
function bufferTest() {
    let path = '/tmp/buf-edge.txt';
    let fd = fs.openSync(path, 'w+');

    try {
        fs.writeSync(fd, Buffer.alloc(0));
        fs.writeSync(fd, Buffer.alloc(1, 255));
    } catch (e) { }

    fs.closeSync(fd);
    fs.unlinkSync(path);
    fs.unlinkSync(path);
    fs.unlinkSync(path);
    fs.unlinkSync(path);
}

bufferTest();

