// Web File System API testing - FileSystemDirectoryHandle and FileSystemFileHandle
// Tests WHATWG spec implementation and potential memory corruption in handle operations

async function runWebFSTests() {
  try {
    // Test StorageManager API
    let rootDir = await navigator.storage.getDirectory();
    console.log('Root directory name:', rootDir.name);
    console.log('Root directory kind:', rootDir.kind);

    // Test bundle directory access
    let bundleDir = await rootDir.getDirectoryHandle('bundle');
    console.log('Bundle directory name:', bundleDir.name);

    // Test directory iteration (potential for OOB in bundle files)
    let entryCount = 0;
    for await (let [name, handle] of bundleDir) {
      console.log(`Bundle entry: ${name}, kind: ${handle.kind}`);
      entryCount++;
      
      if (handle.kind === 'file' && entryCount <= 2) {
        // Test file handle operations on bundle files
        let fileHandle = handle;
        let file = await fileHandle.getFile();
        console.log(`Bundle file ${name} size:`, file.size);
        
        // Test reading bundle file content (potential OOB reads)
        let text = await file.text();
        console.log(`Bundle file ${name} content length:`, text.length);
        
        if (file.size > 0) {
          let arrayBuffer = await file.arrayBuffer();
          console.log(`Bundle file ${name} buffer length:`, arrayBuffer.byteLength);
        }
      }
    }

    // Test temp directory operations with Web FS API
    let tempDir = await rootDir.getDirectoryHandle('tmp');
    let testFile = await tempDir.getFileHandle('webfs-test.txt', { create: true });
    console.log('Created file handle:', testFile.name);

    // Test FileSystemWritableFileStream
    let writable = await testFile.createWritable();
    console.log('Created writable stream');

    await writable.write('Hello Web FS!');
    await writable.write(new Uint8Array([65, 66, 67])); // ABC
    await writable.close();
    console.log('Writable stream closed');

    // Test reading the written file
    let writtenFile = await testFile.getFile();
    let content = await writtenFile.text();
    console.log('Written content length:', content.length);

    // Test file handle operations with various write modes
    let writable2 = await testFile.createWritable({ keepExistingData: true });
    await writable2.seek(0);
    await writable2.write('REPLACED');
    await writable2.truncate(8);
    await writable2.close();

    let modifiedFile = await testFile.getFile();
    let modifiedContent = await modifiedFile.text();
    console.log('Modified content:', modifiedContent);

    // Test directory handle operations
    let subDir = await tempDir.getDirectoryHandle('webfs-subdir', { create: true });
    let subFile = await subDir.getFileHandle('nested.txt', { create: true });
    
    let subWritable = await subFile.createWritable();
    await subWritable.write('Nested file content');
    await subWritable.close();

    // Test directory traversal and file access patterns
    let subdirEntries = [];
    for await (let [name, handle] of subDir) {
      subdirEntries.push(name);
      if (handle.kind === 'file') {
        let file = await handle.getFile();
        console.log(`Subdir file ${name} size:`, file.size);
      }
    }
    console.log('Subdir entries:', subdirEntries);

    // Test handle comparison
    let sameFile = await subDir.getFileHandle('nested.txt');
    let isSame = await subFile.isSameEntry(sameFile);
    console.log('Handle comparison result:', isSame);

    // Test error conditions
    try {
      await tempDir.getFileHandle('nonexistent-file');
    } catch (e) {
      console.log('Expected file not found:', e.name);
    }

    try {
      await rootDir.getDirectoryHandle('invalid-dir');
    } catch (e) {
      console.log('Expected dir not found:', e.name);
    }

    // Test removal operations
    await subFile.remove();
    await subDir.removeEntry('nested.txt').catch(() => console.log('File already removed'));
    await tempDir.removeEntry('webfs-subdir', { recursive: true });
    await testFile.remove();

  } catch (error) {
    console.error('Web FS test error:', error.message, error.name);
  }
}

// Execute the Web FS tests
await runWebFSTests();
console.log('Web File System API tests completed');