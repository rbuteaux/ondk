#!/usr/bin/env bash

# Copyright 2022-2023 Google LLC.
# SPDX-License-Identifier: Apache-2.0

set -e

. common.sh

OS=$(uname | tr '[:upper:]' '[:lower:]')
NATIVE_ARCH=$(uname -m)
if [ $NATIVE_ARCH = "arm64" ]; then
  # Apple calls aarch64 arm64
  NATIVE_ARCH='aarch64'
fi

if [ -z $1 ]; then
  # Build the native architecture by default
  ARCH=$NATIVE_ARCH
else
  ARCH=$1
fi

if [ $OS = "darwin" ]; then
  NDK_DIRNAME='darwin-x86_64'
  TRIPLE="${ARCH}-apple-darwin"
  NATIVE_TRIPLE="${NATIVE_ARCH}-apple-darwin"
  DYN_EXT='dylib'

  if [ $ARCH = "aarch64" ]; then
    # Apple Silicon uses 16k pages
    export JEMALLOC_SYS_WITH_LG_PAGE=14
  fi

  command -v ninja >/dev/null || brew install ninja
else
  NDK_DIRNAME='linux-x86_64'
  TRIPLE="${ARCH}-unknown-linux-gnu"
  NATIVE_TRIPLE="${NATIVE_ARCH}-unknown-linux-gnu"
  DYN_EXT='so'

  command -v ninja >/dev/null || sudo apt-get install ninja-build
  command -v lld >/dev/null || sudo apt-get install lld
fi

build() {
  cd rust
  python3 ./x.py --config "../config-${OS}.toml" --host $TRIPLE install
  cd ../

  cd out
  find . -name '*.old' -delete
  cp -af ../rust/build/$TRIPLE/llvm/bin llvm-bin
  cp -af $(../rust/build/$NATIVE_TRIPLE/llvm/bin/clang -print-resource-dir)/include clang-include
  cp -af lib/rustlib/$TRIPLE/bin/rust-lld llvm-bin/lld
  ln -sf lld llvm-bin/ld
  find ../rust/build/$TRIPLE/llvm/lib -name "*.${DYN_EXT}*" -exec cp -an {} lib \;
  cd ..
}

ndk() {
  local NDK_ZIP="android-ndk-${NDK_VERSION}-${OS}.zip"

  # Download and extract
  [ -f $NDK_ZIP ] || curl -O -L "https://dl.google.com/android/repository/$NDK_ZIP"
  unzip -q $NDK_ZIP
  mv "android-ndk-${NDK_VERSION}" ndk

  # Copy the whole output folder into ndk
  cp -af out ndk/toolchains/rust

  cd ndk/toolchains

  # Move llvm folder to llvm.dir
  mv llvm/prebuilt/$NDK_DIRNAME llvm.dir
  ln -s ../../llvm.dir llvm/prebuilt/$NDK_DIRNAME

  # Replace headers
  local NDK_RES=$(llvm.dir/bin/clang -print-resource-dir)
  rm -rf $NDK_RES/include
  mv rust/clang-include $NDK_RES/include

  # Replace files with those from the rust toolchain
  cd llvm.dir/bin
  ln -sf ../../rust/llvm-bin/* .
  rm clang-14
  cd ../lib64
  ln -sf ../../rust/lib/*.$DYN_EXT* .
  rm -f libclang.so.13 libclang-cpp.so.14git libLLVM-14git.so libLTO.so.14git libRemarks.so.14git
  cd ../..

  # Now that clang is replaced, move files to the correct location
  mkdir -p $(dirname $(llvm.dir/bin/clang -print-resource-dir))
  mv $NDK_RES $(llvm.dir/bin/clang -print-resource-dir)
  ln -s ../../rust/lib/clang llvm.dir/lib/clang
  cd ../..
}

if [ -z "$DIST_ONLY" ]; then
  clone
  build
fi

if [ -z "$SKIP_DIST" ]; then
  ndk
  dist
fi
