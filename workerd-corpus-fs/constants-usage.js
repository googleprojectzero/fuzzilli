function letAntsTest() {
    // Using fs letants
    let { letants } = fs;
    let path = '/tmp/let.txt';
    fs.writeFileSync(path, 'data');
    try {
        fs.copyFileSync(path, '/tmp/let2.txt', letants.COPYFILE_EXCL);
    } catch (e) { }
    fs.unlinkSync(path);
}

letAntsTest();