function renameAndCopy() {
  // Copy and rename operations
  let src = '/tmp/source.txt';
  let dst = '/tmp/dest.txt';
  fs.writeFileSync(src, 'data to copy');
  fs.copyFileSync(src, dst);
  fs.renameSync(dst, '/tmp/renamed.txt');
  fs.unlinkSync(src);
  fs.unlinkSync('/tmp/renamed.txt');
}
