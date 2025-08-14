strictEqual(typeof fs.ReadStream, 'function');
strictEqual(typeof fs.createReadStream, 'function');

const simpleReadStreamTest = {
  async test() {
    const largeData = 'abc'.repeat(100_000);
    fs.writeFileSync('/tmp/foo', largeData);

    const stream = fs.createReadStream('/tmp/foo', {
      encoding: 'utf8',
      highWaterMark: 10_000,
    });

    let data = '';
    for await (const chunk of stream) {
      data += chunk;
    }
    strictEqual(data, largeData);
  },
};

function prepareFile() {
  const path = '/tmp/elipses.txt';
  fs.writeFileSync(path, '…'.repeat(10000));
  return path;
}

async function runTest(options) {
  let paused = false;
  let bytesRead = 0;

  const path = prepareFile();

  const file = fs.createReadStream(path, options);
  const fileSize = fs.statSync(path).size;

  strictEqual(file.bytesRead, 0);

  const promises = [];

  const { promise: openPromise, resolve: openResolve } =
    Promise.withResolvers();
  const { promise: endPromise, resolve: endResolve } = Promise.withResolvers();
  const { promise: closePromise, resolve: closeResolve } =
    Promise.withResolvers();
  promises.push(openPromise);
  promises.push(endPromise);
  promises.push(closePromise);

  const onOpen = mock.fn((fd) => {
    file.length = 0;
    strictEqual(typeof fd, 'number');
    strictEqual(file.bytesRead, 0);
    ok(file.readable);
    file.pause();
    file.resume();
    file.pause();
    file.resume();
    openResolve();
  });

  const onData = mock.fn((data) => {
    ok(data instanceof Buffer);
    ok(data.byteOffset % 8 === 0);
    ok(!paused);
    file.length += data.length;

    bytesRead += data.length;
    strictEqual(file.bytesRead, bytesRead);

    paused = true;
    file.pause();

    setTimeout(function () {
      paused = false;
      file.resume();
    }, 10);
  });

  const onEnd = mock.fn(() => {
    strictEqual(bytesRead, fileSize);
    strictEqual(file.bytesRead, fileSize);
    endResolve();
  });

  const onClose = mock.fn(() => {
    strictEqual(bytesRead, fileSize);
    strictEqual(file.bytesRead, fileSize);
    closeResolve();
  });

  file.once('open', onOpen);
  file.once('end', onEnd);
  file.once('close', onClose);
  file.on('data', onData);

  await Promise.all(fs.promises);

  strictEqual(file.length, 30000);
  strictEqual(onOpen.mock.callCount(), 1);
  strictEqual(onEnd.mock.callCount(), 1);
  strictEqual(onClose.mock.callCount(), 1);
  strictEqual(onData.mock.callCount(), 1);
}

const readStreamTest1 = {
  async test() {
    await runTest({});
  },
};

const readStreamTest2 = {
  async test() {
    const customFs = {
      open: mock.fn((...args) => fs.open(...args)),
      read: mock.fn((...args) => fs.read(...args)),
      close: mock.fn((...args) => fs.close(...args)),
    };
    await runTest({
      fs: customFs,
    });
    strictEqual(customFs.open.mock.callCount(), 1);
    strictEqual(customFs.read.mock.callCount(), 2);
    strictEqual(customFs.close.mock.callCount(), 1);
  },
};

const readStreamTest3 = {
  async test() {
    const path = prepareFile();
    const file = fs.createReadStream(path, { encoding: 'utf8' });
    file.length = 0;
    file.on('data', function (data) {
      strictEqual(typeof data, 'string');
      file.length += data.length;

      for (let i = 0; i < data.length; i++) {
        // http://www.fileformat.info/info/unicode/char/2026/index.htm
        strictEqual(data[i], '\u2026');
      }
    });

    const { promise, resolve } = Promise.withResolvers();
    file.on('close', resolve);

    await promise;

    strictEqual(file.length, 10000);
  },
};

const readStreamTest4 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz');
    const file = fs.createReadStream(path, { bufferSize: 1, start: 1, end: 2 });
    let contentRead = '';
    file.on('data', function (data) {
      contentRead += data.toString('utf-8');
    });
    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function (data) {
      strictEqual(contentRead, 'yz');
      resolve();
    });
    await promise;
  },
};

