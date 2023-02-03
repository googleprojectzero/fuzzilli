if (typeof output === 'undefined') output = console.log;

function foo() {
  return 42;
}
output(%GetOptimizationStatus(foo));
foo();
%PrepareFunctionForOptimization(foo);
foo();
%OptimizeFunctionOnNextCall(foo);
foo();
output(%GetOptimizationStatus(foo));

