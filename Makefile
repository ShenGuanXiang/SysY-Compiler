SRC_PATH ?= src
INC_PATH += include
BUILD_PATH ?= build
TEST_PATH ?= test
DEBUG_PATH ?= MakeDebug
OPTTEST_PATH ?= opttest
OBJ_PATH ?= $(BUILD_PATH)/obj
BINARY ?= $(BUILD_PATH)/compiler
SYSLIB_PATH ?= sysyruntimelibrary

INC = $(addprefix -I, $(INC_PATH))
SRC = $(shell find $(SRC_PATH)  -name "*.cpp")
CFLAGS = -O0 -g -Wall -std=c++11 $(INC)
FLEX ?= $(SRC_PATH)/lexer.l
LEXER ?= $(addsuffix .cpp, $(basename $(FLEX)))
BISON ?= $(SRC_PATH)/parser.y
PARSER ?= $(addsuffix .cpp, $(basename $(BISON)))
SRC += $(LEXER)
SRC += $(PARSER)
OBJ = $(SRC:$(SRC_PATH)/%.cpp=$(OBJ_PATH)/%.o)
PARSERH ?= $(INC_PATH)/$(addsuffix .h, $(notdir $(basename $(PARSER))))

TESTCASE = $(shell find $(DEBUG_PATH) -name "*.sy")
# TESTCASE = $(shell find $(TEST_PATH) -name "*.sy")
OPTTESTCASE = $(shell find $(OPTTEST_PATH) -name "*.sy")
TESTCASE_NUM = $(words $(TESTCASE))
LLVM_IR = $(addsuffix _std.ll, $(basename $(TESTCASE)))
GCC_ASM = $(addsuffix _std.s, $(basename $(TESTCASE)))
OUTPUT_TOKS = $(addsuffix .toks, $(basename $(TESTCASE)))
OUTPUT_AST = $(addsuffix .ast, $(basename $(TESTCASE)))
OUTPUT_IR = $(addsuffix .ll, $(basename $(TESTCASE)))
OUTPUT_ASM = $(addsuffix .s, $(basename $(TESTCASE)))
OUTPUT_RES = $(addsuffix .res, $(basename $(TESTCASE)))
OUTPUT_BIN = $(addsuffix .bin, $(basename $(TESTCASE)))
OUTPUT_LOG = $(addsuffix .log, $(basename $(TESTCASE)))
OUTPUT_OPT_IR = $(addsuffix .ll, $(basename $(OPTTESTCASE)))
OUTPUT_OPT_ASM = $(addsuffix .s, $(basename $(OPTTESTCASE)))
OUTPUT_OPT_LOG = $(addsuffix .log, $(basename $(OPTTESTCASE)))

.phony:all app run gdb testlexer testparser testir testasm test clean clean-all clean-test clean-app llvmir gccasm testopt lltest
all:app

$(LEXER):$(FLEX)
	@flex -o $@ $<

$(PARSER):$(BISON)
	@bison -o $@ $< --warnings=error=all --defines=$(PARSERH)

$(OBJ_PATH)/%.o:$(SRC_PATH)/%.cpp
	@mkdir -p $(OBJ_PATH)
	@g++ $(CFLAGS) -c -o $@ $<

$(BINARY):$(OBJ)
	@g++ -O0 -g -o $@ $^

app:$(LEXER) $(PARSER) $(BINARY)

run:app
	@$(BINARY) -o debug.s -S debug.sy -O2

gdb:app
	@gdb $(BINARY)

$(OBJ_PATH)/lexer.o:$(SRC_PATH)/lexer.cpp
	@mkdir -p $(OBJ_PATH)
	@g++ $(CFLAGS) -c -o $@ $<

$(TEST_PATH)/%.toks:$(TEST_PATH)/%.sy
	@$(BINARY) $< -o $@ -t

$(TEST_PATH)/%.ast:$(TEST_PATH)/%.sy
	@$(BINARY) $< -o $@ -a

$(TEST_PATH)/%.ll:$(TEST_PATH)/%.sy
	@$(BINARY) $< -o $@ -i	

$(TEST_PATH)/%_std.ll:$(TEST_PATH)/%.sy
	@clang -x c $< -S -m32 -emit-llvm -o $@ 