const readStreamTest5 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const file = fs.createReadStream(path, { bufferSize: 1, start: 1 });
    file.data = '';
    file.on('data', function (data) {
      file.data += data.toString('utf-8');
    });
    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(file.data, 'yz\n');
      resolve();
    });
    await promise;
  },
};

const readStreamTest6 = {
  async test() {
    // Ref: https://github.com/nodejs/node-v0.x-archive/issues/2320
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const file = fs.createReadStream(path, { bufferSize: 1.23, start: 1 });
    file.data = '';
    file.on('data', function (data) {
      file.data += data.toString('utf-8');
    });
    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(file.data, 'yz\n');
      resolve();
    });
    await promise;
  },
};

const readStreamTest7 = {
  test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    throws(() => fs.createReadStream(path, { start: 10, end: 2 }), {
      code: 'ERR_OUT_OF_RANGE',
      name: 'RangeError',
    });
  },
};

const readStreamTest8 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const stream = fs.createReadStream(path, { start: 0, end: 0 });
    stream.data = '';

    stream.on('data', function (chunk) {
      stream.data += chunk;
    });
    const { promise, resolve } = Promise.withResolvers();
    stream.on('end', function () {
      strictEqual(stream.data, 'x');
      resolve();
    });
    await promise;
  },
};

const readStreamTest9 = {
  async test() {
    // Verify that end works when start is not specified.
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const stream = new fs.createReadStream(path, { end: 1 });
    stream.data = '';

    stream.on('data', function (chunk) {
      stream.data += chunk;
    });

    const { promise, resolve } = Promise.withResolvers();
    stream.on('end', function () {
      strictEqual(stream.data, 'xy');
      resolve();
    });
    await promise;
  },
};

const readStreamTest10 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    let file = fs.createReadStream(path, { autoClose: false });
    let data = '';
    file.on('data', function (chunk) {
      data += chunk;
    });
    const { promise, resolve, reject } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(data, 'xyz\n');
      process.nextTick(function () {
        ok(!file.closed);
        ok(!file.destroyed);
        fileNext().then(resolve, reject);
      });
    });

    await promise;

    async function fileNext() {
      // This will tell us if the fd is usable again or not.
      file = fs.createReadStream(null, { fd: file.fd, start: 0 });
      file.data = '';
      file.on('data', function (data) {
        file.data += data;
      });
      const { promise, resolve } = Promise.withResolvers();
      const { promise: endPromise, resolve: endResolve } =
        Promise.withResolvers();
      file.on('end', function (err) {
        strictEqual(file.data, 'xyz\n');
        endResolve();
      });
      file.on('close', resolve);
      await Promise.all([promise, endPromise]);
      ok(file.closed);
      ok(file.destroyed);
    }
  },
};

const readStreamTest11 = {
  async test() {
    // Just to make sure autoClose won't close the stream because of error.
    const { promise, resolve, reject } = Promise.withResolvers();
    const file = fs.createReadStream(null, { fd: 13337, autoClose: false });
    file.on('data', () => reject(new Error('should not be called')));
    file.on('error', resolve);
    await promise;
    ok(!file.closed);
    ok(!file.destroyed);
    ok(file.fd);
  },
};

const readStreamTest12 = {
  async test() {
    // Make sure stream is destroyed when file does not exist.
    const file = fs.createReadStream('/path/to/file/that/does/not/exist');
    const { promise, resolve, reject } = Promise.withResolvers();
    file.on('data', () => reject(new Error('should not be called')));
    file.on('error', resolve);
    await promise;
    ok(file.closed);
    ok(file.destroyed);
  },
};

