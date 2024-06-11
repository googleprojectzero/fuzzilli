#!/bin/bash

NEEDLE='main(int argc, char \*\*argv)'
MODIF='not_main(int argc, char \*\*argv)'
sed -i "s/$NEEDLE/$MODIF/" ./external/njs_fuzzilli_shell.c

sed -i '1s/^/int not_main(int argc, char **argv);\n/' ./external/njs_fuzzilli_shell.c