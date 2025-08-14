// Boundary conditions
function boundaryCond() {
  let path = '/tmp/boundary.txt';
  fs.writeFileSync(path, '');  // Empty file
  let fd = fs.openSync(path, 'r+');
  fs.ftruncateSync(fd, 0);
  fs.closeSync(fd);
  fs.unlinkSync(path);
}
boundaryCond();