const readStreamTest13 = {
  async test() {
    const example = '/tmp/x.txt';
    fs.writeFileSync(example, 'xyz\n');
    fs.createReadStream(example, undefined);
    fs.createReadStream(example, null);
    fs.createReadStream(example, 'utf8');
    fs.createReadStream(example, { encoding: 'utf8' });

    const createReadStreamErr = (path, opt, error) => {
      throws(() => fs.createReadStream(path, opt), error);
    };

    const typeError = {
      code: 'ERR_INVALID_ARG_TYPE',
      name: 'TypeError',
    };

    const rangeError = {
      code: 'ERR_OUT_OF_RANGE',
      name: 'RangeError',
    };

    [123, 0, true, false].forEach((opts) =>
      createReadStreamErr(example, opts, typeError)
    );

    // Case 0: Should not throw if either start or end is undefined
    [{}, { start: 0 }, { end: Infinity }].forEach((opts) =>
      fs.createReadStream(example, opts)
    );

    // Case 1: Should throw TypeError if either start or end is not of type 'number'
    [
      { start: 'invalid' },
      { end: 'invalid' },
      { start: 'invalid', end: 'invalid' },
    ].forEach((opts) => createReadStreamErr(example, opts, typeError));

    // Case 2: Should throw RangeError if either start or end is NaN
    [{ start: NaN }, { end: NaN }, { start: NaN, end: NaN }].forEach((opts) =>
      createReadStreamErr(example, opts, rangeError)
    );

    // Case 3: Should throw RangeError if either start or end is negative
    [{ start: -1 }, { end: -1 }, { start: -1, end: -1 }].forEach((opts) =>
      createReadStreamErr(example, opts, rangeError)
    );

    // Case 4: Should throw RangeError if either start or end is fractional
    [{ start: 0.1 }, { end: 0.1 }, { start: 0.1, end: 0.1 }].forEach((opts) =>
      createReadStreamErr(example, opts, rangeError)
    );

    // Case 5: Should not throw if both start and end are whole numbers
    fs.createReadStream(example, { start: 1, end: 5 });

    // Case 6: Should throw RangeError if start is greater than end
    createReadStreamErr(example, { start: 5, end: 1 }, rangeError);

    // Case 7: Should throw RangeError if start or end is not safe integer
    const NOT_SAFE_INTEGER = 2 ** 53;
    [
      { start: NOT_SAFE_INTEGER, end: Infinity },
      { start: 0, end: NOT_SAFE_INTEGER },
    ].forEach((opts) => createReadStreamErr(example, opts, rangeError));
  },
};

const readStreamTest14 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    let data = '';
    let first = true;

    const stream = fs.createReadStream(path);
    stream.setEncoding('utf8');
    stream.on('data', function (chunk) {
      data += chunk;
      if (first) {
        first = false;
        stream.resume();
      }
    });

    const { promise, resolve } = Promise.withResolvers();

    process.nextTick(function () {
      stream.pause();
      setTimeout(function () {
        stream.resume();
        resolve();
      }, 100);
    });

    await promise;
    strictEqual(data, 'xyz\n');
  },
};

const readStreamTest15 = {
  async test() {
    const { promise, resolve } = Promise.withResolvers();
    fs.ReadStream.prototype.open = resolve;
    fs.createReadStream('asd');
    await promise;
    delete fs.ReadStream.prototype.open;
  },
};

// const fn = fixtures.path('elipses.txt');
// const rangeFile = fixtures.path('x.txt');

const readStreamTest16 = {
  async test() {
    let paused = false;
    const path = prepareFile();

    const file = fs.ReadStream(path);

    const promises = [];
    const { promise: openPromise, resolve: openResolve } =
      Promise.withResolvers();
    const { promise: endPromise, resolve: endResolve } =
      Promise.withResolvers();
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();
    promises.push(openPromise);
    promises.push(endPromise);
    promises.push(closePromise);

    file.on('open', function (fd) {
      file.length = 0;
      strictEqual(typeof fd, 'number');
      ok(file.readable);

      // GH-535
      file.pause();
      file.resume();
      file.pause();
      file.resume();
      openResolve();
    });

    file.on('data', function (data) {
      ok(data instanceof Buffer);
      ok(!paused);
      file.length += data.length;

      paused = true;
      file.pause();

      setTimeout(function () {
        paused = false;
        file.resume();
      }, 10);
    });

    file.on('end', endResolve);

    file.on('close', function () {
      strictEqual(file.length, 30000);
      closeResolve();
    });

    await Promise.all(fs.promises);
  },
};

const readStreamTest17 = {
  async test() {
    const path = prepareFile();
    const file = fs.createReadStream(path, { __proto__: { encoding: 'utf8' } });
    file.length = 0;
    file.on('data', function (data) {
      strictEqual(typeof data, 'string');
      file.length += data.length;

      for (let i = 0; i < data.length; i++) {
        // http://www.fileformat.info/info/unicode/char/2026/index.htm
        strictEqual(data[i], '\u2026');
      }
    });

    const { promise, resolve } = Promise.withResolvers();
    file.on('close', function () {
      strictEqual(file.length, 10000);
      resolve();
    });

    await promise;
  },
};

