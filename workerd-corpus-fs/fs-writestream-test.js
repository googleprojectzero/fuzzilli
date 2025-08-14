strictEqual(typeof fs.WriteStream, 'function');
strictEqual(typeof fs.createWriteStream, 'function');

const writeStreamTest1 = {
  async test() {
    const path = '/tmp/workerd-fs-fs.WriteStream-test1.txt';
    const { promise, resolve } = Promise.withResolvers();
    const stream = fs.WriteStream(path, {
      fs: {
        close(fd) {
          ok(fd);
          fs.closeSync(fd);
          resolve();
        },
      },
    });
    stream.destroy();
    await promise;
  },
};

const writeStreamTest2 = {
  async test() {
    const path = '/tmp/workerd-fs-fs.WriteStream-test2.txt';
    const stream = fs.createWriteStream(path);

    const { promise, resolve, reject } = Promise.withResolvers();

    stream.on('drain', reject);
    stream.on('close', resolve);
    stream.destroy();
    await promise;
  },
};

const writeStreamTest3 = {
  async test() {
    const path = '/tmp/workerd-fs-fs.WriteStream-test3.txt';
    const stream = fs.createWriteStream(path);
    const { promise, resolve, reject } = Promise.withResolvers();
    stream.on('error', reject);
    stream.on('close', resolve);
    throws(() => stream.write(42), {
      code: 'ERR_INVALID_ARG_TYPE',
      name: 'TypeError',
    });
    stream.destroy();
    await promise;
  },
};

const writeStreamTest4 = {
  test() {
    const example = '/tmp/workerd-fs-fs.WriteStream-test4.txt';
    fs.createWriteStream(example, undefined).end();
    fs.createWriteStream(example, null).end();
    fs.createWriteStream(example, 'utf8').end();
    fs.createWriteStream(example, { encoding: 'utf8' }).end();

    const createWriteStreamErr = (path, opt) => {
      throws(() => fs.createWriteStream(path, opt), {
        code: 'ERR_INVALID_ARG_TYPE',
        name: 'TypeError',
      });
    };

    createWriteStreamErr(example, 123);
    createWriteStreamErr(example, 0);
    createWriteStreamErr(example, true);
    createWriteStreamErr(example, false);
  },
};

const writeStreamTest5 = {
  async test() {
    const { promise, resolve } = Promise.withResolvers();
    fs.WriteStream.prototype.open = resolve;
    fs.createWriteStream('/tmp/test');
    await promise;
    delete fs.WriteStream.prototype.open;
  },
};

const writeStreamTest6 = {
  async test() {
    const path = '/tmp/write-end-test0.txt';
    const fs = {
      open: mock.fn(fs.open),
      write: mock.fn(fs.write),
      close: mock.fn(fs.close),
    };
    const { promise, resolve } = Promise.withResolvers();
    const stream = fs.createWriteStream(path, { fs });
    stream.on('close', resolve);
    stream.end('asd');

    await promise;
    strictEqual(fs.open.mock.callCount(), 1);
    strictEqual(fs.write.mock.callCount(), 1);
    strictEqual(fs.close.mock.callCount(), 1);
  },
};

const writeStreamTest7 = {
  async test() {
    const path = '/tmp/write-end-test1.txt';
    const fs = {
      open: mock.fn(fs.open),
      write: fs.write,
      writev: mock.fn(fs.write),
      close: mock.fn(fs.close),
    };
    const stream = fs.createWriteStream(path, { fs });
    stream.write('asd');
    stream.write('asd');
    stream.write('asd');
    stream.end();
    const { promise, resolve } = Promise.withResolvers();
    stream.on('close', resolve);
    await promise;

    strictEqual(fs.open.mock.callCount(), 1);
    strictEqual(fs.writev.mock.callCount(), 1);
    strictEqual(fs.close.mock.callCount(), 1);
  },
};

let cnt = 0;
function nextFile() {
  return `/tmp/${cnt++}.out`;
}

const writeStreamTest8 = {
  test() {
    for (const flush of ['true', '', 0, 1, [], {}, Symbol()]) {
      throws(
        () => {
          fs.createWriteStream(nextFile(), { flush });
        },
        { code: 'ERR_INVALID_ARG_TYPE' }
      );
    }
  },
};

const writeStreamTest9 = {
  async test() {
    const fs = {
      fsync: mock.fn(fs.fsync),
    };
    const stream = fs.createWriteStream(nextFile(), { flush: true, fs });

    const { promise, resolve, reject } = Promise.withResolvers();

    stream.write('hello', (err) => {
      if (err) return reject();
      stream.close((err) => {
        if (err) return reject(err);
        resolve();
      });
    });

    await promise;

    strictEqual(fs.fsync.mock.callCount(), 1);
  },
};

