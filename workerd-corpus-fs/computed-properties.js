function props() {
  // Computed property access
  let prop = 'Sync';
  let path = '/tmp/computed.txt';

  fs['writeFile' + prop](path, 'computed');
  fs['readFile' + prop](path);
  fs['unlink' + prop](path);
}