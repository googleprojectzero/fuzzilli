strictEqual(typeof openSync, 'function');
strictEqual(typeof closeSync, 'function');
strictEqual(typeof statSync, 'function');
strictEqual(typeof fstatSync, 'function');
strictEqual(typeof lstatSync, 'function');
strictEqual(typeof symlinkSync, 'function');
strictEqual(typeof chmod, 'function');
strictEqual(typeof lchmod, 'function');
strictEqual(typeof fchmod, 'function');
strictEqual(typeof chmodSync, 'function');
strictEqual(typeof lchmodSync, 'function');
strictEqual(typeof fchmodSync, 'function');
strictEqual(typeof fs.chown, 'function');
strictEqual(typeof lchown, 'function');
strictEqual(typeof fchown, 'function');
strictEqual(typeof chownSync, 'function');
strictEqual(typeof lchownSync, 'function');
strictEqual(typeof fchownSync, 'function');
strictEqual(typeof promises.fs.chown, 'function');
strictEqual(typeof promises.lchown, 'function');

const kInvalidArgTypeError = { code: 'ERR_INVALID_ARG_TYPE' };
const kOutOfRangeError = { code: 'ERR_OUT_OF_RANGE' };

function checkStat(path) {
  const { uid, gid } = fs.statSync(path);
  strictEqual(uid, 0);
  strictEqual(gid, 0);
}

function checkfStat(fd) {
  const { uid, gid } = fs.fstatSync(fd);
  strictEqual(uid, 0);
  strictEqual(gid, 0);
}

const path = '/tmp';
const bufferPath = Buffer.from(path);
const urlPath = new URL(path, 'file:///');

const chownSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => fs.chownSync(123), kInvalidArgTypeError);
    throws(() => fs.chownSync('/', {}), kInvalidArgTypeError);
    throws(() => fs.chownSync('/', 0, {}), kInvalidArgTypeError);
    throws(() => fs.chownSync(path, -1000, 0), kOutOfRangeError);
    throws(() => fs.chownSync(path, 0, -1000), kOutOfRangeError);

    // We stat the file before and after to verify the impact
    // of the fs.chown( operation. Specifically, the uid and gid
    // should not change since our impl is a non-op.
    checkStat(path);
    fs.chownSync(path, 1000, 1000);
    checkStat(path);

    fs.chownSync(bufferPath, 1000, 1000);
    checkStat(bufferPath);

    fs.chownSync(urlPath, 1000, 1000);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    throws(() => fs.chownSync('/non-existent-path', 1000, 1000), {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'fs.chown',
    });
  },
};

const chownCallbackTest = {
  async test() {
    // Incorrect input types should throw synchronously
    throws(() => fs.chown(123), kInvalidArgTypeError);
    throws(() => fs.chown('/', {}), kInvalidArgTypeError);
    throws(() => fs.chown('/', 0, {}), kInvalidArgTypeError);
    throws(() => fs.chownSync(path, -1000, 0), kOutOfRangeError);
    throws(() => fs.chownSync(path, 0, -1000), kOutOfRangeError);

    async function callChown(path) {
      const { promise, resolve, reject } = Promise.withResolvers();
      fs.chown(path, 1000, 1000, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    // Should be non-op
    checkStat(path);
    await callChown(path);
    checkStat(path);

    await callChown(bufferPath);
    checkStat(bufferPath);

    await callChown(urlPath);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    const { promise, resolve, reject } = Promise.withResolvers();
    fs.chown('/non-existent-path', 1000, 1000, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'fs.chown(',
    });
  },
};

const chownPromiseTest = {
  async test() {
    // Incorrect input types should reject the promise.
    await rejects(promises.fs.chown(123), kInvalidArgTypeError);
    await rejects(promises.fs.chown('/', {}), kInvalidArgTypeError);
    await rejects(promises.fs.chown('/', 0, {}), kInvalidArgTypeError);
    await rejects(promises.fs.chown(path, -1000, 0), kOutOfRangeError);
    await rejects(promises.fs.chown(path, 0, -1000), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    await promises.fs.chown(path, 1000, 1000);
    checkStat(path);

    await promises.fs.chown(bufferPath, 1000, 1000);
    checkStat(bufferPath);

    await promises.fs.chown(urlPath, 1000, 1000);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    await rejects(promises.fs.chown('/non-existent-path', 1000, 1000), {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'fs.chown(',
    });
  },
};

const lchownSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => lchownSync(123), kInvalidArgTypeError);
    throws(() => lchownSync('/', {}), kInvalidArgTypeError);
    throws(() => lchownSync('/', 0, {}), kInvalidArgTypeError);
    throws(() => lchownSync(path, -1000, 0), kOutOfRangeError);
    throws(() => lchownSync(path, 0, -1000), kOutOfRangeError);

    // We stat the file before and after to verify the impact
    // of the fs.chown( operation. Specifically, the uid and gid
    // should not change since our impl is a non-op.
    checkStat(path);
    lchownSync(path, 1000, 1000);
    checkStat(path);

    lchownSync(bufferPath, 1000, 1000);
    checkStat(bufferPath);

    lchownSync(urlPath, 1000, 1000);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    throws(() => lchownSync('/non-existent-path', 1000, 1000), {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'lchown',
    });
  },
};