const writeStreamTest10 = {
  async test() {
    const values = [undefined, null, false];
    const fs = {
      fsync: mock.fn(fs.fsync),
    };
    let cnt = 0;

    const { promise, resolve, reject } = Promise.withResolvers();

    for (const flush of values) {
      const file = nextFile();
      const stream = fs.createWriteStream(file, { flush });
      stream.write('hello world', (err) => {
        if (err) return reject(err);
        stream.close((err) => {
          if (err) return reject(err);
          strictEqual(fs.readFileSync(file, 'utf8'), 'hello world');
          cnt++;
          if (cnt === values.length) {
            strictEqual(fs.fsync.mock.callCount(), 0);
            resolve();
          }
        });
      });
    }

    await promise;
  },
};

const writeStreamTest11 = {
  async test() {
    const file = nextFile();
    const handle = await promises.open(file, 'w');
    const stream = handle.fs.createWriteStream({ flush: true });

    const { promise, resolve, reject } = Promise.withResolvers();

    stream.write('hello', (err) => {
      if (err) return reject(err);
      stream.close((err) => {
        if (err) return reject(err);
        strictEqual(fs.readFileSync(file, 'utf8'), 'hello');
        resolve();
      });
    });

    await promise;
  },
};

const writeStreamTest12 = {
  async test() {
    const file = nextFile();
    const handle = await promises.open(file, 'w+');

    const { promise, resolve } = Promise.withResolvers();
    handle.on('close', resolve);
    const stream = fs.createWriteStream(null, { fd: handle });

    stream.end('hello');
    stream.on('close', () => {
      const output = fs.readFileSync(file, 'utf-8');
      strictEqual(output, 'hello');
    });

    await promise;
  },
};

const writeStreamTest13 = {
  async test() {
    const file = nextFile();
    const handle = await promises.open(file, 'w+');
    let calls = 0;
    const { write: originalWriteFunction, writev: originalWritevFunction } =
      handle;
    handle.write = mock.fn(handle.write.bind(handle));
    handle.writev = mock.fn(handle.writev.bind(handle));
    const stream = fs.createWriteStream(null, { fd: handle });
    stream.end('hello');
    const { promise, resolve } = Promise.withResolvers();
    stream.on('close', () => {
      console.log('test');
      ok(handle.write.mock.callCount() + handle.writev.mock.callCount() > 0);
      resolve();
    });
    await promise;
  },
};

const writeStreamTest14 = {
  async test() {
    const path = '/tmp/out';

    let writeCalls = 0;
    const fs = {
      write: mock.fn((...args) => {
        switch (writeCalls++) {
          case 0: {
            return fs.write(...args);
          }
          case 1: {
            args[args.length - 1](new Error('BAM'));
            break;
          }
          default: {
            // It should not be called again!
            throw new Error('BOOM!');
          }
        }
      }),
      close: mock.fn(fs.close),
    };

    const stream = fs.createWriteStream(path, {
      highWaterMark: 10,
      fs,
    });

    const { promise: errorPromise, resolve: errorResolve } =
      Promise.withResolvers();
    const { promise: writePromise, resolve: writeResolve } =
      Promise.withResolvers();

    stream.on('error', (err) => {
      strictEqual(stream.fd, null);
      strictEqual(err.message, 'BAM');
      errorResolve();
    });

    stream.write(Buffer.allocUnsafe(256), () => {
      stream.write(Buffer.allocUnsafe(256), (err) => {
        strictEqual(err.message, 'BAM');
        writeResolve();
      });
    });

    await Promise.all([errorPromise, writePromise]);
  },
};

const writeStreamTest15 = {
  async test() {
    const file = '/tmp/write-end-test0.txt';
    const stream = fs.createWriteStream(file);
    stream.end();
    const { promise, resolve } = Promise.withResolvers();
    stream.on('close', resolve);
    await promise;
  },
};

const writeStreamTest16 = {
  async test() {
    const file = '/tmp/write-end-test1.txt';
    const stream = fs.createWriteStream(file);
    stream.end('a\n', 'utf8');
    const { promise, resolve } = Promise.withResolvers();
    stream.on('close', () => {
      const content = fs.readFileSync(file, 'utf8');
      strictEqual(content, 'a\n');
      resolve();
    });
    await promise;
  },
};

