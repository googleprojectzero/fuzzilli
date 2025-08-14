// Promises-based filesystem API testing
// Tests async operations that could reveal race conditions or memory issues

async function runPromiseTests() {
  try {
    // Test bundle access via promises
    let bundleStat = await fs.promises.stat('/bundle');
    console.log('Async bundle stat:', bundleStat.isDirectory());

    let bundleFiles = await fs.promises.readdir('/bundle');
    console.log('Async bundle files:', bundleFiles.length);

    // Test reading bundle files asynchronously
    if (bundleFiles.length > 0) {
      let firstFile = bundleFiles[0];
      let content = await fs.promises.readFile(`/bundle/${firstFile}`);
      console.log('Async bundle file size:', content.length);
    }

    // Test temp directory operations with promises
    await fs.promises.mkdir('/tmp/async-test', { recursive: true });
    await fs.promises.writeFile('/tmp/async-test/data.bin', Buffer.from('Binary data test'));

    let tempStat = await fs.promises.stat('/tmp/async-test/data.bin');
    console.log('Async temp file size:', tempStat.size);

    // Test FileHandle operations (potential for fd leaks/corruption)
    let fileHandle = await fs.promises.open('/tmp/async-test/data.bin', 'r+');
    console.log('FileHandle fd:', fileHandle.fd);

    let handleStat = await fileHandle.stat();
    console.log('FileHandle stat size:', handleStat.size);

    let readBuffer = Buffer.alloc(20);
    let readResult = await fileHandle.read(readBuffer, 0, 10, 0);
    console.log('FileHandle read bytes:', readResult.bytesRead);

    let writeBuffer = Buffer.from('ASYNC');
    let writeResult = await fileHandle.write(writeBuffer, 0, writeBuffer.length, handleStat.size);
    console.log('FileHandle wrote bytes:', writeResult.bytesWritten);

    await fileHandle.close();
    console.log('FileHandle closed');

    // Test concurrent async operations (stress test)
    let promises = [];
    for (let i = 0; i < 3; i++) {
      promises.push(
        fs.promises.writeFile(`/tmp/async-test/concurrent-${i}.txt`, `Concurrent data ${i}`)
      );
    }
    
    await Promise.all(promises);
    console.log('Concurrent writes completed');

    // Test concurrent reads
    let readPromises = [];
    for (let i = 0; i < 3; i++) {
      readPromises.push(
        fs.promises.readFile(`/tmp/async-test/concurrent-${i}.txt`, 'utf8')
      );
    }
    
    let results = await Promise.all(readPromises);
    console.log('Concurrent reads completed:', results.length);

    // Test error handling with promises
    try {
      await fs.promises.readFile('/bundle/nonexistent-async-file');
    } catch (e) {
      console.log('Async error handled:', e.code);
    }

    // Cleanup
    for (let i = 0; i < 3; i++) {
      await fs.promises.unlink(`/tmp/async-test/concurrent-${i}.txt`);
    }
    await fs.promises.unlink('/tmp/async-test/data.bin');
    await fs.promises.rmdir('/tmp/async-test');

  } catch (error) {
    console.error('Promise test error:', error.message);
  }
}

// Execute the async tests
await runPromiseTests();
console.log('Promise API tests completed');