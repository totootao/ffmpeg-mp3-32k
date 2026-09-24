# 精简版 FFmpeg —— 仅 MP3 降码率(320k → 32k)

一个 **1.9 MB 全静态**的定制 FFmpeg(基于 FFmpeg 7.1.1 + LAME 3.100,`-O3` 编译),
通过 `--disable-everything` 裁剪后**只保留 MP3 转码所需组件**,
用 musl-gcc 静态链接,**零依赖**,可直接在 **Alpine Linux**(及任意 x86_64 Linux)上运行。

## 快速使用

```sh
chmod +x ffmpeg
./ffmpeg -i input.mp3 -b:a 32k output.mp3

# 32k 码率下转单声道,听感通常明显更好(可选):
./ffmpeg -i input.mp3 -b:a 32k -ac 1 output.mp3
```

批量转换(递归目录):

```sh
chmod +x mp3-320-to-32.sh
./mp3-320-to-32.sh /path/to/music          # 多核并行,输出到 ./32k/,保持目录结构
MONO=1 LEVEL=9 ./mp3-320-to-32.sh /path/to/music   # 最快模式(见下)
JOBS=8 OUT=/tmp/out ./mp3-320-to-32.sh ... # 指定并行数与输出目录
```

## 性能与提速

基准:3 分钟 320 kbps 立体声 MP3 → 32 kbps,单文件转码为单线程流水线,速度以"x 实时"计:

| 配置 | 速度 | 相对默认 |
|---|---|---|
| 默认参数(立体声,LAME 默认质量)| ~220x | 1.0x |
| `-compression_level 9`(LAME 快速档)| ~250x | +15% |
| `-ac 1`(单声道)| ~340x | +55% |
| `-ac 1 -compression_level 9` | ~600x | **+170%(约 2.7 倍)** |

3 分钟歌曲最快约 **0.3 秒**转完;瓶颈始终在 LAME 编码器的单核计算上,而非解码或磁盘 I/O。

**提速手段(按收益排序):**

1. **批量并行(收益最大)**:单文件转码无法多线程,但批量场景可多进程并行吃满所有核心。`mp3-320-to-32.sh` 已内置(`JOBS=` 控制并发数,默认全部核心);16 核机器批量吞吐可达数千倍实时。
2. **`MONO=1`(即 `-ac 1`)**:32 kbps 下立体声声道带宽严重不足,转单声道不仅快 50%+ ,听感也明显更好——**推荐默认开启**。
3. **`LEVEL=9`(即 `-compression_level 9`)**:LAME 最快档,再快 15~20%;32 kbps 极低码率下与默认质量的听感差异很小。
4. **二进制已是 `-O3` 编译**:比体积优化的 `-Os` 版再快 20~30%,体积仅多 0.4 MB(1.9 MB vs 1.5 MB),无需额外操作。
5. 不建议用降采样率提速:实测 `-ar 24000` 的重采样开销会吃掉低码率编码省下的时间,速度反而略降。

## 内置能力(刻意裁剪,仅此而已)

| 组件 | 内容 |
|---|---|
| 解码器 | mp3 / mp3float |
| 编码器 | libmp3lame(320k→32k 的实际转换由它完成) |
| 容器 | mp3 demuxer + mp3 muxer(含 ID3/Xing 头) |
| 协议 | file |
| 过滤器 | aresample、aformat、anull(CLI 转码管线必需) |
| 关闭 | 网络、视频、设备、ffprobe/ffplay、其余全部编解码器 |

非 MP3 输入(AAC、FLAC、视频等)会直接报 `Invalid data found when processing input`,无法使用。

## 兼容性验证结果

- `file ffmpeg` → `ELF 64-bit ... x86-64, statically linked, stripped`;`ldd` → `not a dynamic executable`
- 在 **Alpine 3.22.2**(musl)chroot 环境中实测:30 秒 320 kbps 文件(1.1 MB)
  → `./ffmpeg -i test.mp3 -b:a 32k out.mp3` → **117.6 KB,恒定 32 kb/s,44.1 kHz**
- 因为是全静态 musl 二进制,不依赖目标机的任何库,glibc 发行版(Debian/CentOS 等)同样能运行。

## 重新编译

**方式一:Ubuntu/Debian 上交叉编译(本仓库 build.sh,产物与交付二进制一致)**

```sh
sh build.sh    # 自动安装 musl-tools,编译 LAME 静态库 + FFmpeg,约几分钟
```

**方式二:直接在 Alpine 上原生编译**

```sh
apk add build-base nasm musl utils bash wget xz tar
# 1) 先用系统源静态编译 LAME:
apk add lame-static   # main 仓库提供 lame 静态库;若无,可源码编译 LAME(--disable-frontend)
# 2) 编译 FFmpeg(与 build.sh 中相同的 configure 参数,把 --cc=musl-gcc 改为 --cc=gcc,
#    --extra-cflags/-L 指向系统 lame 静态库路径,并保留 --extra-ldflags=-static)
```

> 源码构建的核心就是这段 configure 参数:
> `--disable-everything --enable-static --disable-shared --disable-network --disable-doc --disable-debug --disable-avdevice --disable-swscale --disable-postproc --enable-libmp3lame --enable-encoder=libmp3lame --enable-decoder=mp3 --enable-decoder=mp3float --enable-demuxer=mp3 --enable-muxer=mp3 --enable-parser=mpegaudio --enable-protocol=file --enable-filter=aresample --enable-filter=aformat --enable-filter=anull --extra-ldflags=-static`

## 说明

- 32 kbps 是 MP3 规范允许的最低 MPEG-1 Layer III 码率,音质损失显著(用于语音/播客/低带宽场景较合适);`-ac 1` 单声道可明显改善。
- 精简版同样支持任意输入码率的 MP3(320k、256k、VBR 等),统一重编码为 32k CBR。
- 许可:FFmpeg 核心与 LAME 均为 LGPL,二进制按 LGPL-2.1+ 分发,详见 COPYING.LGPLv2.1。