const readStreamTest18 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const options = { __proto__: { bufferSize: 1, start: 1, end: 2 } };
    const file = fs.createReadStream(path, options);
    strictEqual(file.start, 1);
    strictEqual(file.end, 2);
    let contentRead = '';
    file.on('data', function (data) {
      contentRead += data.toString('utf-8');
    });

    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(contentRead, 'yz');
      resolve();
    });
    await promise;
  },
};

const readStreamTest19 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const options = { __proto__: { bufferSize: 1, start: 1 } };
    const file = fs.createReadStream(path, options);
    strictEqual(file.start, 1);
    file.data = '';
    file.on('data', function (data) {
      file.data += data.toString('utf-8');
    });
    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(file.data, 'yz\n');
      resolve();
    });
    await promise;
  },
};

// https://github.com/joyent/node/issues/2320
const readStreamTest20 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const options = { __proto__: { bufferSize: 1.23, start: 1 } };
    const file = fs.createReadStream(path, options);
    strictEqual(file.start, 1);
    file.data = '';
    file.on('data', function (data) {
      file.data += data.toString('utf-8');
    });
    const { promise, resolve } = Promise.withResolvers();
    file.on('end', function () {
      strictEqual(file.data, 'yz\n');
      resolve();
    });
    await promise;
  },
};

const readStreamTest21 = {
  test() {
    const path = '/tmp/x.txt';
    throws(() => fs.createReadStream(path, { __proto__: { start: 10, end: 2 } }), {
      code: 'ERR_OUT_OF_RANGE',
      name: 'RangeError',
    });
  },
};

const readStreamTest22 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const options = { __proto__: { start: 0, end: 0 } };
    const stream = fs.createReadStream(path, options);
    strictEqual(stream.start, 0);
    strictEqual(stream.end, 0);
    stream.data = '';

    stream.on('data', function (chunk) {
      stream.data += chunk;
    });

    const { promise, resolve } = Promise.withResolvers();
    stream.on('end', function () {
      strictEqual(stream.data, 'x');
      resolve();
    });
    await promise;
  },
};

const readStreamTest23 = {
  async test() {
    const path = '/tmp/x.txt';
    let output = '';
    fs.writeFileSync(path, 'hello world');
    const fd = fs.openSync(path, 'r');
    const stream = fs.createReadStream(null, { fd: fd, encoding: 'utf8' });
    strictEqual(stream.path, undefined);
    stream.on('data', (data) => {
      output += data;
    });
    const { promise, resolve } = Promise.withResolvers();
    stream.on('close', resolve);
    await promise;
    strictEqual(output, 'hello world');
  },
};

const readStreamTest24 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'hello world');
    const stream = fs.createReadStream(path);
    const { promise: promise1, resolve: resolve1 } = Promise.withResolvers();
    const { promise: promise2, resolve: resolve2 } = Promise.withResolvers();
    stream.close(resolve1);
    stream.close(resolve2);
    await Promise.all([promise1, promise2]);
  },
};

const readStreamTest25 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'hello world');
    const stream = fs.createReadStream(path);
    const { promise: promise1, resolve: resolve1 } = Promise.withResolvers();
    const { promise: promise2, resolve: resolve2 } = Promise.withResolvers();
    stream.destroy(null, resolve1);
    stream.destroy(null, resolve2);
    await Promise.all([promise1, promise2]);
  },
};

const readStreamTest26 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'hello world');
    const fh = await fs.promises.open(path, 'r');
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();
    fh.on('close', closeResolve);
    const stream = fs.createReadStream(null, { fd: fh, encoding: 'utf8' });
    let data = '';
    stream.on('data', (chunk) => (data += chunk));
    const { promise, resolve } = Promise.withResolvers();
    stream.on('end', () => resolve());
    await Promise.all([promise, closePromise]);
    strictEqual(data, 'hello world');
    strictEqual(fh.fd, undefined);
  },
};

