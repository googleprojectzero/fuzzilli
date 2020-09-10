FUZZILLI_COMP = ./Compiler/_esy/default/build/default/bin/fuzzilli_compiler.exe
FUZZILLI_COMP_OPT = -builtins
COMP_LOG = ./comp_log.txt

DIE_SRCS = $(shell find Corpus/die -type f -name "*.js")
DIE_OBJS = $(patsubst Corpus/die/%.js, corp_temp/die_%.il.protobuf, $(DIE_SRCS))

FUZZILLI_GENED_SRCS = $(shell find Corpus/regressions -type f -name "*.js")
FUZZILLI_GENED_OBJS = $(patsubst Corpus/regressions/%.js, corp_temp/reg_%.il.protobuf, $(FUZZILLI_GENED_SRCS))

JSC_SRCS = $(shell find Corpus/javascriptcore -type f -name "*.js")
JSC_OBJS = $(patsubst Corpus/javascriptcore/%.js, corp_temp/jsc_%.il.protobuf, $(JSC_SRCS))

JSC_EXT_SRCS = $(shell find Corpus/javascriptcore_extra -type f -name "*.js")
JSC_EXT_OBJS = $(patsubst Corpus/javascriptcore_extra/%.js, corp_temp/jscext_%.il.protobuf, $(JSC_EXT_SRCS))

SPM_EXT_SRCS = $(shell find Corpus/spidermonkey -type f -name "*.js")
SPM_EXT_OBJS = $(patsubst Corpus/spidermonkey/%.js, corp_temp/spm_%.il.protobuf, $(SPM_EXT_SRCS))

V8_EXT_SRCS = $(shell find Corpus/v8 -type f -name "*.js")
V8_EXT_OBJS = $(patsubst Corpus/v8/%.js, corp_temp/v8_%.il.protobuf, $(V8_EXT_SRCS))

all: corpus
	swift run -c release FuzzILTool --combineProtoDir=./corp_temp/

#corpus: $(DIE_OBJS) $(FUZZILLI_GENED_OBJS) $(JSC_OBJS) $(JSC_EXT_OBJS) $(SPM_EXT_OBJS) $(V8_EXT_OBJS)
corpus: $(FUZZILLI_GENED_OBJS) #$(SPM_EXT_OBJS) $(V8_EXT_OBJS)

.PHONY: combine
combine:
	swift run -c release FuzzILTool --combineProtoDir=./corp_temp/

corp_temp/die_%.il.protobuf: Corpus/die/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG)

corp_temp/reg_%.il.protobuf: Corpus/regressions/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG)

corp_temp/jsc_%.il.protobuf: Corpus/javascriptcore/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG)

corp_temp/jscext_%.il.protobuf: Corpus/javascriptcore_extra/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG)

corp_temp/spm_%.il.protobuf: Corpus/spidermonkey/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG) 

corp_temp/v8_%.il.protobuf: Corpus/v8/%.js
	echo $< >> $(COMP_LOG)
	$(FUZZILLI_COMP) $(FUZZILLI_COMP_OPT) $< $@ >> $(COMP_LOG)

clean:
	-rm ./corp_temp/*
	-rm $(COMP_LOG)