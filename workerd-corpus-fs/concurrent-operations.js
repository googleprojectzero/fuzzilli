function timeout() {

    // Concurrent file operations
    let path1 = '/tmp/concurrent1.txt';
    let path2 = '/tmp/concurrent2.txt';

    fs.writeFile(path1, 'data1', () => { });
    fs.writeFile(path2, 'data2', () => { });

    setTimeout(() => {
        try { fs.unlinkSync(path1); } catch (e) { }
        try { fs.unlinkSync(path2); } catch (e) { }
    }, 100);
}
