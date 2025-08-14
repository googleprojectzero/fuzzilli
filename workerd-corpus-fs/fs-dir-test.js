// Copyright (c) 2017-2022 Cloudflare, Inc.
// Licensed under the Apache 2.0 license found in the LICENSE file or at:
//     https://opensource.org/licenses/Apache-2.0
strictEqual(typeof fs.existsSync, 'function');
strictEqual(typeof fs.writeFileSync, 'function');
strictEqual(typeof fs.mkdirSync, 'function');
strictEqual(typeof fs.mkdtempSync, 'function');
strictEqual(typeof fs.rmSync, 'function');
strictEqual(typeof fs.rmdirSync, 'function');
strictEqual(typeof fs.readdirSync, 'function');
strictEqual(typeof fs.mkdtemp, 'function');
strictEqual(typeof fs.mkdir, 'function');
strictEqual(typeof fs.rm, 'function');
strictEqual(typeof fs.rmdir, 'function');
strictEqual(typeof fs.readdir, 'function');
strictEqual(typeof fs.opendirSync, 'function');
strictEqual(typeof fs.opendir, 'function');
strictEqual(typeof promises.fs.mkdir, 'function');
strictEqual(typeof promises.fs.mkdtemp, 'function');
strictEqual(typeof promises.fs.rm, 'function');
strictEqual(typeof promises.fs.rmdir, 'function');
strictEqual(typeof promises.fs.readdir, 'function');
strictEqual(typeof promises.fs.opendir, 'function');

const kInvalidArgTypeError = { code: 'ERR_INVALID_ARG_TYPE' };
const kInvalidArgValueError = { code: 'ERR_INVALID_ARG_VALUE' };
const kEPermError = { code: 'EPERM' };
const kENoEntError = { code: 'ENOENT' };
const kEExistError = { code: 'EEXIST' };
const kENotDirError = { code: 'ENOTDIR' };
const kENotEmptyError = { code: 'ENOTEMPTY' };

const mkdirSyncTest = {
  test() {
    throws(() => fs.mkdirSync(), kInvalidArgTypeError);
    throws(() => fs.mkdirSync(123), kInvalidArgTypeError);
    throws(() => fs.mkdirSync('/tmp/testdir', 'hello'), kInvalidArgTypeError);
    throws(
      () => fs.mkdirSync('/tmp/testdir', { recursive: 123 }),
      kInvalidArgTypeError
    );

    // Make a directory.
    ok(!fs.existsSync('/tmp/testdir'));
    strictEqual(fs.mkdirSync('/tmp/testdir'), undefined);
    ok(fs.existsSync('/tmp/testdir'));

    // Making a subdirectory in a non-existing path fails by default
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    throws(() => fs.mkdirSync('/tmp/testdir/a/b/c'), kENoEntError);

    // But passing the recursive option allows the entire path to be created.
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    strictEqual(
      fs.mkdirSync('/tmp/testdir/a/b/c', { recursive: true }),
      '/tmp/testdir/a'
    );
    ok(fs.existsSync('/tmp/testdir/a/b/c'));

    // Cannot make a directory in a read-only location
    throws(() => fs.mkdirSync('/bundle/a'), kEPermError);

    // Making a directory that already exists is a non-op
    fs.mkdirSync('/tmp/testdir');

    // Attempting to create a directory that already exists as a file throws
    fs.writeFileSync('/tmp/abc', 'Hello World');
    throws(() => fs.mkdirSync('/tmp/abc'), kEExistError);

    // Attempting to create a directory recursively when a parent is a file
    // throws
    throws(() => fs.mkdirSync('/tmp/abc/foo', { recursive: true }), kENotDirError);
  },
};

