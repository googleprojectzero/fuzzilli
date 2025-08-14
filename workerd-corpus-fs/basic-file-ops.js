// Basic file operations
function basicOps() {
  let path = '/tmp/test.txt';
  let content = 'Hello World';
  fs.writeFileSync(path, content);
  fs.readFileSync(path);
  fs.existsSync(path);
  fs.unlinkSync(path);
}

basicOps();