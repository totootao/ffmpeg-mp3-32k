#!/bin/sh
# =====================================================================
# MP3 批量降码率工具:320k(或其他)-> 32k CBR
# 依赖: 本目录下的精简版 ffmpeg(静态,无需任何系统依赖)
#       多核并行转换(单文件转码无法多线程,并行是批量场景最大提速手段)
#
# 用法:
#   ./mp3-320-to-32.sh 文件.mp3              # 输出到 $OUT(默认 ./32k)
#   ./mp3-320-to-32.sh 目录                  # 递归处理目录内所有 mp3,多核并行
#
# 可选环境变量:
#   OUT=/path      输出目录(默认 ./32k),保持源目录结构
#   BITRATE=32k    目标码率(默认 32k)
#   MONO=1         转单声道(32k 下听感通常明显更好,且更快)
#   LEVEL=0-9      LAME 压缩等级(9 最快,0 质量最好最慢;默认留空用 ffmpeg 默认)
#   JOBS=8         并行进程数(默认 = CPU 核数)
# =====================================================================
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
FF="$DIR/ffmpeg"
# 按主机架构自动选择二进制(x86_64 -> ffmpeg,aarch64 -> ffmpeg-aarch64)
case "$(uname -m)" in
    aarch64*|arm64) [ -x "$DIR/ffmpeg-aarch64" ] && FF="$DIR/ffmpeg-aarch64" ;;
esac
OUT="${OUT:-./32k}"
BITRATE="${BITRATE:-32k}"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

[ -x "$FF" ] || { echo "错误: 未找到 $FF"; exit 1; }
export FF OUT BITRATE MONO LEVEL

convert_stream() {
    src="$1"
    rel="${src#./}"
    dst="$OUT/${rel%.*}.mp3"
    mkdir -p "$(dirname "$dst")"
    extra=""
    [ -n "$MONO" ] && extra="$extra -ac 1"
    [ -n "$LEVEL" ] && extra="$extra -compression_level $LEVEL"
    "$FF" -hide_banner -loglevel error -y -i "$src" -b:a "$BITRATE" $extra "$dst" \
        && echo "OK  $src -> $dst"
}

collect() {
    if [ -f "$1" ]; then
        printf '%s\n' "$1"
    elif [ -d "$1" ]; then
        find "$1" -type f -iname '*.mp3'
    else
        echo "用法: $0 <mp3文件或目录>" >&2; exit 1
    fi
}

# xargs 子进程无法复用本脚本函数,转换逻辑必须内联(依赖已 export 的变量)
collect "$1" | xargs -P "$JOBS" -I{} sh -c '
    src="$1"
    rel="${src#./}"
    dst="$OUT/${rel%.*}.mp3"
    mkdir -p "$(dirname "$dst")"
    extra=""
    [ -n "$MONO" ] && extra="$extra -ac 1"
    [ -n "$LEVEL" ] && extra="$extra -compression_level $LEVEL"
    "$FF" -hide_banner -loglevel error -y -i "$src" -b:a "$BITRATE" $extra "$dst" \
        && echo "OK  $src -> $dst"
' _ {}
