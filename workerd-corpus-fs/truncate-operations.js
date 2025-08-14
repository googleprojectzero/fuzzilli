

// Truncate operations
function trunc() {
  let path = '/tmp/truncate.txt';
  fs.writeFileSync(path, 'long content string');
  fs.truncateSync(path, 5);
  fs.unlinkSync(path);
}

trunc();
