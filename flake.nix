{
  description = "the libvpx VP8/VP9 codec tools (vpxenc / vpxdec) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libvpx ships its CLI tools (vpxenc / vpxdec) as "examples". The shared
  # nix-lib overlay used by ffmpeg builds the library only (examplesSupport
  # off — ffmpeg just wants libvpx.a); here we turn the examples back on and
  # nix-lib self-folds vpxenc + vpxdec into a single `vpx` binary.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;

      # libvpx with the example CLIs (vpxenc/vpxdec) turned back on. The shared
      # overlay used by ffmpeg disables examples (`--disable-examples`,
      # `--disable-install-bins`) because ffmpeg wants only libvpx.a; here we
      # rewrite those flags back on (re-`.override`ing examplesSupport would
      # discard the darwin/mingw overrideAttrs). Shared by every target — the
      # engine gates below key off the scope's own cc, so the mingw cross picks
      # them up too now that it runs on the adapter.
      withExamples = scope:
        let isEngine = scope.lib.hasInfix "unpin-cc" (scope.stdenv.cc.name or ""); in
        (ulib.nativeFixes.libvpx scope).overrideAttrs (old: {
          # SIMD stays ON: libvpx's kernels (vpx_*_sse2/ssse3/avx2, the per-arch
          # NEON/VSX equivalents) are yasm/asm objects that can't enter the -flto
          # bitcode module, but the engine hook rescues native objects into a
          # sidecar (module_native.a) the self-fold links alongside module.bc, so
          # they resolve. A pure-C `--target=generic-gnu` build links too, and
          # measured 48-50 fps against 124-132 fps for the same bit-identical VP9
          # encode — 2.6x, not a tradeoff worth taking.
          configureFlags =
            (builtins.filter
              (f: f != "--disable-examples" && f != "--disable-install-bins")
              (old.configureFlags or [ ]))
            ++ [ "--enable-examples" "--enable-install-bins" ];
          # Engine path: libvpx generates per-object `.d` dependency files with
          # `$(CC) -M $< | $(fmt_deps)` and `-include`s them on the next make
          # pass. The unpin-llvm engine's clang resolves its musl libc headers
          # through a VFS-virtual sysroot (`/__unpin_ziglib__/…`) that has no
          # on-disk existence, so those header paths land in the `.d` files as
          # make prerequisites that make can't satisfy ("No rule to make target
          # '/__unpin_ziglib__/…/string.h'"). Extend the emitted `fmt_deps` sed
          # to drop any prerequisite under that virtual root — they are stable
          # toolchain headers, never a reason to rebuild, so dropping them only
          # loses header-edit tracking we don't use in a one-shot Nix build.
          postPatch = (old.postPatch or "") + scope.lib.optionalString isEngine ''
            substituteInPlace build/make/configure.sh \
              --replace-fail \
                "fmt_deps = sed -e " \
                "fmt_deps = sed -e 's;[ ]/__unpin_ziglib__[^ ]*;;g' -e "
            # Engine path: objects/archives are LLVM bitcode (under -flto), not
            # ELF. libvpx's `%.a: %_g.a` rule runs `$(STRIP) --strip-debug` on
            # each archive when configure detects GNU strip — but `llvm-strip`
            # rejects bitcode archive members ("not recognized as a valid object
            # file"). Disable the gnu_strip feature so the rule falls back to a
            # plain `cp`; the final shipped binary is stripped by nix-lib's own
            # strip pass downstream.
            substituteInPlace build/make/configure.sh \
              --replace-fail \
                'grep GNU >/dev/null && enable_feature gnu_strip' \
                'grep GNU >/dev/null && true'
          '';
        });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "vpx";

      # Multicall: `vpx <applet> [args]` dispatches by argv[0]; the bare binary
      # takes the applet via --unpin-program. vpxenc/vpxdec pull the VENDORED
      # webm parser (webmdec.cc / webmenc.cc), so the link is C++ — requires.cxx.
      # There is NO external C++ library (the webm parser is self-contained), so
      # the bitcode self-fold links libstdc++ statically without dragging a
      # forbidden libc++.1.dylib.
      smoke = [ "--unpin-program=vpxenc" "--help" ];
      smokePattern = "Usage:";

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles libvpx (examples on) to bitcode and the standalone
      # self-folds vpxenc + vpxdec into one `vpx` binary on every target.
      pkgsAttr = "libvpx";
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [
          { name = "vpxenc"; }
          { name = "vpxdec"; }
        ];
        requires.cxx = true;
      };

      # Examples → bitcode → engine self-fold. The tools pull C++ (vendored
      # webm); requires.cxx folds libc++ statically, which also settles the
      # /usr/lib/libc++.1.dylib the darwin allowlist rejects.
      build = pkgs: withExamples pkgs.pkgsStatic;

      # mingw cross — the same helper. mingw-overlay/libvpx.nix already gave the
      # scope's libvpx its target=x86_64-win64-gcc + CROSS + winpthreads fixes;
      # withExamples layers nativeFixes.libvpx on top, whose engine branch (the
      # VFS depfile + gnu_strip breakages) now applies here too.
      windowsBuild = pkgs: withExamples (ulib.mingwStaticCross pkgs);
    };
}
