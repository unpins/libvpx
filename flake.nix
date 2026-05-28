{
  description = "Standalone build of the libvpx VP8/VP9 codec tools (vpxenc / vpxdec)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libvpx ships its CLI tools (vpxenc / vpxdec) as "examples". The shared
  # nix-lib overlay used by ffmpeg builds the library only (examplesSupport
  # off — ffmpeg just wants libvpx.a); here multicall.nix turns the examples
  # back on and post-links vpxenc + vpxdec into a single `vpx` binary. See
  # ./multicall.nix for the link mechanics.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      mk = pkgs: extra: import ./multicall.nix { lib = pkgs.lib // ulib; } extra;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "vpx";

      # Linux passes through; darwin needs the overlay's osxMinVersion bridge +
      # darwin23 target rewrite. Examples are on by upstream default here.
      # The tools pull C++ (vendored webm); on darwin clang++ would link
      # /usr/lib/libc++.1.dylib (forbidden by the single-binary policy), so
      # static-link libc++ into the final link — same as srt/x265's darwin
      # branch. Linux pkgsStatic links libstdc++ statically already.
      build = pkgs:
        let sp = pkgs.pkgsStatic; in
        mk pkgs ({
          pkgs = sp;
          libvpx = ulib.nativeFixes.libvpx sp;
        } // pkgs.lib.optionalAttrs sp.stdenv.hostPlatform.isDarwin {
          extraLinkFlags = "-nostdlib++ ${sp.libcxx}/lib/libc++.a ${sp.libcxx}/lib/libc++abi.a";
        });

      # mingw cross. cross.libvpx carries the overlay's target=x86_64-win64-gcc
      # + CROSS + winpthreads fixes (and examplesSupport=false, which
      # multicall.nix flips back via configureFlags — re-`.override`ing would
      # discard those overrideAttrs). The examples link C++ (webm) and pull the
      # mingw runtime as DLLs unless the final link forces it static.
      windowsBuild = pkgs:
        let cross = ulib.mingwStaticCross pkgs; in
        mk pkgs {
          pkgs = cross;
          libvpx = cross.libvpx;
          extraLinkFlags = "-static -static-libgcc -static-libstdc++";
        };
    };
}
