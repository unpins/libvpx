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

      # A 64x64 3-frame Y4M gradient, gzipped so the constant stays small.
      # Content matters: a flat image would round-trip through a broken
      # transform too.
      probeY4mB64 = "H4sIAAAAAAACA+2a6zvXdxzG21q1bGlKo0I/NCIWv5zCiPwcI+UUhSKh5FgYMcqh0IhYKFIay+gkorRamqJp2dpqa2vn8/l83t7X1R9wP7ifuX6v6/pe3wfvR/f98PW5w0NCbfwDVV5KRZidjcJbPk+lraO1widV4WYt/2U2SqtNqXHxGp6r3PxVGhMeevjRx7R19RTzF1hY2Tg4L/XwXh4YvHrtug0JSalbs7cXFO2qqNq3/8Ch1vYXT3SfPX9x8Or11964fff9jz//+vuff/974pRHps/UmTvP2HThosX2Tq7LvPxWBIWtiY6N35ySkZX7zM7S8sqa5xqbj7R1HD/de+6ly0MjN15/6517H3321Xc//fbXf5M1NGc8PsfAyMT8SaWdo4u7p2/AqtCIqJiNm5LTM3Pyd5SUPVtd19B0+PljXad6+i+8/Mrw6Nibb7/34adffvvjr3/+++DUaVqzZusbPmFmaW275Ck3lY//ypDwyPVxiVvStj2dV1i8e8/e2vqDLUdf6Dx5pm/g0pVrr968defdDz754psffvnjnwcmUeGlPCq8lEeFl/Ko8FIeFV7Ko8JLeVR4KY8KL+VR4aU8KryUR4WX8qjwUh4VXsqjwkt5VHgpjwov5VHhpTwqvJRHhZfyqPBSHhVeyqPCS3lUeCmPCi/lUeGlPCq8lEeFl/Ko8FIeFV7Ko8JLeVR4KY8KL+VR4aU8KryUR4WX8qjwUh4VXsqjwkt5VHgpjwov5VHhpTwqvJRHhZfyqPBSHhVeyqPCS3lUeCmPCi/lUeGlPCq8lEeFl/Ko8FIeFV7Ko8JLeVR4KY8KL+VR4aU8KryUR4WX8qjwUt6ESRrTtWcbGC+wVNo7u3n6BYZERG9ITM7IzttRWrG3rlF9V9/V93F8B0wBaAJmAfQAxgBzgDXAAeAK8AT4A4IBawAxgERAKiALkA8oBlQAagANgBZAO+A4oAcwABgEjADGAHcA918BtEiNrE1qZB1SI88hNbI+qZEVpEY2JjWyCamRzUiNbEFq5EWkRlaSGtmW1MgOpEZ2IjWyC6mR3UiN7EFqZC9SI/uSGtmf1MiBpEYOIjVyKKmRw0mNvJbUyNGkRo4hNXIcqZETSI28mdTIyaRGTiM18lZSI2eRGjmH1Mh5pEYuIDXyTlIjl5AaeTepkStIjVxJauRqUiPXkhp5P6mRG0mN3ERq5BZSI7eSGrmN1MjHSI3cSWrkE6RGPk1q5B5SI/eRGplz6N1nOYfee45z6P0XOIc+cIkKL+VR4aU8KryUN1Vzpq6+kamFtZ3TUpXviuDwqNiELelZ2wtLyqtqG5pb1Xf1XX0fv/eJAA2AFkAXMA9gArAE2ACcAO4AH0AgIAwQBYgDJAEyADmAQsAuQCWgDnAQ0AroAJwC9AEuAoYAo4BbgLuA+68A5BTbgJxiG5JT7PnkFNuUnGKbk1NsS3KKbUVOsReTU2w7coq9hJxiO5NTbFdyiu1OTrFV5BTbm5xi+5FT7AByir2SnGIHk1PsMHKKHUFOsSPJKfY6coodS06xN5JT7ERyip1ETrFTyCl2OjnF3kZOsbPJKXYuOcXOJ6fYheQUu4icYpeSU+wycoq9h5xiV5FT7Bpyil1HTrHrySn2AXKK3UxOsQ+TU+yj5BS7nZxid5BT7C5yin2SnGJ3k1PsXnKK3U9OsQcGSY08RGrkYVIjcw79yjXOoV+9zjn0kRucQx8do8JLeVR4KY8KL+XN0NEzNFloZevo6uETELQ6MiY+KS0zt6C4rHJffdOR9k71XX1X38fvfTJgGkAbMBdgBDADWAHsAS4AFWA5IAgQAVgPSACkADIBeYAiQDmgGlAPOARoA3QBzgDOAy4DhgE3AbcB9wD/AzouNCM7SAAA";

      # Encode/decode guard. VP9's --lossless=1 makes the round trip exact, so
      # the check is a byte comparison and not a quality threshold — but only
      # over the FRAME payload: vpxdec rewrites the Y4M header (it emits the
      # frame rate in its own units and drops the aspect-ratio tag), so `cmp`
      # on the whole file fails on a perfectly good decode.
      #
      # This sits on the libvpx derivation, where vpxenc and vpxdec are still
      # two programs in the `bin` output — the fold into a single `vpx` happens
      # in a later derivation, and is what the smoke covers. So the guard tests
      # the codec, and the smoke tests the dispatch.
      #
      # Also runs the pair through IVF and through stdout: on Windows the CRT
      # opens stdio in text mode, which corrupts binary output, and `-o -` is
      # the only path that would show it.
      withRoundTrip = pkgs: drv: drv.overrideAttrs (old: {
        doInstallCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
        installCheckPhase = ''
          runHook preInstallCheck
          enc="''${bin:-$out}/bin/vpxenc"
          dec="''${bin:-$out}/bin/vpxdec"
          echo '${probeY4mB64}' | base64 -d | gzip -d > p.y4m

          "$enc" --codec=vp9 --lossless=1 -o p9.webm p.y4m
          "$dec" -o back.y4m p9.webm
          tail -n +2 p.y4m > a.raw
          tail -n +2 back.y4m > b.raw
          cmp a.raw b.raw || { echo "VP9 lossless round trip is not exact"; exit 1; }

          "$enc" --codec=vp9 --lossless=1 --ivf -o - p.y4m > p9.ivf
          test -s p9.ivf || { echo "vpxenc wrote nothing to stdout"; exit 1; }
          "$dec" --i420 -o - p9.ivf > o.raw
          "$dec" --i420 -o f.raw p9.ivf
          cmp o.raw f.raw || { echo "vpxdec stdout differs from its file output"; exit 1; }

          "$enc" --codec=vp8 -o p8.webm p.y4m
          "$dec" -o back8.y4m p8.webm
          test -s back8.y4m || { echo "the VP8 encoder produced nothing decodable"; exit 1; }

          echo "installCheck: VP9 lossless round trip exact, VP8 encodes, binary stdout clean"
          runHook postInstallCheck
        '';
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "vpx";

      # Multicall: an installed `vpxenc`/`vpxdec` dispatches by argv[0]; the bare
      # binary takes the applet via --unpin-program. vpxenc/vpxdec pull the VENDORED
      # webm parser (webmdec.cc / webmenc.cc), so the link is C++ — requires.cxx.
      # There is NO external C++ library (the webm parser is self-contained), so
      # the bitcode self-fold links libstdc++ statically without dragging a
      # forbidden libc++.1.dylib.
      smoke = [ "--unpin-program=vpxenc" "--help" ];
      # Anchored on the applet name: a bare "Usage:" also matches vpxdec, and
      # matches the message an unrecognized option prints — so it would stay
      # green if the dispatcher handed the smoke the wrong program, or if
      # --help stopped being a valid option at all.
      smokePattern = "^Usage: vpxenc";

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles libvpx (examples on) to bitcode and the standalone
      # self-folds vpxenc + vpxdec into one `vpx` binary on every target.
      pkgsAttr = "libvpx";
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [
          # libvpx installs no man pages at all.
          { name = "vpxenc"; noMan = true; }
          { name = "vpxdec"; noMan = true; }
        ];
        requires.cxx = true;
      };

      # Examples → bitcode → engine self-fold. The tools pull C++ (vendored
      # webm); requires.cxx folds libc++ statically, which also settles the
      # /usr/lib/libc++.1.dylib the darwin allowlist rejects.
      build = pkgs: withRoundTrip pkgs (withExamples pkgs.pkgsStatic);

      # mingw cross — the same helper. mingw-overlay/libvpx.nix already gave the
      # scope's libvpx its target=x86_64-win64-gcc + CROSS + winpthreads fixes;
      # withExamples layers nativeFixes.libvpx on top, whose engine branch (the
      # VFS depfile + gnu_strip breakages) now applies here too.
      windowsBuild = pkgs: withExamples (ulib.mingwStaticCross pkgs);
    };
}
