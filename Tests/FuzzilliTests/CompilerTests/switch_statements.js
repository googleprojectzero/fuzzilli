let fruit = 'apple';
for (let i = 0; i < 3; i++) {
  switch (fruit) {
    case 'apple': // test if this case falls through
      console.log('You selected an apple.');
      for (let j = 0; j < 2; j++) {
          console.log('Inside apple loop', j);
          if (j === 1) {
              break; // test if this break exits the inner loop
          }
      }
    case null:
        console.log('You selected null.');
        break; // Babel parses default case as null case. Try to confuse the compiler.
    default: // test if default case is detected (irrespective of the convention that the last case is the default case)
      console.log('Unknown fruit selection.'); // test falls through
      break; // test if this break exits the switch
    case 'banana':
      console.log('You selected a banana.');
      break; // test if this break exits the switch

  }
  if (i === 2) {
      break; // test if this break exits the outer loop
  }
}