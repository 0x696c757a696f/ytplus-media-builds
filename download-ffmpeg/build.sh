#!/usr/bin/env bash
# Builds the ffmpeg.exe and ffprobe.exe YTPlus gives yt-dlp for downloads.
#
#   build.sh <x86_64|x86_64-v3|aarch64> <ffmpeg source> <zlib source> <output folder>
#
# They only join and repackage what yt-dlp downloaded (stream copy into MP4,
# MKV or WebM, HLS remux, m3u8/m4a fixups, metadata and subtitles), so this is
# an LGPL build with no external codec libraries, hardware decoding, devices
# or encoders beyond a few small native ones. All demuxers, muxers, parsers,
# bitstream filters and protocols stay: --disable-everything breaks merges.
# The playback FFmpeg inside libmpv is built separately and keeps everything.
#
# Uses llvm-mingw from PATH (<triple>-clang); set CROSS_CC=gcc to use a
# mingw-w64 GCC instead (x86_64 only, for a quick local check).
set -euo pipefail

arch=$1 src=$(realpath "$2") zlib=$(realpath "$3")
mkdir -p "$4"
out=$(realpath "$4")
case $arch in
  x86_64) triple=x86_64-w64-mingw32 cpu=x86_64 march="-march=x86-64 -mtune=generic" ;;
  x86_64-v3) triple=x86_64-w64-mingw32 cpu=x86_64 march="-march=x86-64-v3" ;;
  aarch64) triple=aarch64-w64-mingw32 cpu=aarch64 march="" ;;
  *) echo "unknown architecture $arch" >&2; exit 2 ;;
esac
cc=${CROSS_CC:-clang}
if [[ $cc == gcc ]]; then
  cxx=g++ ar=$triple-ar ranlib=$triple-ranlib nm=$triple-nm strip=$triple-strip lto=""
else
  ar=llvm-ar ranlib=llvm-ranlib nm=llvm-nm strip=llvm-strip lto="--enable-lto=thin"
fi

work=$(mktemp -d)
prefix=$work/prefix
mkdir -p "$prefix"

# zlib: gzip-encoded HTTP responses and compressed MP4 headers.
cp -r "$zlib" "$work/zlib"
make -C "$work/zlib" -f win32/Makefile.gcc -j"$(nproc)" \
  CC="$triple-$cc" AR="$ar" RC="$triple-windres" STRIP="$strip" CFLAGS="-O2 $march" libz.a
install -D -m644 "$work/zlib/libz.a" "$prefix/lib/libz.a"
install -D -m644 "$work/zlib/zlib.h" "$prefix/include/zlib.h"
install -D -m644 "$work/zlib/zconf.h" "$prefix/include/zconf.h"

decoders="h264,hevc,vp8,vp9,av1,mpeg4,mjpeg,png,webp,aac,aac_latm,ac3,eac3,opus,vorbis,mp3,mp3float,flac,alac,pcm_s16le,pcm_s16be,pcm_f32le,ass,ssa,srt,subrip,webvtt,mov_text,text"
encoders="aac,flac,pcm_s16le,mjpeg,png,ass,ssa,srt,subrip,webvtt,mov_text"
filters="aresample,anull,null,copy,acopy,format,aformat,setpts,asetpts,scale"

mkdir -p "$work/build"
cd "$work/build"
"$src/configure" \
  --enable-cross-compile --target-os=mingw32 --arch="$cpu" \
  --cross-prefix="$triple-" --cc="$triple-$cc" --cxx="$triple-${cxx:-clang++}" \
  --ar="$ar" --ranlib="$ranlib" --nm="$nm" --strip="$strip" \
  --pkg-config=false \
  --extra-cflags="-I$prefix/include $march" \
  --extra-ldflags="-L$prefix/lib -static" \
  $lto \
  --disable-autodetect --disable-debug --disable-doc --enable-small \
  --disable-shared --enable-static \
  --disable-ffplay --enable-ffmpeg --enable-ffprobe \
  --disable-avdevice --disable-devices --disable-hwaccels \
  --disable-encoders --enable-encoder="$encoders" \
  --disable-decoders --enable-decoder="$decoders" \
  --disable-filters --enable-filter="$filters" \
  --enable-zlib --enable-schannel \
  > configure.log || { tail -40 configure.log; tail -80 ffbuild/config.log; exit 1; }
grep -q '^License: LGPL' configure.log || { echo 'not an LGPL configuration' >&2; exit 1; }
make -j"$(nproc)" > make.log 2>&1 || { tail -60 make.log; exit 1; }
"$strip" -o "$out/ffmpeg.exe" ffmpeg.exe
"$strip" -o "$out/ffprobe.exe" ffprobe.exe

# What the LGPL asks to ship with it: the licence and where the source is.
cp "$src/COPYING.LGPLv2.1" "$out/"
{
  echo "FFmpeg $(git -C "$src" describe --tags --always) for YTPlus downloads ($arch)"
  echo "Source: https://github.com/FFmpeg/FFmpeg/tree/$(git -C "$src" rev-parse HEAD)"
  echo "zlib: https://github.com/madler/zlib/tree/$(git -C "$zlib" rev-parse HEAD)"
  echo "Built by https://github.com/0x696c757a696f/ytplus-media-builds (download-ffmpeg/build.sh)"
  echo
  echo "Configuration: $(sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"$/\1/p' config.h)"
  grep -m1 -A0 '^License' configure.log
} > "$out/BUILD.txt"
rm -rf "$work"
ls -l "$out"
