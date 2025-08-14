function bufferIO() {
  // Buffer-based I/O operations
  let path = '/tmp/buffer.txt';
  let buffer = Buffer.from('binary data', 'utf8');
  fs.writeFileSync(path, buffer);
  let result = fs.readFileSync(path);
  fs.unlinkSync(path);
}
bufferIO();