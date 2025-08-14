function fd() {
  // File descriptor operations
  let fd = fs.openSync('/tmp/fd-test.txt', 'w+');
  fs.writeSync(fd, 'test data');
  let stats = fs.fstatSync(fd);
  fs.closeSync(fd);
}

fd();
