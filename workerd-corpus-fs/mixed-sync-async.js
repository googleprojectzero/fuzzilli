function mixed() {
    // Mix sync and async operations
    let path = '/tmp/mixed.txt';
    fs.writeFileSync(path, 'sync');
    fs.readFile(path, (err, data) => {
        if (!err) {
            fs.appendFileSync(path, 'more');
            fs.unlink(path, () => { });
        }
    });
}
mixed();