$(TEST_PATH)/%_std.s:$(TEST_PATH)/%.sy
	@arm-linux-gnueabihf-gcc -x c $< -S -o $@ 

$(TEST_PATH)/%.s:$(TEST_PATH)/%.sy
	@timeout 5s $(BINARY) $< -o $@ -S 2>$(addsuffix .log, $(basename $@))
	@[ $$? != 0 ] && echo "\033[1;31mCOMPILE FAIL:\033[0m $(notdir $<)" || echo "\033[1;32mCOMPILE SUCCESS:\033[0m $(notdir $<)"

llvmir:$(LLVM_IR)

gccasm:$(GCC_ASM)

testlexer:app $(OUTPUT_TOKS)

testparser:app $(OUTPUT_AST)

testir:app $(OUTPUT_IR)

testasm:app $(OUTPUT_ASM)

.ONESHELL:
test:app
	@sudo cp -arf ./newpass.log ./lastpass.log
	@rm newpass.log
	@touch newpass.log
	@success=0
	@for file in $(sort $(TESTCASE))
	do
		ASM=$${file%.*}.s
		LOG=$${file%.*}.log
		BIN=$${file%.*}.bin
		RES=$${file%.*}.res
		IN=$${file%.*}.in
		OUT=$${file%.*}.out
		FILE=$${file##*/}
		FILE=$${FILE%.*}
		timeout 20s $(BINARY) $${file} -o $${ASM} -S 2>$${LOG} -O2
		# timeout 5s $(BINARY) $${file} -o $${IR} -i 2>$${LOG} -O2
		RETURN_VALUE=$$?
		if [ $$RETURN_VALUE = 124 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Timeout\033[0m" && echo "FAIL: $${FILE}\tCompile Timeout" >> newpass.log
			continue
		else if [ $$RETURN_VALUE != 0 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Error\033[0m" && echo "FAIL: $${FILE}\tCompile Error" >> newpass.log
			continue
			fi
		fi
		arm-linux-gnueabihf-gcc -mcpu=cortex-a72 -o $${BIN} $${ASM} $(SYSLIB_PATH)/libsysy.a >>$${LOG} 2>&1
		if [ $$? != 0 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m" && echo "FAIL: $${FILE}\tAssemble Error" >> newpass.log
		else
			if [ -f "$${IN}" ]; then
				timeout 2s qemu-arm -L /usr/arm-linux-gnueabihf $${BIN} <$${IN} >$${RES} 2>>$${LOG}
			else
				timeout 2s qemu-arm -L /usr/arm-linux-gnueabihf $${BIN} >$${RES} 2>>$${LOG}
			fi
		# clang -o $${BIN} $${IR} $(SYSLIB_PATH)/sylib.c >>$${LOG} 2>&1
		# if [ $$? != 0 ]; then
		# 	echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m" && echo "FAIL: $${FILE}\tAssemble Error" >> newpass.log
		# else
		# 	if [ -f "$${IN}" ]; then
		# 		timeout 2s $${BIN} <$${IN} >$${RES} 2>>$${LOG}
		# 	else
		# 		timeout 2s $${BIN} >$${RES} 2>>$${LOG}
		# 	fi
			RETURN_VALUE=$$?
			FINAL=`tail -c 1 $${RES}`
			[ $${FINAL} ] && echo "\n$${RETURN_VALUE}" >> $${RES} || echo "$${RETURN_VALUE}" >> $${RES}
			if [ "$${RETURN_VALUE}" = "124" ]; then
				echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Timeout\033[0m" && echo "FAIL: $${FILE}\tExecute Timeout" >> newpass.log
			else if [ "$${RETURN_VALUE}" = "127" ]; then
				echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Error\033[0m" && echo "FAIL: $${FILE}\tExecute Error" >> newpass.log
				else
					diff -Z $${RES} $${OUT} >/dev/null 2>&1
					if [ $$? != 0 ]; then
						echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mWrong Answer\033[0m" && echo "FAIL: $${FILE}\tWrong Answer" >> newpass.log
					else
						success=$$((success + 1))
						echo "\033[1;32mPASS:\033[0m $${FILE}" && echo "PASS: $${FILE}" >> newpass.log
					fi
				fi
			fi
		fi
	done
	echo "\033[1;33mTotal: $(TESTCASE_NUM)\t\033[1;32mAccept: $${success}\t\033[1;31mFail: $$(($(TESTCASE_NUM) - $${success}))\033[0m" && echo "Total: $(TESTCASE_NUM)\tAccept: $${success}\tFail: $$(($(TESTCASE_NUM) - $${success}))" >> newpass.log
	[ $(TESTCASE_NUM) = $${success} ] && echo "\033[5;32mAll Accepted. Congratulations!\033[0m" && echo "All Accepted. Congratulations!" >> newpass.log
	:
	diff lastpass.log newpass.log > passchange.log

testopt:app
	@for file in $(sort $(OPTTESTCASE))
	do
		$(BINARY) -o $${file%.*}.unopt.ll -i $${file}  2>$${file%.*}.log
		$(BINARY) -o $${file%.*}.unopt.s -S $${file}  2>$${file%.*}.log
		$(BINARY) -o $${file%.*}.opt.ll -i $${file} -O2 2>$${file%.*}.log
		$(BINARY) -o $${file%.*}.opt.s -S $${file} -O2 2>$${file%.*}.log
	done

clean-app:
	@rm -rf $(BUILD_PATH) $(PARSER) $(LEXER) $(PARSERH)

clean-test:
	@rm -rf $(OUTPUT_TOKS) $(OUTPUT_AST) $(OUTPUT_IR) $(OUTPUT_ASM) $(OUTPUT_LOG) $(OUTPUT_BIN) $(OUTPUT_RES) $(LLVM_IR) $(GCC_ASM) ./example.ast ./example.ll ./example.s ./debug.bin ./debug.log ./debug.res

clean-opt:
	@rm -rf $(OUTPUT_OPT_IR) $(OUTPUT_OPT_ASM) $(OUTPUT_OPT_LOG)

clean-all:clean-test clean-app clean-opt

clean:clean-all

.ONESHELL:
lltest:app
	@success=0
	@for file in $(sort $(TESTCASE))
	do
		IR=$${file%.*}.ll
		LOG=$${file%.*}.log
		BIN=$${file%.*}.bin
		RES=$${file%.*}.res
		IN=$${file%.*}.in
		OUT=$${file%.*}.out
		FILE=$${file##*/}
		FILE=$${FILE%.*}
		timeout 300s $(BINARY) $${file} -o $${IR} -O2 -i 2>$${LOG}
		RETURN_VALUE=$$?
		if [ $$RETURN_VALUE = 124 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Timeout\033[0m"
			continue
		else if [ $$RETURN_VALUE != 0 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Error\033[0m"
			continue
			fi
		fi
		clang -o $${BIN} $${IR} $(SYSLIB_PATH)/sylib.c >>$${LOG} 2>&1
		if [ $$? != 0 ]; then
			echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m"
		else
			if [ -f "$${IN}" ]; then
				timeout 50s $${BIN} <$${IN} >$${RES} 2>>$${LOG}
			else
				timeout 50s $${BIN} >$${RES} 2>>$${LOG}
			fi
			RETURN_VALUE=$$?
			FINAL=`tail -c 1 $${RES}`
			[ $${FINAL} ] && echo "\n$${RETURN_VALUE}" >> $${RES} || echo "$${RETURN_VALUE}" >> $${RES}
			if [ "$${RETURN_VALUE}" = "124" ]; then
				echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Timeout\033[0m"
			else if [ "$${RETURN_VALUE}" = "127" ]; then
				echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Error\033[0m"
				else
					diff -Z $${RES} $${OUT} >/dev/null 2>&1
					if [ $$? != 0 ]; then
						echo "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mWrong Answer\033[0m"
					else
						success=$$((success + 1))
						echo "\033[1;32mPASS:\033[0m $${FILE}"
					fi
				fi
			fi
		fi
	done
	echo "\033[1;33mTotal: $(TESTCASE_NUM)\t\033[1;32mAccept: $${success}\t\033[1;31mFail: $$(($(TESTCASE_NUM) - $${success}))\033[0m"
	[ $(TESTCASE_NUM) = $${success} ] && echo "\033[5;32mAll Accepted. Congratulations!\033[0m"
	: