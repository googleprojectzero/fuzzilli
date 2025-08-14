function vecStuff() {
  // Vector I/O operations (readv/writev)
  let fd = fs.openSync('/tmp/vector.txt', 'w+');
  fs.writevSync(fd, [Buffer.from('part1'), Buffer.from('part2')]);
  let buf1 = Buffer.alloc(5);
  let buf2 = Buffer.alloc(5);
  fs.readvSync(fd, [buf1, buf2], 0);
  fs.closeSync(fd);
  fs.unlinkSync('/tmp/vector.txt');
}
vecStuff();