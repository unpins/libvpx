# libvpx

Standalone build of the [libvpx](https://www.webmproject.org/code/) VP8/VP9 codec command-line tools.

[![Build](https://github.com/unpins/libvpx/actions/workflows/libvpx.yml/badge.svg)](https://github.com/unpins/libvpx/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

Encode and decode VP8/VP9 video. Ships as one multicall binary that dispatches to the upstream tools:

- `vpxenc` — encode Y4M/YUV input to a VP8/VP9 IVF or WebM stream.
- `vpxdec` — decode a VP8/VP9 IVF/WebM stream to Y4M/YUV.

Run a tool by name or via the dispatcher:

```bash
vpxenc --codec=vp9 -o out.webm in.y4m   # by name
vpx enc --codec=vp9 -o out.webm in.y4m  # via the vpx dispatcher
```

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin libvpx
```

Or run without installing:

```bash
unpin run libvpx -- vpxenc --help
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
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs (the C++ webm/libyuv runtime is folded in statically).

The multicall link recipe is in [`multicall.nix`](./multicall.nix).