const mkdirAsyncCallbackTest = {
  async test() {
    throws(() => mkdir(), kInvalidArgTypeError);
    throws(() => mkdir(123), kInvalidArgTypeError);
    throws(() => mkdir('/tmp/testdir', 'hello'), kInvalidArgTypeError);
    throws(
      () => mkdir('/tmp/testdir', { recursive: 123 }),
      kInvalidArgTypeError
    );

    // Make a directory.
    ok(!fs.existsSync('/tmp/testdir'));
    await new Promise((resolve, reject) => {
      mkdir('/tmp/testdir', (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    ok(fs.existsSync('/tmp/testdir'));

    // Making a subdirectory in a non-existing path fails by default
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    await new Promise((resolve, reject) => {
      mkdir('/tmp/testdir/a/b/c', (err) => {
        if (err && err.code === kENoEntError.code) resolve();
        else reject(err);
      });
    });

    // But passing the recursive option allows the entire path to be created.
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    await new Promise((resolve, reject) => {
      mkdir('/tmp/testdir/a/b/c', { recursive: true }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    ok(fs.existsSync('/tmp/testdir/a/b/c'));

    // Cannot make a directory in a read-only location
    await new Promise((resolve, reject) => {
      mkdir('/bundle/a', (err) => {
        if (err && err.code === kEPermError.code) resolve();
        else reject(err);
      });
    });

    // Making a directory that already exists is a non-op
    await new Promise((resolve, reject) => {
      mkdir('/tmp/testdir', (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Attempting to create a directory that already exists as a file throws
    fs.writeFileSync('/tmp/abc', 'Hello World');
    await new Promise((resolve, reject) => {
      mkdir('/tmp/abc', (err) => {
        if (err && err.code === kEExistError.code) resolve();
        else reject(err);
      });
    });

    // Attempting to create a directory recursively when a parent is a file
    // throws
    await new Promise((resolve, reject) => {
      mkdir('/tmp/abc/foo', { recursive: true }, (err) => {
        if (err && err.code === kENotDirError.code) resolve();
        else reject(err);
      });
    });
  },
};

const mkdirAsyncPromiseTest = {
  async test() {
    await rejects(promises.fs.mkdir(), kInvalidArgTypeError);
    await rejects(promises.fs.mkdir(123), kInvalidArgTypeError);
    await rejects(
      promises.fs.mkdir('/tmp/testdir', 'hello'),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.mkdir('/tmp/testdir', { recursive: 123 }),
      kInvalidArgTypeError
    );

    // Make a directory.
    ok(!fs.existsSync('/tmp/testdir'));
    await promises.fs.mkdir('/tmp/testdir');
    ok(fs.existsSync('/tmp/testdir'));

    // Making a subdirectory in a non-existing path fails by default
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    await rejects(promises.fs.mkdir('/tmp/testdir/a/b/c'), kENoEntError);

    // But passing the recursive option allows the entire path to be created.
    ok(!fs.existsSync('/tmp/testdir/a/b/c'));
    await promises.fs.mkdir('/tmp/testdir/a/b/c', { recursive: true });
    ok(fs.existsSync('/tmp/testdir/a/b/c'));

    // Cannot make a directory in a read-only location
    await rejects(promises.fs.mkdir('/bundle/a'), kEPermError);

    // Making a directory that already exists is a non-op
    await promises.fs.mkdir('/tmp/testdir');

    // Attempting to create a directory that already exists as a file throws
    fs.writeFileSync('/tmp/abc', 'Hello World');
    await rejects(promises.fs.mkdir('/tmp/abc'), kEExistError);

    // Attempting to create a directory recursively when a parent is a file
    // throws
    await rejects(
      promises.fs.mkdir('/tmp/abc/foo', { recursive: true }),
      kENotDirError
    );
  },
};

const mkdtempSyncTest = {
  test() {
    throws(() => fs.mkdtempSync(), kInvalidArgTypeError);
    const ret1 = fs.mkdtempSync('/tmp/testdir-');
    const ret2 = fs.mkdtempSync('/tmp/testdir-');
    match(ret1, /\/tmp\/testdir-\d+/);
    match(ret2, /\/tmp\/testdir-\d+/);
    ok(fs.existsSync(ret1));
    ok(fs.existsSync(ret2));
    throws(() => fs.mkdtempSync('/bundle/testdir-'), kEPermError);
  },
};

const mkdtempAsyncCallbackTest = {
  async test() {
    throws(() => fs.mkdtemp(), kInvalidArgTypeError);
    const ret1 = await new Promise((resolve, reject) => {
      fs.mkdtemp('/tmp/testdir-', (err, dir) => {
        if (err) reject(err);
        else resolve(dir);
      });
    });
    const ret2 = await new Promise((resolve, reject) => {
      fs.mkdtemp('/tmp/testdir-', (err, dir) => {
        if (err) reject(err);
        else resolve(dir);
      });
    });
    match(ret1, /\/tmp\/testdir-\d+/);
    match(ret2, /\/tmp\/testdir-\d+/);
    ok(fs.existsSync(ret1));
    ok(fs.existsSync(ret2));
    await new Promise((resolve, reject) => {
      fs.mkdtemp('/bundle/testdir-', (err) => {
        if (err && err.code === kEPermError.code) resolve();
        else reject(err);
      });
    });
  },
};

const mkdtempAsyncPromiseTest = {
  async test() {
    await rejects(promises.fs.mkdtemp(), kInvalidArgTypeError);
    const ret1 = await promises.fs.mkdtemp('/tmp/testdir-');
    const ret2 = await promises.fs.mkdtemp('/tmp/testdir-');
    match(ret1, /\/tmp\/testdir-\d+/);
    match(ret2, /\/tmp\/testdir-\d+/);
    ok(fs.existsSync(ret1));
    ok(fs.existsSync(ret2));
    await rejects(promises.fs.mkdtemp('/bundle/testdir-'), kEPermError);
  },
};

const rmSyncTest = {
  test() {
    // Passing incorrect types for options throws
    throws(
      () => fs.rmSync('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    throws(() => fs.rmSync('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    throws(
      () => fs.rmSync('/tmp/testdir', { force: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmSync('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmSync('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmSync('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmSync('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );
    throws(
      () =>
        fs.rmSync('/tmp/testdir', { maxRetries: 1, retryDelay: 1, force: 'yes' }),
      kInvalidArgTypeError
    );

    throws(
      () => fs.rmdirSync('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    throws(() => fs.rmdirSync('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    throws(
      () => fs.rmdirSync('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdirSync('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdirSync('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdirSync('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );

    ok(!fs.existsSync('/tmp/testdir'));
    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');

    // When the recusive option is not set, then removing a directory
    // with children throws...
    throws(() => fs.rmdirSync('/tmp/testdir'), kENotEmptyError);
    ok(fs.existsSync('/tmp/testdir'));

    // But works when the recursive option is set
    fs.rmdirSync('/tmp/testdir', { recursive: true });
    ok(!fs.existsSync('/tmp/testdir'));

    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');
    fs.writeFileSync('/tmp/testdir/b.txt', 'Hello World');
    ok(fs.existsSync('/tmp/testdir/a.txt'));

    // trying to remove a file with fs.rmdir throws
    throws(() => fs.rmdirSync('/tmp/testdir/a.txt'), kENotDirError);

    // removing a file with fs.rm works
    fs.rmSync('/tmp/testdir/a.txt');
    ok(!fs.existsSync('/tmp/testdir/a.txt'));

    // Calling fs.rmSync when the directory is not empty throws
    throws(() => fs.rmSync('/tmp/testdir'), kENotEmptyError);
    ok(fs.existsSync('/tmp/testdir'));

    // But works when the recursive option is set
    throws(() => fs.rmSync('/tmp/testdir'));
    fs.rmSync('/tmp/testdir', { recursive: true });
    ok(!fs.existsSync('/tmp/testdir'));
  },
};

const rmAsyncCallbackTest = {
  async test() {
    // Passing incorrect types for options throws
    throws(
      () => fs.rm('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    throws(() => fs.rm('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    throws(() => fs.rm('/tmp/testdir', { force: 'yes' }), kInvalidArgTypeError);
    throws(
      () => fs.rm('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rm('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rm('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rm('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rm('/tmp/testdir', { maxRetries: 1, retryDelay: 1, force: 'yes' }),
      kInvalidArgTypeError
    );

    throws(
      () => fs.rmdir('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    throws(() => fs.rmdir('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    throws(
      () => fs.rmdir('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdir('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdir('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.rmdir('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );

    ok(!fs.existsSync('/tmp/testdir'));
    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');

    // When the recusive option is not set, then removing a directory
    // with children throws...
    await new Promise((resolve, reject) => {
      fs.rmdir('/tmp/testdir', (err) => {
        if (err && err.code === kENotEmptyError.code) resolve();
        else reject(err);
      });
    });

    ok(fs.existsSync('/tmp/testdir'));
    // But works when the recursive option is set
    await new Promise((resolve, reject) => {
      fs.rmdir('/tmp/testdir', { recursive: true }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    ok(!fs.existsSync('/tmp/testdir'));
    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');
    fs.writeFileSync('/tmp/testdir/b.txt', 'Hello World');

    ok(fs.existsSync('/tmp/testdir/a.txt'));
    // trying to remove a file with fs.rmdir throws
    await new Promise((resolve, reject) => {
      fs.rmdir('/tmp/testdir/a.txt', (err) => {
        if (err && err.code === kENotDirError.code) resolve();
        else reject(err);
      });
    });
    // removing a file with fs.rm works
    await new Promise((resolve, reject) => {
      fs.rm('/tmp/testdir/a.txt', (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    ok(!fs.existsSync('/tmp/testdir/a.txt'));
    // Calling fs.rm when the directory is not empty throws
    await new Promise((resolve, reject) => {
      fs.rm('/tmp/testdir', (err) => {
        if (err && err.code === kENotEmptyError.code) resolve();
        else reject(err);
      });
    });
    ok(fs.existsSync('/tmp/testdir'));
    // But works when the recursive option is set
    await new Promise((resolve, reject) => {
      fs.rm('/tmp/testdir', { recursive: true }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    ok(!fs.existsSync('/tmp/testdir'));
  },
};

const rmAsyncPromiseTest = {
  async test() {
    // Passing incorrect types for options throws
    await rejects(
      promises.fs.rm('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(promises.fs.rm('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    await rejects(
      promises.fs.rm('/tmp/testdir', { force: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rm('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rm('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rm('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rm('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rm('/tmp/testdir', {
        maxRetries: 1,
        retryDelay: 1,
        force: 'yes',
      }),
      kInvalidArgTypeError
    );

    await rejects(
      promises.fs.rmdir('/tmp/testdir', { recursive: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(promises.fs.rmdir('/tmp/testdir', 'abc'), kInvalidArgTypeError);
    await rejects(
      promises.fs.rmdir('/tmp/testdir', { maxRetries: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rmdir('/tmp/testdir', { retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rmdir('/tmp/testdir', { maxRetries: 1, retryDelay: 'yes' }),
      kInvalidArgTypeError
    );
    await rejects(
      promises.fs.rmdir('/tmp/testdir', { maxRetries: 'yes', retryDelay: 1 }),
      kInvalidArgTypeError
    );

    ok(!fs.existsSync('/tmp/testdir'));
    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');

    // When the recusive option is not set, then removing a directory
    // with children throws...
    await rejects(promises.fs.rmdir('/tmp/testdir'), kENotEmptyError);

    ok(fs.existsSync('/tmp/testdir'));
    // But works when the recursive option is set
    await promises.fs.rmdir('/tmp/testdir', { recursive: true });
    ok(!fs.existsSync('/tmp/testdir'));
    fs.mkdirSync('/tmp/testdir');
    fs.writeFileSync('/tmp/testdir/a.txt', 'Hello World');
    fs.writeFileSync('/tmp/testdir/b.txt', 'Hello World');
    ok(fs.existsSync('/tmp/testdir/a.txt'));
    // trying to remove a file with fs.rmdir throws
    await rejects(promises.fs.rmdir('/tmp/testdir/a.txt'), kENotDirError);
    // removing a file with fs.rm works
    await promises.fs.rm('/tmp/testdir/a.txt');
    ok(!fs.existsSync('/tmp/testdir/a.txt'));
    // Calling fs.rm when the directory is not empty throws
    await rejects(promises.fs.rm('/tmp/testdir'), kENotEmptyError);
    ok(fs.existsSync('/tmp/testdir'));
    // But works when the recursive option is set
    await promises.fs.rm('/tmp/testdir', { recursive: true });
    ok(!fs.existsSync('/tmp/testdir'));
  },
};

const readdirSyncTest = {
  test() {
    throws(() => fs.readdirSync(), kInvalidArgTypeError);
    throws(() => fs.readdirSync(123), kInvalidArgTypeError);
    throws(
      () => fs.readdirSync('/tmp/testdir', { withFileTypes: 123 }),
      kInvalidArgTypeError
    );
    throws(
      () => fs.readdirSync('/tmp/testdir', { recursive: 123 }),
      kInvalidArgTypeError
    );
    throws(
      () =>
        fs.readdirSync('/tmp/testdir', { withFileTypes: true, recursive: 123 }),
      kInvalidArgTypeError
    );

    deepStrictEqual(fs.readdirSync('/'), ['bundle', 'tmp', 'dev']);

    deepStrictEqual(fs.readdirSync('/', 'buffer'), [
      Buffer.from('bundle'),
      Buffer.from('tmp'),
      Buffer.from('dev'),
    ]);

    {
      const ents = fs.readdirSync('/', { withFileTypes: true });
      strictEqual(ents.length, 3);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = fs.readdirSync('/', {
        withFileTypes: true,
        encoding: 'buffer',
      });
      strictEqual(ents.length, 3);

      deepStrictEqual(ents[0].name, Buffer.from('bundle'));
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = fs.readdirSync('/', { withFileTypes: true, recursive: true });
      strictEqual(ents.length, 8);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');

      strictEqual(ents[1].name, 'bundle/worker');
      strictEqual(ents[1].isDirectory(), false);
      strictEqual(ents[1].isFile(), true);
      strictEqual(ents[1].isBlockDevice(), false);
      strictEqual(ents[1].isCharacterDevice(), false);
      strictEqual(ents[1].isFIFO(), false);
      strictEqual(ents[1].isSocket(), false);
      strictEqual(ents[1].isSymbolicLink(), false);
      strictEqual(ents[1].parentPath, '/bundle');

      strictEqual(ents[4].name, 'dev/null');
      strictEqual(ents[4].isDirectory(), false);
      strictEqual(ents[4].isFile(), false);
      strictEqual(ents[4].isBlockDevice(), false);
      strictEqual(ents[4].isCharacterDevice(), true);
      strictEqual(ents[4].isFIFO(), false);
      strictEqual(ents[4].isSocket(), false);
      strictEqual(ents[4].isSymbolicLink(), false);
      strictEqual(ents[4].parentPath, '/dev');
    }
  },
};

const readdirAsyncCallbackTest = {
  async test() {
    deepStrictEqual(
      await new Promise((resolve, reject) => {
        fs.readdir('/', (err, files) => {
          if (err) reject(err);
          else resolve(files);
        });
      }),
      ['bundle', 'tmp', 'dev']
    );

    {
      const ents = await new Promise((resolve, reject) => {
        fs.readdir('/', { withFileTypes: true }, (err, files) => {
          if (err) reject(err);
          else resolve(files);
        });
      });
      strictEqual(ents.length, 3);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = await new Promise((resolve, reject) => {
        fs.readdir(
          '/',
          { withFileTypes: true, encoding: 'buffer' },
          (err, files) => {
            if (err) reject(err);
            else resolve(files);
          }
        );
      });
      strictEqual(ents.length, 3);

      deepStrictEqual(ents[0].name, Buffer.from('bundle'));
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = await new Promise((resolve, reject) => {
        fs.readdir('/', { withFileTypes: true, recursive: true }, (err, files) => {
          if (err) reject(err);
          else resolve(files);
        });
      });
      strictEqual(ents.length, 8);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');

      strictEqual(ents[1].name, 'bundle/worker');
      strictEqual(ents[1].isDirectory(), false);
      strictEqual(ents[1].isFile(), true);
      strictEqual(ents[1].isBlockDevice(), false);
      strictEqual(ents[1].isCharacterDevice(), false);
      strictEqual(ents[1].isFIFO(), false);
      strictEqual(ents[1].isSocket(), false);
      strictEqual(ents[1].isSymbolicLink(), false);
      strictEqual(ents[1].parentPath, '/bundle');

      strictEqual(ents[4].name, 'dev/null');
      strictEqual(ents[4].isDirectory(), false);
      strictEqual(ents[4].isFile(), false);
      strictEqual(ents[4].isBlockDevice(), false);
      strictEqual(ents[4].isCharacterDevice(), true);
      strictEqual(ents[4].isFIFO(), false);
      strictEqual(ents[4].isSocket(), false);
      strictEqual(ents[4].isSymbolicLink(), false);
      strictEqual(ents[4].parentPath, '/dev');
    }
  },
};

const readdirAsyncPromiseTest = {
  async test() {
    deepStrictEqual(await promises.fs.readdir('/'), ['bundle', 'tmp', 'dev']);

    {
      const ents = await promises.fs.readdir('/', { withFileTypes: true });
      strictEqual(ents.length, 3);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = await promises.fs.readdir('/', {
        withFileTypes: true,
        encoding: 'buffer',
      });
      strictEqual(ents.length, 3);

      deepStrictEqual(ents[0].name, Buffer.from('bundle'));
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');
    }

    {
      const ents = await promises.fs.readdir('/', {
        withFileTypes: true,
        recursive: true,
      });
      strictEqual(ents.length, 8);

      strictEqual(ents[0].name, 'bundle');
      strictEqual(ents[0].isDirectory(), true);
      strictEqual(ents[0].isFile(), false);
      strictEqual(ents[0].isBlockDevice(), false);
      strictEqual(ents[0].isCharacterDevice(), false);
      strictEqual(ents[0].isFIFO(), false);
      strictEqual(ents[0].isSocket(), false);
      strictEqual(ents[0].isSymbolicLink(), false);
      strictEqual(ents[0].parentPath, '/');

      strictEqual(ents[1].name, 'bundle/worker');
      strictEqual(ents[1].isDirectory(), false);
      strictEqual(ents[1].isFile(), true);
      strictEqual(ents[1].isBlockDevice(), false);
      strictEqual(ents[1].isCharacterDevice(), false);
      strictEqual(ents[1].isFIFO(), false);
      strictEqual(ents[1].isSocket(), false);
      strictEqual(ents[1].isSymbolicLink(), false);
      strictEqual(ents[1].parentPath, '/bundle');
      strictEqual(ents[4].name, 'dev/null');
      strictEqual(ents[4].isDirectory(), false);
      strictEqual(ents[4].isFile(), false);
      strictEqual(ents[4].isBlockDevice(), false);
      strictEqual(ents[4].isCharacterDevice(), true);
      strictEqual(ents[4].isFIFO(), false);
      strictEqual(ents[4].isSocket(), false);
      strictEqual(ents[4].isSymbolicLink(), false);
      strictEqual(ents[4].parentPath, '/dev');
    }
  },
};

const opendirSyncTest = {
  test() {
    throws(() => fs.opendirSync(), kInvalidArgTypeError);
    throws(() => fs.opendirSync(123), kInvalidArgTypeError);
    throws(() => fs.opendirSync('/tmp', { encoding: 123 }), kInvalidArgValueError);

    const dir = fs.opendirSync('/', { recursive: true });
    strictEqual(dir.path, '/');
    strictEqual(dir.readSync().name, 'bundle');
    strictEqual(dir.readSync().name, 'bundle/worker');
    strictEqual(dir.readSync().name, 'tmp');
    strictEqual(dir.readSync().name, 'dev');
    strictEqual(dir.readSync().name, 'dev/null');
    strictEqual(dir.readSync().name, 'dev/zero');
    strictEqual(dir.readSync().name, 'dev/full');
    strictEqual(dir.readSync().name, 'dev/random');
    strictEqual(dir.readSync(), null); // All done.
    dir.closeSync();

    // Closing again throws
    throws(() => dir.closeSync(), { code: 'ERR_DIR_CLOSED' });
    // Reading again throws
    throws(() => dir.readSync(), { code: 'ERR_DIR_CLOSED' });
  },
};