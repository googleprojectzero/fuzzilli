FUZZILLI_COMP = ./Compiler/_esy/default/build/default/bin/fuzzilli_compiler.exe
FUZZILLI_COMP_OPT = -v8-natives
FUZZILLI_COMP_OPT_PLACE = -use-placeholder
COMP_LOG = ./comp_log.txt

DIE_SRCS = $(shell find Corpus/die -type f -name "*.js")
DIE_OBJS = $(patsubst Corpus/die/%.js, corp_temp/die_%.fuzzil.protobuf, $(DIE_SRCS))
DIE_OBJS_PLACE = $(patsubst Corpus/die/%.js, corp_temp/die_place_%.fuzzil.protobuf, $(DIE_SRCS))

EXT_SRCS = $(shell find Corpus/extra -type f -name "*.js")
EXT_OBJS = $(patsubst Corpus/extra/%.js, corp_temp/ext_%.fuzzil.protobuf, $(EXT_SRCS))
EXT_OBJS_PLACE = $(patsubst Corpus/extra/%.js, corp_temp/ext_place_%.fuzzil.protobuf, $(EXT_SRCS))

REG_SRCS = $(shell find Corpus/regressions -type f -name "*.js")
REG_OBJS = $(patsubst Corpus/regressions/%.js, corp_temp/reg_%.fuzzil.protobuf, $(REG_SRCS))
REG_OBJS_PLACE = $(patsubst Corpus/regressions/%.js, corp_temp/reg_place_%.fuzzil.protobuf, $(REG_SRCS))

JSC_SRCS = $(shell find Corpus/javascriptcore -type f -name "*.js")
JSC_OBJS = $(patsubst Corpus/javascriptcore/%.js, corp_temp/jsc_%.fuzzil.protobuf, $(JSC_SRCS))
JSC_OBJS_PLACE = $(patsubst Corpus/javascriptcore/%.js, corp_temp/jsc_place_%.fuzzil.protobuf, $(JSC_SRCS))

SPM_SRCS = $(shell find Corpus/spidermonkey -type f -name "*.js")
SPM_OBJS = $(patsubst Corpus/spidermonkey/%.js, corp_temp/spm_%.fuzzil.protobuf, $(SPM_SRCS))
SPM_OBJS_PLACE = $(patsubst Corpus/spidermonkey/%.js, corp_temp/spm_place_%.fuzzil.protobuf, $(SPM_SRCS))

V8_SRCS = $(shell find Corpus/v8 -type f -name "*.js")
V8_OBJS = $(patsubst Corpus/v8/%.js, corp_temp/v8_%.fuzzil.protobuf, $(V8_SRCS))
V8_OBJS_PLACE = $(patsubst Corpus/v8/%.js, corp_temp/v8_place_%.fuzzil.protobuf, $(V8_SRCS))

all: corpus

corpus: $(DIE_OBJS) $(EXT_OBJS) $(REG_OBJS) $(JSC_OBJS) $(SPM_OBJS) $(V8_OBJS) $(DIE_OBJS_PLACE) $(EXT_OBJS_PLACE) $(REG_OBJS_PLACE) $(JSC_OBJS_PLACE) $(SPM_OBJS_PLACE) $(V8_OBJS_PLACE)

corp_temp/die_%.fuzzil.protobuf: Corpus/die/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/reg_%.fuzzil.protobuf: Corpus/regressions/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/ext_%.fuzzil.protobuf: Corpus/extra/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/jsc_%.fuzzil.protobuf: Corpus/javascriptcore/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/spm_%.fuzzil.protobuf: Corpus/spidermonkey/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@  > /dev/null

corp_temp/v8_%.fuzzil.protobuf: Corpus/v8/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null




corp_temp/die_place_%.fuzzil.protobuf: Corpus/die/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@ > /dev/null

corp_temp/reg_place_%.fuzzil.protobuf: Corpus/regressions/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@ > /dev/null

corp_temp/ext_place_%.fuzzil.protobuf: Corpus/extra/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@ > /dev/null

corp_temp/jsc_place_%.fuzzil.protobuf: Corpus/javascriptcore/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@ > /dev/null

corp_temp/spm_place_%.fuzzil.protobuf: Corpus/spidermonkey/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@  > /dev/null

corp_temp/v8_place_%.fuzzil.protobuf: Corpus/v8/%.js
	-timeout 1m $(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $(FUZZILLI_COMP_OPT_PLACE) $< $@ > /dev/null


clean:
	-rm -rf ./corp_temp
	-mkdir ./corp_temp
	-rm $(COMP_LOG)