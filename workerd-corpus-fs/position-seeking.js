function seeking() {
  // Position-based operations
  let fd = fs.openSync('/tmp/pos.txt', 'w+');
  fs.writeSync(fd, 'ABCDEFGHIJ');
  let buf = Buffer.alloc(3);
  fs.readSync(fd, buf, 0, 3, 2);
  fs.closeSync(fd);
  fs.unlinkSync('/tmp/pos.txt');
}
seeking();