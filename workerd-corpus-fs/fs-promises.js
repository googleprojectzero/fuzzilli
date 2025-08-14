function promises() {
  // fs.promises API
  let path = '/tmp/promise.txt';
  fs.promises.writeFile(path, 'promise data')
    .then(() => fs.promises.readFile(path))
    .then(() => fs.promises.unlink(path))
    .catch(() => { });
}

promises();