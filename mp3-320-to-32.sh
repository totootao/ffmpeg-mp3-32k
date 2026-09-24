#!/bin/sh
# =====================================================================
# MP3 批量降码率工具:320k(或其他) -> 32k CBR
# 依赖: 本目录下的精简版 ffmpeg(静态,无需任何系统依赖)
#
# 用法:
#   ./mp3-320-to-32.sh 文件.mp3              # 输出到 ./32k/文件.mp3
#   ./mp3-320-to-32.sh 目录                  # 递归处理目录内所有 mp3
#   OUT=/path ./mp3-320-to-32.sh 目录        # 自定义输出目录(默认 ./32k)
#   MONO=1 ./mp3-320-to-32.sh ...            # 32k 下转单声道,听感通常更好
# =====================================================================
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
FF="$DIR/ffmpeg"
OUT="${OUT:-./32k}"
BITRATE="${BITRATE:-32k}"

[ -x "$FF" ] || { echo "错误: 未找到 $FF"; exit 1; }

convert_one() {
    src="$1"
    rel="${src#./}"
    dst="$OUT/${rel%.*}.mp3"
    mkdir -p "$(dirname "$dst")"
    if [ -n "$MONO" ]; then
        "$FF" -hide_banner -loglevel error -y -i "$src" -b:a "$BITRATE" -ac 1 "$dst"
    else
        "$FF" -hide_banner -loglevel error -y -i "$src" -b:a "$BITRATE" "$dst"
    fi
    echo "OK  $src -> $dst"
}

if [ -f "$1" ]; then
    convert_one "$1"
elif [ -d "$1" ]; then
    # POSIX sh 无 globstar,用 find 递归
    find "$1" -type f -iname "*.mp3" | while IFS= read -r f; do
        convert_one "$f"
    done
else
    echo "用法: $0 <mp3文件或目录>"; exit 1
fi
