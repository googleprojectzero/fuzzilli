#!/bin/bash

# get codebase
git clone https://github.com/nginx/njs.git


# add fuzzilli reprl shell
MODIF=''
MODIF+="\n"'# njs fuzzer(fuzzilli)'
MODIF+="\n"''
MODIF+="\n"'cat << END >> $NJS_MAKEFILE'
MODIF+="\n"''
MODIF+="\n"'$NJS_BUILD_DIR\/njs_fuzzilli: \\\\'
MODIF+="\n"'	$NJS_BUILD_DIR\/libnjs.a \\\\'
MODIF+="\n"'	external\/njs_fuzzilli.c'
MODIF+="\n"'	cp external\/njs_shell.c external\/njs_fuzzilli_shell.c'
MODIF+="\n"''
MODIF+="\n"'	.\/external\/gen-fuzzilli-shell.sh'
MODIF+="\n"'	'
MODIF+="\n"'	\\\$(NJS_CC) -c \\\$(NJS_LIB_INCS) \\\$(CFLAGS) \\\\'
MODIF+="\n"'		\\\$(NJS_LIB_AUX_CFLAGS) \\\\'
MODIF+="\n"'		-o $NJS_BUILD_DIR\/external\/njs_fuzzilli_shell.o \\\\'
MODIF+="\n"'		external\/njs_fuzzilli_shell.c'
MODIF+="\n"''
MODIF+="\n"'	\\\$(NJS_LINK) -o $NJS_BUILD_DIR\/njs_fuzzilli \\\$(NJS_LIB_INCS) \\\\'
MODIF+="\n"'		\\\$(NJS_CFLAGS) \\\$(NJS_LIB_AUX_CFLAGS)\\\\'
MODIF+="\n"'		external\/njs_fuzzilli.c \\\\'
MODIF+="\n"'		$NJS_BUILD_DIR\/libnjs.a \\\\'
MODIF+="\n"'		$NJS_LD_OPT -lm $NJS_LIBS $NJS_LIB_AUX_LIBS $NJS_READLINE_LIB'
MODIF+="\n"''
MODIF+="\n"'END'
MODIF+="\n"''
MODIF+="\n"'# lib tests.'
MODIF+="\n"''

NEEDLE='# lib tests.'

sed -i "s/$NEEDLE/$MODIF/" ./njs/auto/make


# add fuzzilli extension sources
cp mod/* ./njs/external/

cat << END >> ./njs/auto/modules

njs_module_name=njs_fuzzilli_module
njs_module_incs=
njs_module_srcs=external/njs_fuzzilli_module.c

. auto/module

END


# add `make njs_fuzzilli target`
NEEDLE='njs: $NJS_BUILD_DIR\/njs_auto_config.h $NJS_BUILD_DIR\/njs'

MODIF=''
MODIF+="\n"'njs_fuzzilli: $NJS_BUILD_DIR\/njs_fuzzilli'
MODIF+="\n"'njs: $NJS_BUILD_DIR\/njs_auto_config.h $NJS_BUILD_DIR\/njs'
MODIF+="\n"

sed -i "s/$NEEDLE/$MODIF/" ./njs/auto/make

echo "[+] Done preparing codebase"