const readStreamTest27 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    const { promise, resolve, reject } = Promise.withResolvers();
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();
    handle.on('close', resolve);
    const stream = fs.createReadStream(null, { fd: handle });
    stream.on('data', reject);
    stream.on('close', closeResolve);
    handle.close();
    await Promise.all([[promise, closePromise]]);
  },
};

const readStreamTest28 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    const { promise: handlePromise, resolve: handleResolve } =
      Promise.withResolvers();
    const { promise: streamPromise, resolve: streamResolve } =
      Promise.withResolvers();
    handle.on('close', handleResolve);
    const stream = fs.createReadStream(null, { fd: handle });
    stream.on('close', streamResolve);
    stream.on('data', () => handle.close());
    await Promise.all([handlePromise, streamPromise]);
  },
};

const readStreamTest29 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    const { promise: handlePromise, resolve: handleResolve } =
      Promise.withResolvers();
    const { promise: streamPromise, resolve: streamResolve } =
      Promise.withResolvers();
    handle.on('close', handleResolve);
    const stream = fs.createReadStream(null, { fd: handle });
    stream.on('close', streamResolve);
    stream.close();
    await Promise.all([handlePromise, streamPromise]);
  },
};

const readStreamTest30 = {
  async test() {
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    throws(() => fs.createReadStream(null, { fd: handle, fs: {} }), {
      code: 'ERR_METHOD_NOT_IMPLEMENTED',
    });
    handle.close();
  },
};

const readStreamTest31 = {
  async test() {
    // AbortSignal option test
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    const controller = new AbortController();
    const { signal } = controller;
    const stream = handle.fs.createReadStream({ signal });

    stream.on('data', () => {
      throw new Error('boom');
    });
    stream.on('end', () => {
      throw new Error('boom');
    });

    const { promise: errorPromise, resolve: errorResolve } =
      Promise.withResolvers();
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();
    stream.on('error', (err) => {
      strictEqual(err.name, 'AbortError');
      errorResolve();
    });

    handle.on('close', closeResolve);
    stream.on('close', () => handle.close());

    controller.abort();

    await Promise.all([errorPromise, closePromise]);
  },
};

const readStreamTest32 = {
  async test() {
    // Already-aborted signal test
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');

    const signal = AbortSignal.abort();
    const stream = handle.fs.createReadStream({ signal });

    stream.on('data', () => {
      throw new Error('boom');
    });
    stream.on('end', () => {
      throw new Error('boom');
    });

    const { promise: errorPromise, resolve: errorResolve } =
      Promise.withResolvers();
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();

    stream.on('error', (err) => {
      strictEqual(err.name, 'AbortError');
      errorResolve();
    });

    handle.on('close', closeResolve);
    stream.on('close', () => handle.close());

    await Promise.all([errorPromise, closePromise]);
  },
};

const readStreamTest33 = {
  async test() {
    // Invalid signal type test
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');

    for (const signal of [
      1,
      {},
      [],
      '',
      NaN,
      1n,
      () => { },
      Symbol(),
      false,
      true,
    ]) {
      throws(() => handle.fs.createReadStream({ signal }), {
        code: 'ERR_INVALID_ARG_TYPE',
        name: 'TypeError',
      });
    }
    handle.close();
  },
};

const readStreamTest34 = {
  async test() {
    // Custom abort reason test
    const path = '/tmp/x.txt';
    fs.writeFileSync(path, 'xyz\n');
    const handle = await fs.promises.open(path, 'r');
    const controller = new AbortController();
    const { signal } = controller;
    const reason = new Error('some silly abort reason');
    const stream = handle.fs.createReadStream({ signal });

    const { promise: errorPromise, resolve: errorResolve } =
      Promise.withResolvers();
    const { promise: closePromise, resolve: closeResolve } =
      Promise.withResolvers();

    stream.on('error', (err) => {
      strictEqual(err.name, 'AbortError');
      strictEqual(err.cause, reason);
      errorResolve();
    });

    handle.on('close', closeResolve);
    stream.on('close', () => handle.close());

    controller.abort(reason);

    await Promise.all([errorPromise, closePromise]);
  },
};

const emptyReadStreamTest = {
  async test() {
    fs.writeFileSync('/tmp/empty.txt', '');
    const stream = fs.createReadStream('/tmp/empty.txt');
    const { promise, resolve, reject } = Promise.withResolvers();
    stream.once('data', () => {
      reject(new Error('should not emit data'));
    });
    stream.once('end', resolve);
    await promise;
    strictEqual(stream.bytesRead, 0);
  },
};

