#!/bin/bash

# https://github.com/jprendes/emception/blob/f6aa9eb24f69f46b7f3dcd58adad6cdf7e412d16/build-llvm.sh
# MIT Licence, File has been modified.

SRC=$(dirname $0)

BUILD="$1"
LLVM_SRC="$2"

if [ "$LLVM_SRC" == "" ]; then
    LLVM_SRC=$(pwd)/upstream/llvm-project
fi

if [ "$BUILD" == "" ]; then
    BUILD=$(pwd)/build
fi

SRC=$(realpath "$SRC")
BUILD=$(realpath "$BUILD")
LLVM_BUILD=$BUILD/llvm
LLVM_NATIVE=$BUILD/llvm-native

# Prepare WASI sysroot
wget -O- https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-22/wasi-sysroot-22.0.tar.gz | tar -xz

# If we don't have a copy of LLVM, make one
if [ ! -d $LLVM_SRC/ ]; then
    git clone --depth 1 --branch llvmorg-18.1.2 https://github.com/llvm/llvm-project.git "$LLVM_SRC/"
fi

# Cross compiling llvm needs a native build of "llvm-tblgen" and "clang-tblgen"
if [ ! -d $LLVM_NATIVE/ ]; then
    cmake -G Ninja \
        -S $LLVM_SRC/llvm/ \
        -B $LLVM_NATIVE/ \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD=ARM \
        -DLLVM_ENABLE_PROJECTS="clang"
fi
cmake --build $LLVM_NATIVE/ -- llvm-tblgen clang-tblgen

## Apply a patch for blocking stdin read
git apply $SRC/wait_stdin.patch

## Build clangd (1st time, just for compiler headers)
emcmake cmake -G Ninja \
    -S $LLVM_SRC/llvm/ \
    -B $LLVM_BUILD/ \
    -DCMAKE_CXX_FLAGS="-pthread -Dwait4=__syscall_wait4" \
    -DCMAKE_EXE_LINKER_FLAGS="-pthread -s ENVIRONMENT=worker -s NO_INVOKE_RUN" \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DLLVM_TARGET_ARCH=wasm32-emscripten \
    -DLLVM_DEFAULT_TARGET_TRIPLE=wasm32-wasi \
    -DLLVM_TARGETS_TO_BUILD=WebAssembly \
    -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra" \
    -DLLVM_TABLEGEN=$LLVM_NATIVE/bin/llvm-tblgen \
    -DCLANG_TABLEGEN=$LLVM_NATIVE/bin/clang-tblgen \
    -DLLVM_BUILD_STATIC=ON \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_BACKTRACES=OFF \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_PIC=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DCLANG_ENABLE_ARCMT=OFF
cmake --build $LLVM_BUILD/ --target clangd

## Copy installed headers to WASI sysroot
cp -r $LLVM_BUILD/lib/clang/18/include/* $SRC/wasi-sysroot/include/

## Build clangd (2nd time, for the real thing)
emcmake cmake -G Ninja \
    -S $LLVM_SRC/llvm/ \
    -B $LLVM_BUILD/ \
    -DCMAKE_CXX_FLAGS="-pthread -Dwait4=__syscall_wait4" \
    -DCMAKE_EXE_LINKER_FLAGS="-pthread -s ENVIRONMENT=worker -s NO_INVOKE_RUN -s EXIT_RUNTIME -s INITIAL_MEMORY=2GB -s ALLOW_MEMORY_GROWTH -s MAXIMUM_MEMORY=4GB -s STACK_SIZE=256kB -s EXPORTED_RUNTIME_METHODS=FS,callMain -s MODULARIZE -s EXPORT_ES6 -s WASM_BIGINT -s ASSERTIONS -s ASYNCIFY -s PTHREAD_POOL_SIZE='Math.max(navigator.hardwareConcurrency, 8)' --embed-file=$SRC/wasi-sysroot/include@/usr/include" \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DLLVM_TARGET_ARCH=wasm32-emscripten \
    -DLLVM_DEFAULT_TARGET_TRIPLE=wasm32-wasi \
    -DLLVM_TARGETS_TO_BUILD=WebAssembly \
    -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra" \
    -DLLVM_TABLEGEN=$LLVM_NATIVE/bin/llvm-tblgen \
    -DCLANG_TABLEGEN=$LLVM_NATIVE/bin/clang-tblgen \
    -DLLVM_BUILD_STATIC=ON \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_BACKTRACES=OFF \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_PIC=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DCLANG_ENABLE_ARCMT=OFF
cmake --build $LLVM_BUILD/ --target clangd
