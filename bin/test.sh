#!/bin/sh
if [ -d ../src ]; then cd ../; fi
if [ -d bin ]; then cd bin; fi
odin test ../src/ -out:infinity-mod.exe -debug -define:ODIN_TEST_THREADS=4 -define:ODIN_TEST_RANDOM_SEED=1 -define:ODIN_TEST_LOG_LEVEL=warning -define:ODIN_TEST_SHORT_LOGS=true
