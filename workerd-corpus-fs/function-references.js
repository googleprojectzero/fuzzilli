function refs() {
  // Function reference variations
  let writeFile = fs.writeFileSync;
  let readFile = fs.readFileSync;
  let deleteFile = fs.unlinkSync;

  let path = '/tmp/ref.txt';
  writeFile(path, 'function ref test');
  readFile(path);
  deleteFile(path);
}
refs();
