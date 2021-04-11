COMP = ./Compiler/_esy/default/store/b/fuzzilli__compiler-b40826ba/default/bin/fuzzilli_compiler.exe

SRC_DIR = Corpus/die
OBJ_DIR = corp2
SRC_FILES := $(wildcard $(SRC_DIR)/*.js)
OBJ_FILES := $(patsubst $(SRC_DIR)/%.js,$(OBJ_DIR)/%.fuzzil.2.protobuf,$(SRC_FILES))

SRC_DIR_j = Corpus/javascriptcore
OBJ_DIR_j = corp2
SRC_FILES_j := $(wildcard $(SRC_DIR_j)/*.js)
OBJ_FILES_j := $(patsubst $(SRC_DIR_j)/%.js,$(OBJ_DIR_j)/%.fuzzil.2.protobuf,$(SRC_FILES_j))

SRC_DIR_s = Corpus/spidermonkey
OBJ_DIR_s = corp2
SRC_FILES_s := $(wildcard $(SRC_DIR_s)/*.js)
OBJ_FILES_s := $(patsubst $(SRC_DIR_s)/%.js,$(OBJ_DIR_s)/%.fuzzil.2.protobuf,$(SRC_FILES_s))

SRC_DIR_v = Corpus/v8
OBJ_DIR_v = corp2
SRC_FILES_v := $(wildcard $(SRC_DIR_v)/*.js)
OBJ_FILES_v := $(patsubst $(SRC_DIR_v)/%.js,$(OBJ_DIR_v)/%.fuzzil.2.protobuf,$(SRC_FILES_v))


all: $(OBJ_FILES) $(OBJ_FILES_j) $(OBJ_FILES_s) $(OBJ_FILES_v)

$(OBJ_DIR)/%.fuzzil.2.protobuf: Corpus/die/%.js
	$(COMP) -v8-natives $< $@

$(OBJ_DIR_j)/%.fuzzil.2.protobuf: Corpus/javascriptcore/%.js
	$(COMP) -v8-natives $< $@

$(OBJ_DIR_s)/%.fuzzil.2.protobuf: Corpus/spidermonkey/%.js
	$(COMP) -v8-natives $< $@

$(OBJ_DIR_v)/%.fuzzil.2.protobuf: Corpus/v8/%.js
	$(COMP) -v8-natives $< $@

clean:
	-rm $(OBJ_DIR)/*