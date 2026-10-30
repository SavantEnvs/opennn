#!/usr/bin/env bash
#
# mayhem/build.sh — build the opennn fuzz harnesses (JSON, CSV dataset, model and dataset JSON) and the functional tests.
#
# OpenNN's own CMake fetches Eigen, zlib, libjpeg-turbo and googletest at configure time, which cannot run
# air-gapped. The Dockerfile vendors the same pinned versions, prebuilt, under /opt/toolchains/lib/<lib>
# ({include,lib}; Eigen is headers only), so the library sources are compiled directly with the flags CMake
# uses (C++20, EIGEN_MPL2_ONLY, pch.h force-included): the full source set of a CPU build with vision on and
# no CUDA. The upstream functional tests cover opennn/core only and are built from those four sources.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${LIB_DIR:=/opt/toolchains/lib}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS LIB_DIR

cd "$SRC"

for f in eigen/Eigen/Core zlib/lib/libz.a libjpeg-turbo/lib/libjpeg.a googletest/lib/libgtest.a; do
    [ -f "$LIB_DIR/$f" ] || { echo "vendored dependency missing: $LIB_DIR/$f" >&2; exit 1; }
done

CORE_SOURCES="json io_utilities string_utilities log"
INCLUDES="-I$SRC -I$LIB_DIR/eigen -I$LIB_DIR/zlib/include -I$LIB_DIR/libjpeg-turbo/include"
DEPS_LIBS="$LIB_DIR/libjpeg-turbo/lib/libjpeg.a $LIB_DIR/zlib/lib/libz.a"
DEFS="-DEIGEN_MPL2_ONLY"
# CMake precompiles opennn/core/pch.h into every library source; force-include it the same way.
STD="-std=c++20 -fopenmp -include opennn/core/pch.h"

# 1) The whole OpenNN library (the source set CMake builds for a CPU build, vision on),
#    sanitized, DWARF 3. One object set carries libFuzzer coverage instrumentation (fuzzer-no-link): the fuzz
#    binaries link it with the libFuzzer engine, the run-once standalone reproducers link the very same
#    objects with the standalone driver (the ASan runtime supplies the coverage callbacks).
#    build-fuzz*/ are covered by .gitignore's /build-*/.
FUZZ_DIR="$SRC/build-fuzz"
rm -rf "$FUZZ_DIR" && mkdir -p "$FUZZ_DIR"
find opennn -name '*.cpp' -not -path '*/cuda/*' | sort > "$FUZZ_DIR/sources.txt"
# A build with no sanitizers (--build-arg SANITIZER_FLAGS=) has no runtime to supply the coverage callbacks.
COV_FLAGS="-fsanitize=fuzzer-no-link"; [ -n "$SANITIZER_FLAGS" ] || COV_FLAGS=""
export SANITIZER_FLAGS DEBUG_FLAGS CXX STD DEFS INCLUDES FUZZ_DIR COV_FLAGS
xargs -P "$MAYHEM_JOBS" -I{} bash -c \
    '$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS -O1 $STD $DEFS $INCLUDES \
        -c "$1" -o "$FUZZ_DIR/$(echo "$1" | tr / _).o"' _ {} < "$FUZZ_DIR/sources.txt"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$FUZZ_DIR/lsan_off.o"
$CC  $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_DIR/standalone_main.o"
# An archive links only the members a harness actually reaches.
rm -f "$FUZZ_DIR/libopennn.a"
ar rcs "$FUZZ_DIR/libopennn.a" "$FUZZ_DIR"/opennn_*.o

# 2) Harnesses: a libFuzzer binary and a standalone reproducer each.
for t in json_fuzz csv_dataset_fuzz network_json_fuzz dataset_json_fuzz; do
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS -O1 $STD $DEFS $INCLUDES \
        -c "mayhem/$t.cpp" -o "$FUZZ_DIR/$t.o"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fopenmp $LIB_FUZZING_ENGINE \
        "$FUZZ_DIR/$t.o" "$FUZZ_DIR/lsan_off.o" "$FUZZ_DIR/libopennn.a" $DEPS_LIBS -o "/mayhem/$t"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fopenmp \
        "$FUZZ_DIR/$t.o" "$FUZZ_DIR/standalone_main.o" "$FUZZ_DIR/lsan_off.o" "$FUZZ_DIR/libopennn.a" $DEPS_LIBS \
        -o "/mayhem/$t-standalone"
done

# 3) Functional tests (upstream's own gtest files) with NORMAL flags, a separate build.
TEST_DIR="$SRC/build-tests"
rm -rf "$TEST_DIR" && mkdir -p "$TEST_DIR"
$CXX -O1 $STD $DEFS $INCLUDES $COVERAGE_FLAGS \
    tests/core/json_test.cpp tests/core/string_utilities_test.cpp \
    $(for s in $CORE_SOURCES; do echo "opennn/core/$s.cpp"; done) \
    -I$LIB_DIR/googletest/include $LIB_DIR/googletest/lib/libgtest.a $LIB_DIR/googletest/lib/libgtest_main.a -pthread $COVERAGE_FLAGS \
    -o "$TEST_DIR/opennn_core_tests"
