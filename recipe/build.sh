#!/bin/bash

set -ex

# Use the conda objdump when generating the linker version script.
sed -i.bak 's/objdump/${OBJDUMP}/g' igc/IGC/Scripts/igc_create_linker_script.sh

# ---------------------------------------------------------------------------
# Build SPIRV-LLVM-Translator.
#
# IGC v2.34.4 uses a newer translator API (TranslatorOpts::
# setEmitFunctionPtrAddrSpace) than conda-forge's libllvmspirv 16.0.5 provides,
# so we vendor the exact revision IGC pins (branch llvm_release_160) and build
# it against the prebuilt LLVM 16, installing it into the prefix.  Both
# opencl-clang and IGC then link this freshly built static LLVMSPIRVLib.
# SPIRV-Headers come from the conda spirv-headers package via
# LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR (the translator pins the same revision).
# ---------------------------------------------------------------------------
(
  export CXXFLAGS="$CXXFLAGS -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS"

  cmake ${CMAKE_ARGS} \
      -G Ninja \
      -DCMAKE_VERBOSE_MAKEFILE=TRUE \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DLLVM_DIR=$PREFIX/lib/cmake/llvm \
      -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=$PREFIX \
      -DLLVM_SPIRV_INCLUDE_TESTS=OFF \
      -S ./spirv-llvm-translator \
      -B ./build-spirv-llvm-translator
  cmake --build ./build-spirv-llvm-translator
  cmake --build ./build-spirv-llvm-translator --target install
)

# ---------------------------------------------------------------------------
# Build opencl-clang (a.k.a. common_clang).
#
# conda-forge does not ship intel-opencl-clang for LLVM 16, so we vendor the
# exact source revision IGC v2.34.4 expects (branch ocl-open-160) and build it
# against the prebuilt LLVM 16 and the SPIRV-LLVM-Translator built just above.
# IGC then links it through its "from system" discovery path.
# ---------------------------------------------------------------------------
(
  export CXXFLAGS="$CXXFLAGS -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS"
  export LDFLAGS="$LDFLAGS -Wl,--exclude-libs,ALL"

  cmake ${CMAKE_ARGS} \
      -G Ninja \
      -DCMAKE_VERBOSE_MAKEFILE=TRUE \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DCMAKE_PREFIX_PATH=$PREFIX \
      -DLLVM_DIR=$PREFIX/lib/cmake/llvm \
      -DPREFERRED_LLVM_VERSION=${LLVM_VERSION}.0 \
      -DLLVMSPIRV_INCLUDED_IN_LLVM=NO \
      -DSPIRV_TRANSLATOR_DIR=$PREFIX \
      -DOPENCL_CLANG_LIBRARY_NAME=opencl_clang \
      -DAPPLY_PATCHES=OFF \
      -S ./opencl-clang \
      -B ./build-opencl-clang
  cmake --build ./build-opencl-clang
  cmake --build ./build-opencl-clang --target install
)

# ---------------------------------------------------------------------------
# Build IGC.
# ---------------------------------------------------------------------------
# IGC encodes the package version as MAJOR.MINOR.PATCH (e.g. 2.34.4).
IFS='.' read -r IGC_MAJOR IGC_MINOR IGC_PATCH <<< "${PKG_VERSION}"

cmake ${CMAKE_ARGS} \
    -G Ninja \
    -DCMAKE_VERBOSE_MAKEFILE=TRUE \
    -DCMAKE_BUILD_TYPE=Release \
    -DIGC_API_MAJOR_VERSION=${IGC_MAJOR} \
    -DIGC_API_MINOR_VERSION=${IGC_MINOR} \
    -DIGC_API_PATCH_VERSION=${IGC_PATCH} \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DLLVM_DIR=$PREFIX/lib/cmake/llvm \
    -DCOMMON_CLANG_LIBRARY_NAME=opencl_clang \
    -DINTRSRC=$SRC_DIR/vc-intrinsics/GenXIntrinsics \
    -DIGC_OPTION__LLVM_MODE=Prebuilds \
    -DIGC_OPTION__LLVM_PREFERRED_VERSION=${LLVM_VERSION}.0 \
    -DIGC_OPTION__SPIRV_TRANSLATOR_MODE=Prebuilds \
    -DIGC_OPTION__SPIRV_TOOLS_MODE=Prebuilds \
    -DIGC_OPTION__USE_PREINSTALLED_SPIRV_HEADERS=ON \
    -S ./igc \
    -B ./build

cmake --build ./build
cmake --build ./build --target install

# TODO: currently debug symbols are included in Release build by design.
#   Should we create a split package with debug symbols, like ddeb?
#   https://github.com/intel/intel-graphics-compiler/issues/341
find $PREFIX/lib -name "*${SHLIB_EXT}.${PKG_VERSION}*" -type f -print0 | xargs -0 -r $STRIP
find $PREFIX/lib -name "libopencl_clang${SHLIB_EXT}*" -type f -print0 | xargs -0 -r $STRIP
for exe in iga64 GenX_IR; do
  if [ -f "$PREFIX/bin/$exe" ]; then
    $STRIP "$PREFIX/bin/$exe"
  fi
done