const fileHandleReadableWebStreamTest = {
  async test() {
    fs.writeFileSync('/tmp/stream.txt', 'abcde'.repeat(1000));
    const fh = await fs.promises.open('/tmp/stream.txt', 'r');
    const stream = fh.readableWebStream();
    const enc = new TextEncoder();
    let data = '';
    for await (const chunk of stream) {
      strictEqual(chunk instanceof Uint8Array, true);
      data += new TextDecoder().decode(chunk);
    }
    strictEqual(data, 'abcde'.repeat(1000));
    strictEqual(fh.fd, undefined);

    // Should throw if the stream is closed.
    throws(() => fh.readableWebStream(), {
      code: 'EBADF',
    });

    const fh2 = await fs.promises.open('/tmp/stream.txt', 'r');
    const stream2 = fh2.readableWebStream({ autoClose: false });
    await fh2.close();
    const res = await stream2.getReader().read();
    strictEqual(res.done, true);
    strictEqual(res.value, undefined);
  },
};

/**
 * TODO(node-fs): Revisit
 * Temporarily comment out. These are larger tests causing timeouts
 * In CI. Will move them out to separate tests in a follow on PR
const readStreamTest98 = {
  async test() {
    const path = prepareFile();
    const content = fs.readFileSync(path);

    const N = 20;
    let started = 0;
    let done = 0;

    const arrayBuffers = new Set();
    const fs.promises = [];

    async function startRead() {
      ++started;
      const chunks = [];
      const fs.promises = [];
      const { promise, resolve } = Promise.withResolvers();
      fs.promises.push(promise);
      fs.createReadStream(path)
        .on('data', (chunk) => {
          chunks.push(chunk);
          arrayBuffers.add(chunk.buffer);
        })
        .on('end', () => {
          if (started < N) fs.promises.push(startRead());
          deepStrictEqual(Buffer.concat(chunks), content);
          if (++done === N) {
            const retainedMemory = [...arrayBuffers]
              .map((ab) => ab.byteLength)
              .reduce((a, b) => a + b);
            ok(
              retainedMemory / (N * content.length) <= 3,
              `Retaining ${retainedMemory} bytes in ABs for ${N} ` +
                `chunks of size ${content.length}`
            );
          }
          resolve();
        });
      await Promise.all(fs.promises);
    }

    // Don’t start the reads all at once – that way we would have to allocate
    // a large amount of memory upfront.
    for (let i = 0; i < 6; ++i) {
      fs.promises.push(startRead());
    }
    await Promise.all(fs.promises);
  },
};

const readStreamTest99 = {
  async test() {
    const path = '/tmp/read_stream_pos_test.txt';
    fs.writeFileSync(path, '');

    let counter = 0;

    const writeInterval = setInterval(() => {
      counter = counter + 1;
      const line = `hello at ${counter}\n`;
      fs.writeFileSync(path, line, { flag: 'a' });
    }, 1);

    const hwm = 10;
    let bufs = [];
    let isLow = false;
    let cur = 0;
    let stream;

    const readInterval = setInterval(() => {
      if (stream) return;

      stream = fs.createReadStream(path, {
        highWaterMark: hwm,
        start: cur,
      });
      stream.on('data', (chunk) => {
        cur += chunk.length;
        bufs.push(chunk);
        if (isLow) {
          const brokenLines = Buffer.concat(bufs)
            .toString()
            .split('\n')
            .filter((line) => {
              const s = 'hello at'.slice(0, line.length);
              if (line && !line.startsWith(s)) {
                return true;
              }
              return false;
            });
          strictEqual(brokenLines.length, 0);
          exitTest();
          return;
        }
        if (chunk.length !== hwm) {
          isLow = true;
        }
      });
      stream.on('end', () => {
        stream = null;
        isLow = false;
        bufs = [];
      });
    }, 10);

    // Time longer than 10 seconds to exit safely
    await scheduler.wait(5_000);

    clearInterval(readInterval);
    clearInterval(writeInterval);

    if (stream && !stream.destroyed) {
      const { promise, resolve } = Promise.withResolvers();
      stream.on('close', resolve);
      stream.destroy();
      await promise;
    }
  },
};
**/
