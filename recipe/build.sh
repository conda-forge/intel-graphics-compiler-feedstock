#!/bin/bash

set -ex

sed -i.bak 's/objdump/${OBJDUMP}/g' igc/IGC/Scripts/igc_create_linker_script.sh

PATCH_VERSION=${PKG_VERSION#1.0.}
if [$PKG_VERSION != "1.0.$PATCH_VERSION"]; then exit 1; fi

cmake ${CMAKE_ARGS} \
    -G Ninja \
    -DCMAKE_VERBOSE_MAKEFILE=TRUE \
    -DCMAKE_BUILD_TYPE=Release \
    -DIGC_PACKAGE_RELEASE=$PATCH_VERSION \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DLLVM_DIR=$PREFIX/lib/cmake/llvm \
    -DCOMMON_CLANG_LIBRARY_NAME=opencl_clang \
    -DINTRSRC=$SRC_DIR/vc-intrinsics/GenXIntrinsics \
    -DIGC_OPTION__LLVM_MODE=Prebuilds \
    -DIGC_OPTION__LLVM_PREFERRED_VERSION=${LLVM_VERSION}.0\
    -DIGC_OPTION__SPIRV_TOOLS_MODE=Prebuilds \
    -DIGC_OPTION__USE_PREINSTALLED_SPIRV_HEADERS=ON \
    -S ./igc \
    -B ./build

cmake --build ./build
cmake --build ./build --target install

# TODO: currently debug symbols are included in Release build by design.
#   Should we create a split package with debug symbols, like ddeb?
#   https://github.com/intel/intel-graphics-compiler/issues/341
find $PREFIX/lib | grep $SHLIB_EXT.$PKG_VERSION | xargs $STRIP
$STRIP $PREFIX/bin/iga64
$STRIP $PREFIX/bin/GenX_IR
