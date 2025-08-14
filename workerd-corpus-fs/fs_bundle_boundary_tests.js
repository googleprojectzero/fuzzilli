// Bundle file boundary testing - specifically targeting potential OOB reads
// Tests edge cases around bundle file access that could trigger memory corruption

// Test bundle directory traversal
let bundleEntries = fs.readdirSync('/bundle', { recursive: true });
console.log('Total bundle entries:', bundleEntries.length);

// Test accessing bundle files with various path patterns
for (let entry of bundleEntries.slice(0, 3)) {
  try {
    let fullPath = `/bundle/${entry}`;
    let stat = fs.statSync(fullPath);
    
    if (stat.isFile()) {
      // Test reading at different positions to stress boundary conditions
      let content = fs.readFileSync(fullPath);
      console.log(`Bundle file ${entry} size:`, content.length);
      
      // Test partial reads that might trigger OOB
      if (content.length > 0) {
        let fd = fs.openSync(fullPath, 'r');
        let smallBuffer = Buffer.alloc(1);
        let largeBuffer = Buffer.alloc(content.length + 100); // Intentionally oversized
        
        // Read at boundary positions
        fs.readSync(fd, smallBuffer, 0, 1, 0); // First byte
        if (content.length > 1) {
          fs.readSync(fd, smallBuffer, 0, 1, content.length - 1); // Last byte
        }
        
        // Test reading more than available (should be safe but test boundary)
        try {
          fs.readSync(fd, largeBuffer, 0, largeBuffer.length, 0);
        } catch (e) {
          console.log('Expected boundary error:', e.code);
        }
        
        fs.closeSync(fd);
      }
    }
  } catch (error) {
    console.log(`Error accessing ${entry}:`, error.code);
  }
}

// Test invalid bundle paths (should fail gracefully)
try {
  fs.readFileSync('/bundle/../../../etc/passwd');
} catch (e) {
  console.log('Path traversal blocked:', e.code);
}

try {
  fs.readFileSync('/bundle/nonexistent-file-xyz');
} catch (e) {
  console.log('Nonexistent file handled:', e.code);
}

// Test bundle file with null bytes and special chars
try {
  fs.readFileSync('/bundle/test\0file');
} catch (e) {
  console.log('Null byte path handled:', e.code);
}

console.log('Bundle boundary tests completed');