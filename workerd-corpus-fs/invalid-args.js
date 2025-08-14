function testInv() {
    fs.writeFileSync(null, 'data');
    fs.readSync(123, Buffer.alloc(10), -1);
    fs.truncateSync('/tmp/test.txt', -5);
}
testInv();