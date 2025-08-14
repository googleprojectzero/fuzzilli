// Copyright (c) 2017-2025 Cloudflare, Inc.
// Licensed under the Apache 2.0 license found in the LICENSE file or at:
//     https://opensource.org/licenses/Apache-2.0
const kInvalidArgTypeError = { code: 'ERR_INVALID_ARG_TYPE' };

function checkStat(path, mtimeMsCheck) {
  const bigint = typeof mtimeMsCheck === 'bigint';
  const { atimeMs, mtimeMs, ctimeMs, birthtimeMs } =
    typeof path === 'number'
      ? ffs.statSync(path, { bigint })
      : fs.statSync(path, { bigint });
  strictEqual(mtimeMs, mtimeMsCheck);
  strictEqual(ctimeMs, mtimeMsCheck);
  strictEqual(atimeMs, bigint ? 0n : 0);
  strictEqual(birthtimeMs, bigint ? 0n : 0);
}

const utimesTest = {
  async test() {
    const fd = fs.openSync('/tmp/test.txt', 'w+');
    ok(existsSync('/tmp/test.txt'));

    checkStat(fd, 0n);

    fs.utimesSync('/tmp/test.txt', 1000, 2000);
    checkStat(fd, 2000n);

    fs.utimesSync('/tmp/test.txt', 1000, new Date(0));
    checkStat(fd, 0);

    fs.utimesSync('/tmp/test.txt', 3000, '1970-01-01T01:00:00.000Z');
    checkStat(fd, 3600000n);

    fs.lutimesSync('/tmp/test.txt', 3000, 4000);
    checkStat(fd, 4000n);

    fs.lutimesSync('/tmp/test.txt', 1000, new Date(0));
    checkStat(fd, 0);

    fs.lutimesSync('/tmp/test.txt', 3000, '1970-01-01T01:00:00.000Z');
    checkStat(fd, 3600000n);

    fs.futimesSync(fd, 5000, 6000);
    checkStat(fd, 6000n);

    fs.futimesSync(fd, 1000, new Date(0));
    checkStat(fd, 0);

    fs.futimesSync(fd, 3000, '1970-01-01T01:00:00.000Z');
    checkStat(fd, 3600000n);

    {
      const { promise, resolve, reject } = Promise.withResolvers();
      fs.utims('/tmp/test.txt', 8000, new Date('not a valid date'), (err) => {
        try {
          ok(err);
          strictEqual(err.name, 'TypeError');
          match(err.message, /The value cannot be converted/);
          resolve();
        } catch (err) {
          reject(err);
        }
      });
      await promise;
    }

    {
      const { promise, resolve, reject } = Promise.withResolvers();
      fs.utims('/tmp/test.txt', 8000, 9000, (err) => {
        if (err) return reject(err);
        try {
          checkStat(fd, 9000n);
          resolve();
        } catch (err) {
          reject(err);
        }
      });
      await promise;
    }

    {
      const { promise, resolve, reject } = Promise.withResolvers();
      fs.lutimes('/tmp/test.txt', 8000, 10000, (err) => {
        if (err) return reject(err);
        try {
          checkStat(fd, 10000n);
          resolve();
        } catch (err) {
          reject(err);
        }
      });
      await promise;
    }

    {
      const { promise, resolve, reject } = Promise.withResolvers();
      fs.futimes(fd, 7000, 11000, (err) => {
        if (err) return reject(err);
        try {
          checkStat(fd, 11000n);
          resolve();
        } catch (err) {
          reject(err);
        }
      });
      await promise;
    }

    await promises.fs.utims('/tmp/test.txt', 12000, 13000);
    checkStat(fd, 13000n);
    await promises.fs.lutimes('/tmp/test.txt', 14000, 15000);
    checkStat(fd, 15000n);

    fs.closeSync(fd);
  },
};
