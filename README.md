# libvpx

The [libvpx](https://www.webmproject.org/code/) VP8/VP9 codec command-line programs, as a single self-contained binary built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/libvpx/actions/workflows/libvpx.yml/badge.svg)](https://github.com/unpins/libvpx/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install libvpx`.

Encode and decode VP8/VP9 video.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin libvpx vpxenc --codec=vp9 -o out.webm in.y4m
unpin libvpx vpxdec -o out.y4m in.webm
```

`unpin install libvpx` also creates the commands `vpxenc` (encode) and `vpxdec` (decode):

```bash
unpin install libvpx
```

## Build locally

```bash
nix build github:unpins/libvpx
./result/bin/vpx
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/libvpx/releases) page has standalone binaries for manual download.

## Build notes

- **Single multicall binary** — `vpxenc` + `vpxdec` are post-linked into one `vpx`; tool names are recreated as `argv[0]` shims on install. WebM in/out and libyuv scaling are included.
- **No man pages** — libvpx ships none upstream; both tools print their options with `--help`.
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs (the C++ webm/libyuv runtime is folded in statically).

The multicall link recipe is in [`multicall.nix`](./multicall.nix).
