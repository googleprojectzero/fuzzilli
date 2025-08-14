function statTest() {
  // Stat operations
  let path = '/tmp/stat.txt';
  fs.writeFileSync(path, 'test');
  let stats = fs.statSync(path);
  stats.isFile();
  stats.isDirectory();
  fs.unlinkSync(path);
}
statTest();