const lchownCallbackTest = {
  async test() {
    // Incorrect input types should throw synchronously
    throws(() => lchown(123), kInvalidArgTypeError);
    throws(() => lchown('/', {}), kInvalidArgTypeError);
    throws(() => lchown('/', 0, {}), kInvalidArgTypeError);
    throws(() => lchownSync(path, -1000, 0), kOutOfRangeError);
    throws(() => lchownSync(path, 0, -1000), kOutOfRangeError);

    async function callChown(path) {
      const { promise, resolve, reject } = Promise.withResolvers();
      lchown(path, 1000, 1000, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    // Should be non-op
    checkStat(path);
    await callChown(path);
    checkStat(path);

    await callChown(bufferPath);
    checkStat(bufferPath);

    await callChown(urlPath);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    const { promise, resolve, reject } = Promise.withResolvers();
    lchown('/non-existent-path', 1000, 1000, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'lchown',
    });
  },
};

const lchownPromiseTest = {
  async test() {
    // Incorrect input types should reject the promise.
    await rejects(promises.lchown(123), kInvalidArgTypeError);
    await rejects(promises.lchown('/', {}), kInvalidArgTypeError);
    await rejects(promises.lchown('/', 0, {}), kInvalidArgTypeError);
    await rejects(promises.lchown(path, -1000, 0), kOutOfRangeError);
    await rejects(promises.lchown(path, 0, -1000), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    await promises.lchown(path, 1000, 1000);
    checkStat(path);

    await promises.lchown(bufferPath, 1000, 1000);
    checkStat(bufferPath);

    await promises.lchown(urlPath, 1000, 1000);
    checkStat(urlPath);

    // A non-existent path should throw ENOENT
    await rejects(promises.lchown('/non-existent-path', 1000, 1000), {
      code: 'ENOENT',
      syscall: 'lchown',
    });
  },
};

const fchownSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => fchownSync({}), kInvalidArgTypeError);
    throws(() => fchownSync(123), kInvalidArgTypeError);
    throws(() => fchownSync(123, {}), kInvalidArgTypeError);
    throws(() => fchownSync(123, 0, {}), kInvalidArgTypeError);
    throws(() => fchownSync(123, -1000, 0), kOutOfRangeError);
    throws(() => fchownSync(123, 0, -1000), kOutOfRangeError);

    const fd = openSync('/tmp');

    // We stat the file before and after to verify the impact
    // of the fs.chown( operation. Specifically, the uid and gid
    // should not change since our impl is a non-op.
    checkfStat(fd);
    fchownSync(fd, 1000, 1000);
    checkfStat(fd);

    throws(() => fchownSync(999, 1000, 1000), {
      code: 'EBADF',
      syscall: 'fstat',
    });

    closeSync(fd);
  },
};

const fchownCallbackTest = {
  async test() {
    // Incorrect input types should throw synchronously
    throws(() => fchown({}), kInvalidArgTypeError);
    throws(() => fchown(123), kInvalidArgTypeError);
    throws(() => fchown(123, {}), kInvalidArgTypeError);
    throws(() => fchown(123, 0, {}), kInvalidArgTypeError);
    throws(() => fchown(123, -1000, 0), kOutOfRangeError);
    throws(() => fchown(123, 0, -1000), kOutOfRangeError);

    const fd = openSync('/tmp');

    async function callChown() {
      const { promise, resolve, reject } = Promise.withResolvers();
      fchown(fd, 1000, 1000, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    // Should be non-op
    checkfStat(fd);
    await callChown();
    checkfStat(fd);

    const { promise, resolve, reject } = Promise.withResolvers();
    fchown(999, 1000, 1000, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'EBADF',
      syscall: 'fstat',
    });

    closeSync(fd);
  },
};

// ===========================================================================

const chmodSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => chmodSync(123), kInvalidArgTypeError);
    throws(() => chmodSync('/', {}), kInvalidArgTypeError);
    throws(() => chmodSync('/tmp', -1), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    chmodSync(path, 0o777);
    checkStat(path);

    chmodSync(bufferPath, 0o777);
    checkStat(bufferPath);

    chmodSync(urlPath, 0o777);
    checkStat(urlPath);

    throws(() => chmodSync('/non-existent-path', 0o777), {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'chmod',
    });
  },
};

