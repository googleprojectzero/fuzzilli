# Compiler Tests

An "end-to-end" testsuite for the JavaScript-to-FuzzIL compiler.

How these work:
- These testcases contain JavaScript snippets that produce some output using the `output` function
- During testing, every (original) testcase is executed in a JavaScript engine such as node.js
- The testcase is then compiled to FuzzIL, lifted back to JavaScript, and executed again
- The test passes if the output of both executions is identical (and if there were no errors)
