function dynamicCalls() {
  // Dynamic function calls
  let ops = ['writeFileSync', 'readFileSync', 'unlinkSync'];
  let path = '/tmp/dynamic.txt';

  fs[ops[0]](path, 'dynamic call');
  fs[ops[1]](path);
  fs[ops[2]](path);
}

