function largeBuf() {
  // Large buffer operations
  let path = '/tmp/large.txt';
  let large = Buffer.alloc(1024, 65);
  fs.writeFileSync(path, large);
  let result = fs.readFileSync(path);
  fs.unlinkSync(path);
}
largeBuf();