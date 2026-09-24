#!/bin/sh
# =====================================================================
# 可复现构建脚本:精简版 FFmpeg(仅 MP3 320k -> 32k 转码,musl 静态链接)
# 产物:全静态 ffmpeg 二进制,可直接在 Alpine(含 ARM)上运行
#
# 用法:
#   sh build.sh                    # 默认构建本机架构(x86_64)
#   ARCH=x86_64 sh build.sh        # x86_64(需 musl-tools)
#   ARCH=aarch64 sh build.sh       # 交叉编译 aarch64(自动搭建 musl 交叉工具链)
# =====================================================================
set -e

ARCH="${ARCH:-x86_64}"
SRC_DIR="$(pwd)/src"
STAGE="$(pwd)/stage"
FFMPEG_VER=7.1.1
LAME_VER=3.100
MUSL_VER=1.2.5

mkdir -p "$SRC_DIR" "$STAGE"

# ---------------- 公共依赖 ----------------
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config xz-utils wget

if [ "$ARCH" = "x86_64" ]; then
    # ---------------- x86_64:musl-tools 一条龙 ----------------
    DEBIAN_FRONTEND=noninteractive apt-get install -y nasm musl-tools
    CC="musl-gcc"
    LAME_HOST=""
    FF_ARCH_FLAGS=""
else
    # ---------------- aarch64:交叉 gcc + 自建 musl 交叉工具链 ----------------
    DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-aarch64-linux-gnu
    [ -x "$STAGE/musl-aarch64/bin/musl-gcc" ] || {
        [ -d "$SRC_DIR/musl-$MUSL_VER" ] || {
            wget -q "https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz" -O "$SRC_DIR/musl.tgz"
            tar xf "$SRC_DIR/musl.tgz" -C "$SRC_DIR"
        }
        (cd "$SRC_DIR/musl-$MUSL_VER" \
            && ./configure ARCH=aarch64 --target=aarch64-linux-musl \
                 --prefix="$STAGE/musl-aarch64" CROSS_COMPILE=aarch64-linux-gnu- \
            && make -j"$(nproc)" && make install)
    }
    export PATH="$STAGE/musl-aarch64/bin:$PATH"
    export REALGCC=aarch64-linux-gnu-gcc
    CC="musl-gcc"
    LAME_HOST="--host=aarch64-linux-gnu"
    FF_ARCH_FLAGS="--enable-cross-compile --target-os=linux --arch=aarch64"
fi

# ---------------- 下载源码 ----------------
cd "$SRC_DIR"
[ -f "ffmpeg-$FFMPEG_VER.tar.xz" ] || wget "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz"
[ -f "lame-$LAME_VER.tar.gz" ]      || wget "https://ftp.osuosl.org/pub/blfs/conglomeration/lame/lame-$LAME_VER.tar.gz"
[ -d "ffmpeg-$FFMPEG_VER" ] || tar xf "ffmpeg-$FFMPEG_VER.tar.xz"
[ -d "lame-$LAME_VER" ]      || tar xf "lame-$LAME_VER.tar.gz"

# ---------------- 1) LAME 静态库(musl,-O3) ----------------
cd "$SRC_DIR/lame-$LAME_VER"
make clean >/dev/null 2>&1 || true
./configure --prefix="$STAGE" $LAME_HOST \
    --enable-static --disable-shared \
    --disable-frontend \
    --disable-dependency-tracking \
    CC="$CC" CFLAGS="-O3"
make -j"$(nproc)"
make install

# ---------------- 2) FFmpeg 最小配置(musl 静态,-O3) ----------------
cd "$SRC_DIR/ffmpeg-$FFMPEG_VER"
make clean >/dev/null 2>&1 || true
./configure \
    --cc="$CC" $FF_ARCH_FLAGS \
    --prefix="$STAGE/ffmpeg" \
    --enable-static --disable-shared \
    --disable-everything --disable-autodetect \
    --disable-network --disable-doc --disable-debug \
    --disable-avdevice --disable-swscale --disable-postproc \
    --disable-ffprobe --disable-ffplay \
    --enable-libmp3lame \
    --enable-encoder=libmp3lame \
    --enable-decoder=mp3 --enable-decoder=mp3float \
    --enable-demuxer=mp3 --enable-muxer=mp3 \
    --enable-parser=mpegaudio \
    --enable-protocol=file \
    --enable-filter=aresample --enable-filter=aformat --enable-filter=anull \
    --extra-cflags="-I$STAGE/include" \
    --extra-ldflags="-L$STAGE/lib -static"
make -j"$(nproc)"

# aarch64 交叉编译时 make 内置 strip 用的是主机 strip,需手动交叉 strip
if [ "$ARCH" = "aarch64" ]; then
    cp -f ffmpeg_g ffmpeg
    aarch64-linux-gnu-strip ffmpeg
fi

OUT_NAME="ffmpeg"
[ "$ARCH" = "aarch64" ] && OUT_NAME="ffmpeg-aarch64"
cp -f ffmpeg "$OUT_NAME"

echo "======================================================"
echo "构建完成: $(pwd)/$OUT_NAME ($ARCH, 全静态)"
echo "file $OUT_NAME   # 应显示 statically linked"
echo "======================================================"
