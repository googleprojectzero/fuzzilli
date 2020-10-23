FUZZILLI_COMP = ./Compiler/_esy/default/build/default/bin/fuzzilli_compiler.exe
FUZZILLI_COMP_OPT = 
COMP_LOG = ./comp_log.txt

DIE_SRCS = $(shell find Corpus/die -type f -name "*.js")
DIE_OBJS = $(patsubst Corpus/die/%.js, corp_temp/die_%.fuzzil.protobuf, $(DIE_SRCS))

EXT_SRCS = $(shell find Corpus/extra -type f -name "*.js")
EXT_OBJS = $(patsubst Corpus/extra/%.js, corp_temp/ext_%.fuzzil.protobuf, $(EXT_SRCS))

FUZZILLI_GENED_SRCS = $(shell find Corpus/regressions -type f -name "*.js")
FUZZILLI_GENED_OBJS = $(patsubst Corpus/regressions/%.js, corp_temp/reg_%.fuzzil.protobuf, $(FUZZILLI_GENED_SRCS))

JSC_SRCS = $(shell find Corpus/javascriptcore -type f -name "*.js")
JSC_OBJS = $(patsubst Corpus/javascriptcore/%.js, corp_temp/jsc_%.fuzzil.protobuf, $(JSC_SRCS))

SPM_SRCS = $(shell find Corpus/spidermonkey -type f -name "*.js")
SPM_OBJS = $(patsubst Corpus/spidermonkey/%.js, corp_temp/spm_%.fuzzil.protobuf, $(SPM_EXT_SRCS))

V8_SRCS = $(shell find Corpus/v8 -type f -name "*.js")
V8_OBJS = $(patsubst Corpus/v8/%.js, corp_temp/v8_%.fuzzil.protobuf, $(V8_EXT_SRCS))

all: corpus

corpus: $(DIE_OBJS) $(EXT_OBJS) $(FUZZILLI_GENED_OBJS) $(JSC_OBJS) $(SPM_OBJS) $(V8_OBJS)

corp_temp/die_%.fuzzil.protobuf: Corpus/die/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/reg_%.fuzzil.protobuf: Corpus/regressions/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/ext_%.fuzzil.protobuf: Corpus/extra/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/jsc_%.fuzzil.protobuf: Corpus/javascriptcore/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

corp_temp/spm_%.fuzzil.protobuf: Corpus/spidermonkey/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@  > /dev/null

corp_temp/v8_%.fuzzil.protobuf: Corpus/v8/%.js
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ > /dev/null

clean:
	-rm -rf ./corp_temp
	-mkdir ./corp_temp
	-rm $(COMP_LOG)