const chmodCallbackTest = {
  async test() {
    // Incorrect input types should throw.
    throws(() => chmod(123), kInvalidArgTypeError);
    throws(() => chmod('/', {}), kInvalidArgTypeError);
    throws(() => chmod('/tmp', -1), kOutOfRangeError);

    async function callChmod(path) {
      const { promise, resolve, reject } = Promise.withResolvers();
      chmod(path, 0o000, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    checkStat(path);
    await callChmod(path);
    checkStat(path);

    await callChmod(bufferPath);
    checkStat(bufferPath);

    await callChmod(urlPath);
    checkStat(bufferPath);

    const { promise, resolve, reject } = Promise.withResolvers();
    chmod('/non-existent-path', 0o777, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'chmod',
    });
  },
};

const chmodPromiseTest = {
  async test() {
    // Incorrect input types should reject the promise.
    await rejects(promises.chmod(123), kInvalidArgTypeError);
    await rejects(promises.chmod('/', {}), kInvalidArgTypeError);
    await rejects(promises.chmod('/tmp', -1), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    await promises.chmod(path, 0o777);
    checkStat(path);

    await promises.chmod(bufferPath, 0o777);
    checkStat(bufferPath);

    await promises.chmod(urlPath, 0o777);
    checkStat(urlPath);

    await rejects(promises.chmod('/non-existent-path', 0o777), {
      code: 'ENOENT',
      syscall: 'chmod',
    });
  },
};

const lchmodSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => lchmodSync(123), kInvalidArgTypeError);
    throws(() => lchmodSync('/', {}), kInvalidArgTypeError);
    throws(() => lchmodSync('/tmp', -1), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    lchmodSync(path, 0o777);
    checkStat(path);

    lchmodSync(bufferPath, 0o777);
    checkStat(bufferPath);

    lchmodSync(urlPath, 0o777);
    checkStat(urlPath);

    throws(() => lchmodSync('/non-existent-path', 0o777), {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'lchmod',
    });
  },
};

const lchmodCallbackTest = {
  async test() {
    // Incorrect input types should throw.
    throws(() => lchmod(123), kInvalidArgTypeError);
    throws(() => lchmod('/', {}), kInvalidArgTypeError);
    throws(() => lchmod('/tmp', -1), kOutOfRangeError);

    async function callChmod(path) {
      const { promise, resolve, reject } = Promise.withResolvers();
      lchmod(path, 0o000, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    checkStat(path);
    await callChmod(path);
    checkStat(path);

    await callChmod(bufferPath);
    checkStat(bufferPath);

    await callChmod(urlPath);
    checkStat(bufferPath);

    const { promise, resolve, reject } = Promise.withResolvers();
    lchmod('/non-existent-path', 0o777, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'ENOENT',
      // Access because it is an access check under the covers.
      syscall: 'lchmod',
    });
  },
};

const lchmodPromiseTest = {
  async test() {
    // Incorrect input types should reject the promise.
    await rejects(promises.lchmod(123), kInvalidArgTypeError);
    await rejects(promises.lchmod('/', {}), kInvalidArgTypeError);
    await rejects(promises.lchmod('/tmp', -1), kOutOfRangeError);

    // Should be non-op
    checkStat(path);
    await promises.lchmod(path, 0o777);
    checkStat(path);

    await promises.lchmod(bufferPath, 0o777);
    checkStat(bufferPath);

    await promises.lchmod(urlPath, 0o777);
    checkStat(urlPath);

    await rejects(promises.lchmod('/non-existent-path', 0o777), {
      code: 'ENOENT',
      syscall: 'lchmod',
    });
  },
};

const fchmodSyncTest = {
  test() {
    // Incorrect input types should throw.
    throws(() => fchmodSync({}), kInvalidArgTypeError);
    throws(() => fchmodSync(123), kInvalidArgTypeError);
    throws(() => fchmodSync(123, {}), kInvalidArgTypeError);
    throws(() => fchmodSync(123, -1000), kOutOfRangeError);

    const fd = openSync('/tmp');

    // We stat the file before and after to verify the impact
    // of the fs.chown( operation. Specifically, the uid and gid
    // should not change since our impl is a non-op.
    checkfStat(fd);
    fchmodSync(fd, 0o777);
    checkfStat(fd);

    throws(() => fchmodSync(999, 0o777), {
      code: 'EBADF',
      syscall: 'fstat',
    });

    closeSync(fd);
  },
};

const fchmodCallbackTest = {
  async test() {
    // Incorrect input types should throw synchronously
    throws(() => fchmod({}), kInvalidArgTypeError);
    throws(() => fchmod(123), kInvalidArgTypeError);
    throws(() => fchmod(123, {}), kInvalidArgTypeError);

    const fd = openSync('/tmp');

    async function callChmod() {
      const { promise, resolve, reject } = Promise.withResolvers();
      fchmod(fd, 0o777, (err) => {
        if (err) return reject(err);
        resolve();
      });
      await promise;
    }

    // Should be non-op
    checkfStat(fd);
    await callChmod();
    checkfStat(fd);

    const { promise, resolve, reject } = Promise.withResolvers();
    fchmod(999, 0o777, (err) => {
      if (err) return reject(err);
      resolve();
    });
    await rejects(promise, {
      code: 'EBADF',
      syscall: 'fstat',
    });

    closeSync(fd);
  },
};

chownSyncTest.test();
await chownCallbackTest.test();
await chownPromiseTest.test();
lchownSyncTest.test();
await lchownCallbackTest.test();
await lchownPromiseTest.test();
fchownSyncTest.test();
chmodSyncTest.test();
await chmodCallbackTest.test();
await chmodPromiseTest.test();
lchmodSyncTest.test();
await lchmodCallbackTest.test();
fchmodSyncTest.test();
await lchmodPromiseTest.test();
await fchmodCallbackTest.test();