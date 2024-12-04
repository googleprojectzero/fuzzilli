output(void 1);
// Expected output: undefined

void output('expression evaluated');
// Expected output: "expression evaluated"

void (function iife() {
  output('iife is executed');
})();
