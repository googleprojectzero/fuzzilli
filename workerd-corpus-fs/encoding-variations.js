function encoding() {
  // Different encoding variations
  let path = '/tmp/encoding.txt';
  fs.writeFileSync(path, 'café', 'utf8');
  fs.readFileSync(path, 'utf8');
  fs.writeFileSync(path, Buffer.from([0x42, 0x43]));
  fs.readFileSync(path);
  fs.unlinkSync(path);
}