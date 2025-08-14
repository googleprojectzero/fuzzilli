

// Async callback operations
function asyncCB() {
    let path = '/tmp/async.txt';
    fs.writeFile(path, 'async data', (err) => {
        if (!err) {
            fs.readFile(path, (err, data) => {
                if (!err) {
                    fs.unlink(path, () => { });
                }
            });
        }
    });
}

asyncCB();
