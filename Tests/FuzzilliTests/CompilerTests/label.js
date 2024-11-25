labelBlock: for (let i = 0; i < 1; i++) {
    console.log("Inside block");
    continue labelBlock; // Skips the rest of the code in this labeled block
    console.log("This will not run");
}
console.log("Outside block");

outerLoop1:
for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 3; j++) {
        if (j === 1) {
            continue outerLoop1;  // Skips to the next iteration of the outer loop
        }
        console.log(`i = ${i}, j = ${j}`);
    }
}

repeatLoop2: do {
    console.log("Running once");
    break repeatLoop2;
} while (false);

outerLoop3: while (true) {
    console.log("Looping...");
    break outerLoop3;
    console.log("Cannot be printed...");
}