const writeStreamTest17 = {
  async test() {
    const file = '/tmp/write-end-test2.txt';
    const stream = fs.createWriteStream(file);
    stream.end();

    const { promise: openPromise, resolve: openResolve } =
      Promise.withResolvers();
    const { promise: finishPromise, resolve: finishResolve } =
      Promise.withResolvers();
    stream.on('open', openResolve);
    stream.on('finish', finishResolve);
    await Promise.all([openPromise, finishPromise]);
  },
};

const writeStreamTest18 = {
  async test() {
    const examplePath = '/tmp/a';
    const dummyPath = '/tmp/b';
    const firstEncoding = 'base64';
    const secondEncoding = 'latin1';

    const exampleReadStream = fs.createReadStream(examplePath, {
      encoding: firstEncoding,
    });

    const dummyWriteStream = fs.createWriteStream(dummyPath, {
      encoding: firstEncoding,
    });

    const { promise, resolve } = Promise.withResolvers();
    exampleReadStream.pipe(dummyWriteStream).on('finish', () => {
      const assertWriteStream = new Writable({
        write: function (chunk, enc, next) {
          const expected = Buffer.from('xyz\n');
          deepStrictEqual(expected, chunk);
        },
      });
      assertWriteStream.setDefaultEncoding(secondEncoding);
      fs.createReadStream(dummyPath, {
        encoding: secondEncoding,
      })
        .pipe(assertWriteStream)
        .on('close', resolve);
    });

    await promise;
  },
};

const writeStreamTest19 = {
  async test() {
    const file = '/tmp/write-end-test3.txt';
    const stream = fs.createWriteStream(file);
    const { promise: closePromise1, resolve: closeResolve1 } =
      Promise.withResolvers();
    const { promise: closePromise2, resolve: closeResolve2 } =
      Promise.withResolvers();
    stream.close(closeResolve1);
    stream.close(closeResolve2);
    await Promise.all([closePromise1, closePromise2]);
  },
};

const writeStreamTest20 = {
  async test() {
    const file = '/tmp/write-autoclose-opt1.txt';
    let stream = fs.createWriteStream(file, { flags: 'w+', autoClose: false });
    stream.write('Test1');
    stream.end();
    const { promise, resolve, reject } = Promise.withResolvers();
    stream.on('finish', () => {
      stream.on('close', reject);
      process.nextTick(() => {
        strictEqual(stream.closed, false);
        notStrictEqual(stream.fd, null);
        resolve();
      });
    });
    await promise;

    const { promise: nextPromise, resolve: nextResolve } =
      Promise.withResolvers();
    const stream2 = fs.createWriteStream(null, { fd: stream.fd, start: 0 });
    stream2.write('Test2');
    stream2.end();
    stream2.on('finish', () => {
      strictEqual(stream2.closed, false);
      stream2.on('close', () => {
        strictEqual(stream2.fd, null);
        strictEqual(stream2.closed, true);
        nextResolve();
      });
    });

    await nextPromise;

    const data = fs.readFileSync(file, 'utf8');
    strictEqual(data, 'Test2');
  },
};

const writeStreamTest21 = {
  async test() {
    // This is to test success scenario where autoClose is true
    const file = '/tmp/write-autoclose-opt2.txt';
    const stream = fs.createWriteStream(file, { autoClose: true });
    stream.write('Test3');
    stream.end();
    const { promise, resolve } = Promise.withResolvers();
    stream.on('finish', () => {
      strictEqual(stream.closed, false);
      stream.on('close', () => {
        strictEqual(stream.fd, null);
        strictEqual(stream.closed, true);
        resolve();
      });
    });
    await promise;
  },
};

const writeStreamTest22 = {
  test() {
    throws(() => fs.WriteStream.prototype.autoClose, {
      code: 'ERR_INVALID_THIS',
    });
  },
};

await simpleWriteStreamTest.test();
await writeStreamTest1.test();
await writeStreamTest2.test();
await writeStreamTest3.test();
writeStreamTest4.test();
await writeStreamTest5.test();
await writeStreamTest6.test();
await writeStreamTest7.test();
writeStreamTest8.test();
await writeStreamTest9.test();
await writeStreamTest10.test();
await writeStreamTest11.test();
await writeStreamTest12.test();
await writeStreamTest13.test();
await writeStreamTest14.test();
await writeStreamTest15.test();
await writeStreamTest16.test();
await writeStreamTest17.test();
await writeStreamTest18.test();
await writeStreamTest19.test();
await writeStreamTest20.test();
await writeStreamTest21.test();
writeStreamTest22.test();