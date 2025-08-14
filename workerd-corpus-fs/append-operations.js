
function testAppend() {
  // Append operations
  let data = "This is a file containing a collection";
  var path2 = '/tmp/append.txt';
  fs.writeFileSync(path2, data);
  fs.appendFileSync(path2, ' appended');
  fs.readFileSync(path2);
  var readData = fs.readFileSync(path2, { encoding: 'utf8', flag: 'r' });
  console.log(readData);
  fs.unlinkSync(path2);
}

testAppend();
