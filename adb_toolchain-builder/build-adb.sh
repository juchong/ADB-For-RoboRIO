#!/usr/bin/env bash
#########################################################################################
# build-adb.sh – cross-compiles Android Debug Bridge using the 2022 RoboRIO toolchain
#                using the standalone CMake repo https://github.com/prife/adb
#########################################################################################
set -euo pipefail

# 0. Locate roboRIO 2022 toolchain
TOPDIR=$(pwd)
TC_PREFIX=arm-frc2022-linux-gnueabi

SYSROOT_DIR="$TOPDIR/frc2022/roborio/$TC_PREFIX"
BIN_DIR="$TOPDIR/frc2022/roborio/bin"

[[ -d "$SYSROOT_DIR" ]] || { echo "Error: sysroot missing: $SYSROOT_DIR"; exit 1; }
[[ -d "$BIN_DIR"    ]] || { echo "Error: bin missing:    $BIN_DIR";    exit 1; }

for t in gcc g++ ar ld strip ranlib; do
  [[ -x "$BIN_DIR/${TC_PREFIX}-$t" ]] || {
    echo "Error: $BIN_DIR/${TC_PREFIX}-$t not found"; exit 1; }
done

export PATH="$BIN_DIR:$PATH"

# 1. User-configurable settings
ADB_REF="" # Empty = default
SRC_DIR="$TOPDIR/src"
BUILD_DIR="$TOPDIR/build"
INSTALL_DIR="$TOPDIR/out"
BORINGSSL_DIR="$SRC_DIR/lib/boringssl"
BORINGSSL_GIT=https://salsa.debian.org/android-tools-team/android-platform-external-boringssl.git
BORINGSSL_TAG=debian/8.1.0+r23-3

# 2. Clone or update prife/adb
if [[ ! -d "$SRC_DIR" ]]; then
  echo "==> Cloning prife/adb…"
  git clone --depth=1 ${ADB_REF:+-b "$ADB_REF"} \
    https://github.com/prife/adb.git "$SRC_DIR"
  git -C "$SRC_DIR" submodule update --init --depth 1
else
  echo "==> Updating prife/adb…"
  git -C "$SRC_DIR" fetch --depth=1 origin ${ADB_REF:-HEAD}
  git -C "$SRC_DIR" reset --hard FETCH_HEAD
  git -C "$SRC_DIR" submodule update --init --depth 1
fi

# 3. Build BoringSSL for arm-frc2022
if [[ ! -e "$BORINGSSL_DIR/debian/out/libcrypto.a" ]]; then
  echo "==> Fetching & building BoringSSL…"
  mkdir -p "$(dirname "$BORINGSSL_DIR")"
  git clone --depth=1 -b "$BORINGSSL_TAG" \
    "$BORINGSSL_GIT" "$BORINGSSL_DIR"
  pushd "$BORINGSSL_DIR" >/dev/null
    rm -rf debian/out
    make -f debian/libcrypto.mk \
         CC=${TC_PREFIX}-gcc   CFLAGS=-fPIC \
         DEB_HOST_ARCH=armhf
    make -f debian/libssl.mk \
         CXX=${TC_PREFIX}-g++ CXXFLAGS=-fPIC \
         DEB_HOST_ARCH=armhf
  popd >/dev/null
fi

BORINGSSL_OUT="$BORINGSSL_DIR/debian/out"
BORINGSSL_INC="$BORINGSSL_DIR/src/include"

# 4. Install BoringSSL into prife/adb's prebuilt tree
PREBUILT_ARM32="$SRC_DIR/prebuilt/linux/arm-frc2022"
rm -rf "$PREBUILT_ARM32"
mkdir -p "$PREBUILT_ARM32"
cp "$BORINGSSL_OUT"/libcrypto.* "$PREBUILT_ARM32/"
cp "$BORINGSSL_OUT"/libssl.*    "$PREBUILT_ARM32/"

# 5. Inject ARM prebuilt ahead of x86-64 in src/CMakeLists.txt
echo "==> Inserting ARM prebuilt into src/CMakeLists.txt…"
ed -s "$SRC_DIR/src/CMakeLists.txt" << 'EOF'
/prebuilt\/linux\/x86-64/ i
if(CMAKE_HOST_SYSTEM_NAME MATCHES "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm.*")
  link_directories("${CMAKE_SOURCE_DIR}/prebuilt/linux/arm-frc2022")
endif()
.
w
q
EOF

# 6. Strip out the static-libstdc++ / static-libgcc++ flags
echo "==> Cleaning up static link flags in CMakeLists.txt…"
sed -i '
  s|-static-libstdc\+\+||g
  s|-static-libgcc\+\+|-static-libgcc|g
' "$SRC_DIR/src/CMakeLists.txt"

# 7. Comment out the static‐link flags so no stray "++" appears
echo "==> Commenting out target_link_options to drop -static-lib*…"
sed -i '/target_link_options.*PRIVATE/s/^/#/' "$SRC_DIR/src/CMakeLists.txt"

# 8. Generate CMake cross-compile toolchain file
mkdir -p "$BUILD_DIR"
TC_FILE="$BUILD_DIR/frc2022.cmake"
cat >"$TC_FILE" <<EOF
set(CMAKE_SYSTEM_NAME       Linux)
set(CMAKE_SYSTEM_PROCESSOR  arm)

set(CMAKE_SYSROOT           $SYSROOT_DIR)
set(CMAKE_FIND_ROOT_PATH    \${CMAKE_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

set(CMAKE_C_COMPILER        ${TC_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER      ${TC_PREFIX}-g++)
set(CMAKE_ASM_COMPILER      ${TC_PREFIX}-gcc)
set(CMAKE_AR                ${TC_PREFIX}-ar)
set(CMAKE_RANLIB            ${TC_PREFIX}-ranlib)
set(CMAKE_STRIP             ${TC_PREFIX}-strip)
set(CMAKE_LINKER            ${TC_PREFIX}-ld)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXE_LINKER_FLAGS  "-s -Wl,-rpath=\$ORIGIN")
EOF

# 9. Configure and build
echo "==> Configuring with CMake…"
pushd "$BUILD_DIR" >/dev/null
cmake -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$TC_FILE" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath=\$ORIGIN" \
      "$SRC_DIR"

echo "==> Building adb…"
cmake --build . --target adb -j"$(nproc)"
popd >/dev/null

echo "==> Staging adb and libcrypto/libssl libraries into out/ directory…"
mkdir -p "$INSTALL_DIR"
cp "$BUILD_DIR/src/adb" "$INSTALL_DIR/adb"
cp "$BORINGSSL_OUT"/libcrypto.so.0 "$INSTALL_DIR/libcrypto.so.0"
cp "$BORINGSSL_OUT"/libssl.so.0 "$INSTALL_DIR/libssl.so.0"

echo "==> Done!  adb binary is here: $INSTALL_DIR/adb"
file "$INSTALL_DIR/adb"
