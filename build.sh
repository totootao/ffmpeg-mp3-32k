#!/bin/sh
# =====================================================================
# 可复现构建脚本:精简版 FFmpeg(仅 MP3 320k -> 32k 转码,musl 静态链接)
# 产物:x86_64 Linux 全静态 ffmpeg 二进制,可直接在 Alpine 上运行
#
# 用法: 在 Ubuntu/Debian 上执行  sh build.sh
# =====================================================================
set -e

SRC_DIR="$(pwd)/src"
STAGE="$(pwd)/stage"
FFMPEG_VER=7.1.1
LAME_VER=3.100

# ---- 依赖(Ubuntu/Debian) ----
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential musl-tools nasm pkg-config xz-utils wget

mkdir -p "$SRC_DIR" "$STAGE"

# ---- 下载源码 ----
cd "$SRC_DIR"
[ -f "ffmpeg-$FFMPEG_VER.tar.xz" ] || wget "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz"
[ -f "lame-$LAME_VER.tar.gz" ]      || wget "https://ftp.osuosl.org/pub/blfs/conglomeration/lame/lame-$LAME_VER.tar.gz"
tar xf "ffmpeg-$FFMPEG_VER.tar.xz"
tar xf "lame-$LAME_VER.tar.gz"

# ---- 1) LAME 静态库(musl) ----
cd "$SRC_DIR/lame-$LAME_VER"
./configure --prefix="$STAGE" \
    --enable-static --disable-shared \
    --disable-frontend \
    --disable-dependency-tracking \
    CC=musl-gcc CFLAGS="-Os"
make -j"$(nproc)"
make install

# ---- 2) FFmpeg 最小配置(musl 静态) ----
cd "$SRC_DIR/ffmpeg-$FFMPEG_VER"
./configure \
    --cc=musl-gcc \
    --prefix="$STAGE/ffmpeg" \
    --enable-static --disable-shared \
    --disable-everything --disable-autodetect \
    --disable-network --disable-doc --disable-debug \
    --disable-avdevice --disable-swscale --disable-postproc \
    --disable-ffprobe --disable-ffplay \
    --enable-small \
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

echo "======================================================"
echo "构建完成: $(pwd)/ffmpeg"
echo "file $(pwd)/ffmpeg   # 应显示 statically linked"
echo "======================================================"
