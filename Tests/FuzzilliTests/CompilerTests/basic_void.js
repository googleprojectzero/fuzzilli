const output = void 1;
console.log(output);
// Expected output: undefined

void console.log('expression evaluated');
// Expected output: "expression evaluated"

void (function iife() {
  console.log('iife is executed');
})();