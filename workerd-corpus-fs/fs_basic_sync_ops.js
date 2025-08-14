// Basic synchronous filesystem operations targeting FileSystemModule C++ API
// Focus on stat, readdir, readFile operations with bundle and temp directories

// Test basic stat operations on bundle directory (potential OOB reads)
let bundleStat = fs.statSync('/bundle');
console.log('Bundle is directory:', bundleStat.isDirectory());

// Test readdir on bundle directory - critical for memory safety
let bundleFiles = fs.readdirSync('/bundle');
console.log('Bundle files count:', bundleFiles.length);

// Test reading bundle files with potential for OOB reads
if (bundleFiles.length > 0) {
  let firstFile = bundleFiles[0];
  let content = fs.readFileSync(`/bundle/${firstFile}`);
  console.log('First bundle file size:', content.length);
  
  // Test with different read positions and sizes
  if (content.length > 10) {
    let partial = fs.readFileSync(`/bundle/${firstFile}`, { encoding: 'utf8' });
    console.log('Content type:', typeof partial);
  }
}

// Test temp directory operations
fs.mkdirSync('/tmp/fuzz-test', { recursive: true });
fs.writeFileSync('/tmp/fuzz-test/data.txt', 'Hello Fuzzer!');

let tempStat = fs.statSync('/tmp/fuzz-test/data.txt');
console.log('Temp file size:', tempStat.size);

let tempContent = fs.readFileSync('/tmp/fuzz-test/data.txt', 'utf8');
console.log('Temp content:', tempContent);

// Test file descriptor operations with potential for corruption
let fd = fs.openSync('/tmp/fuzz-test/data.txt', 'r+');
let fdStat = fs.fstatSync(fd);
console.log('FD stat size:', fdStat.size);

let buffer = Buffer.alloc(20);
let bytesRead = fs.readSync(fd, buffer, 0, 5, 0);
console.log('Bytes read via FD:', bytesRead);

fs.closeSync(fd);

// Cleanup
fs.unlinkSync('/tmp/fuzz-test/data.txt');
fs.rmdirSync('/tmp/fuzz-test');

console.log('Sync operations test completed');