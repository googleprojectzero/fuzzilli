function ops() {
  // Multiple file descriptor operations
  let path = '/tmp/multi-fd.txt';
  fs.writeFileSync(path, 'test data');

  let fd1 = fs.openSync(path, 'r');
  let fd2 = fs.openSync(path, 'r');

  fs.readSync(fd1, Buffer.alloc(4), 0, 4, 0);
  fs.readSync(fd2, Buffer.alloc(4), 0, 4, 5);

  fs.closeSync(fd1);
  fs.closeSync(fd2);
  fs.unlinkSync(path);
}
