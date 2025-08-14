// Buffer and binary data operations testing
// Focus on potential buffer overflows, OOB reads, and memory corruption

// Create various buffer sizes for testing
let smallBuffer = Buffer.alloc(10);
let mediumBuffer = Buffer.alloc(1024);
let largeBuffer = Buffer.alloc(64 * 1024); // 64KB

// Test writing different buffer sizes
fs.writeFileSync('/tmp/small-buffer.bin', smallBuffer);
fs.writeFileSync('/tmp/medium-buffer.bin', mediumBuffer);

// Fill buffers with test patterns
smallBuffer.fill(0xAA);
mediumBuffer.fill(0xBB);
largeBuffer.fill(0xCC);

fs.writeFileSync('/tmp/pattern-small.bin', smallBuffer);
fs.writeFileSync('/tmp/pattern-medium.bin', mediumBuffer);
fs.writeFileSync('/tmp/pattern-large.bin', largeBuffer);

// Test reading with various buffer configurations
let readBuffer = Buffer.alloc(100);

// Test reading more than file size
let smallContent = fs.readFileSync('/tmp/pattern-small.bin');
console.log('Small file size:', smallContent.length);

let fd = fs.openSync('/tmp/pattern-medium.bin', 'r');

// Test various read configurations that might trigger boundary errors
try {
  // Read at different offsets
  fs.readSync(fd, readBuffer, 0, 50, 0);    // Normal read
  fs.readSync(fd, readBuffer, 50, 50, 100); // Read from middle
  fs.readSync(fd, readBuffer, 0, 10, 1020); // Read near end
  
  // Test boundary conditions
  fs.readSync(fd, readBuffer, 0, 1, 1023);  // Last byte
  
  // Test reading beyond file end (should handle gracefully)
  try {
    fs.readSync(fd, readBuffer, 0, 100, 1000); // Beyond file
  } catch (e) {
    console.log('Beyond file read handled:', e.code);
  }
  
} catch (error) {
  console.log('Read operation error:', error.code);
}

fs.closeSync(fd);

// Test writing with buffer overruns and underruns
let writeBuffer = Buffer.from('Test data for write operations');
let writeFd = fs.openSync('/tmp/write-test.bin', 'w+');

// Test various write scenarios
try {
  fs.writeSync(writeFd, writeBuffer, 0, writeBuffer.length, 0);
  fs.writeSync(writeFd, writeBuffer, 0, 5, 100); // Write 5 bytes at offset 100
  
  // Test writing with buffer boundaries
  fs.writeSync(writeFd, writeBuffer, 10, 10, 50);
  
  // Test zero-length writes
  fs.writeSync(writeFd, writeBuffer, 0, 0, 200);
  
} catch (error) {
  console.log('Write operation error:', error.code);
}

// Test readv/writev operations (vectored I/O)
let vec1 = Buffer.from('Vector1');
let vec2 = Buffer.from('Vector2');
let vec3 = Buffer.from('Vector3');

try {
  let bytesWritten = fs.writevSync(writeFd, [vec1, vec2, vec3], 300);
  console.log('Vectored write bytes:', bytesWritten);
} catch (error) {
  console.log('Writev error:', error.code);
}

fs.closeSync(writeFd);

// Test reading back with readv
let readFd = fs.openSync('/tmp/write-test.bin', 'r');
let rvec1 = Buffer.alloc(7);
let rvec2 = Buffer.alloc(7);
let rvec3 = Buffer.alloc(7);

try {
  let bytesRead = fs.readvSync(readFd, [rvec1, rvec2, rvec3], 300);
  console.log('Vectored read bytes:', bytesRead);
  console.log('Read vectors:', rvec1.toString(), rvec2.toString(), rvec3.toString());
} catch (error) {
  console.log('Readv error:', error.code);
}

fs.closeSync(readFd);

// Test bundle file buffer operations (potential OOB reads)
let bundleFiles = fs.readdirSync('/bundle');
if (bundleFiles.length > 0) {
  let bundleFile = bundleFiles[0];
  let bundleContent = fs.readFileSync(`/bundle/${bundleFile}`);
  
  if (bundleContent.length > 0) {
    // Test reading bundle content with different buffer sizes
    let bundleFd = fs.openSync(`/bundle/${bundleFile}`, 'r');
    let tinyBuffer = Buffer.alloc(1);
    let exactBuffer = Buffer.alloc(bundleContent.length);
    let oversizedBuffer = Buffer.alloc(bundleContent.length + 100);
    
    // Test reading with exact size
    try {
      fs.readSync(bundleFd, exactBuffer, 0, bundleContent.length, 0);
      console.log('Exact buffer read successful');
    } catch (e) {
      console.log('Exact buffer read error:', e.code);
    }
    
    // Test reading with oversized buffer (check for OOB)
    try {
      let bytesRead = fs.readSync(bundleFd, oversizedBuffer, 0, oversizedBuffer.length, 0);
      console.log('Oversized buffer read bytes:', bytesRead);
    } catch (e) {
      console.log('Oversized buffer read error:', e.code);
    }
    
    fs.closeSync(bundleFd);
  }
}

// Test TypedArray operations
let uint8Array = new Uint8Array(50);
let uint16Array = new Uint16Array(25);
let uint32Array = new Uint32Array(12);

fs.writeFileSync('/tmp/uint8.bin', uint8Array);
fs.writeFileSync('/tmp/uint16.bin', uint16Array);
fs.writeFileSync('/tmp/uint32.bin', uint32Array);

// Test reading into TypedArrays
let readArray = new Uint8Array(100);
let arrayFd = fs.openSync('/tmp/uint8.bin', 'r');

try {
  let arrayBytesRead = fs.readSync(arrayFd, readArray, 0, readArray.length, 0);
  console.log('TypedArray read bytes:', arrayBytesRead);
} catch (error) {
  console.log('TypedArray read error:', error.code);
}

fs.closeSync(arrayFd);

// Cleanup
let cleanupFiles = [
  '/tmp/small-buffer.bin', '/tmp/medium-buffer.bin',
  '/tmp/pattern-small.bin', '/tmp/pattern-medium.bin', '/tmp/pattern-large.bin',
  '/tmp/write-test.bin', '/tmp/uint8.bin', '/tmp/uint16.bin', '/tmp/uint32.bin'
];

for (let file of cleanupFiles) {
  try {
    fs.unlinkSync(file);
  } catch (e) {
    console.log(`Cleanup error for ${file}:`, e.code);
  }
}

console.log('Buffer operations testing completed');