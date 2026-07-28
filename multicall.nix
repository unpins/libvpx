# Upstream libvpx builds two CLI tools — vpxenc and vpxdec — as "examples".
# To honour the unpins one-pkg-one-bin rule we post-link them into a single
# multicall binary at $out/bin/vpx; `lib.withAliases` then embeds the tool
# names as an UNPIN_META block so unpin's installer can recreate the argv[0]
# shims.
#
# libvpx's link mechanics (vs srt/CMake, librist/meson, rtmpdump/Makefile):
#
#   * The build is a recursive make (`make target=<t> vpxenc`), so there is no
#     top-level link line to query with `make -n`. We construct the link
#     directly — which is easy here because every tool/util translation unit is
#     compiled ONCE into <name>.c.o / <name>.cc.o at the source root and shared
#     between the two tools (args, tools_common, y4minput, ivfdec/ivfenc,
#     webmdec/webmenc, video_reader/writer, …). So the only symbol that clashes
#     between vpxenc.c.o and vpxdec.c.o is `main`; everything else is a single
#     shared object. We link the whole root object set + libvpx.a once.
#
#   * vpxdec/vpxenc pull the vendored webm parser (webmdec.cc / webmenc.cc), so
#     the link is C++ — use $CXX (libstdc++). On mingw `extraLinkFlags`
#     (-static -static-libgcc -static-libstdc++) folds the runtime in so the
#     .exe carries no libstdc++-6 / libgcc_s / libwinpthread DLLs.
{ lib }:
{ pkgs, libvpx, name ? "vpx", extraLinkFlags ? "" }:
let
  multicall = libvpx.overrideAttrs (old: {
    pname = "libvpx-multi";

    # Re-enable the examples the library overlay turns off (ffmpeg wants only
    # libvpx.a). Done by rewriting configureFlags rather than re-`.override`ing
    # examplesSupport — the latter would discard the mingw overlay's target /
    # CROSS / winpthreads overrideAttrs. Filtering an absent flag is a no-op, so
    # this is also correct on linux/darwin (examples already on there).
    configureFlags =
      (builtins.filter
        (f: f != "--disable-examples" && f != "--disable-install-bins")
        (old.configureFlags or [ ]))
      ++ [ "--enable-examples" "--enable-install-bins" ];

    # Ship only the multicall binary.
    outputs = [ "out" ];
    separateDebugInfo = false;
    postInstall = "";

    postBuild = (old.postBuild or "") + ''
      mkdir -p multicall

      # Tool mains live at the source root as <tool>.c.o. Existence gates a
      # platform that ever drops one.
      apps=()
      for a in vpxenc vpxdec; do
        [ -f "$a.c.o" ] && apps+=("$a")
      done
      [ ''${#apps[@]} -ge 1 ] || { echo "multicall: no libvpx tools built" >&2; exit 1; }
      printf '%s\n' "''${apps[@]}" > multicall/apps.list

      # Symbol prefix (Mach-O leads C symbols with '_'), read once from a main.
      if $NM --defined-only "''${apps[0]}.c.o" | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      # Rename each tool's main → <tool>_main (distinct entry points) and
      # usage_exit → <tool>_usage_exit. usage_exit is a callback contract: the
      # SHARED tools_common.c.o calls usage_exit(), and each tool defines its
      # own — so we can't keep one global copy (the tools differ) nor rename it
      # away (tools_common's reference would dangle). The dispatcher below
      # provides a single usage_exit() trampoline that forwards to the active
      # tool's via a function pointer. (main + usage_exit are the only two
      # symbols both mains define — verified with nm.)
      for a in "''${apps[@]}"; do
        $OBJCOPY \
          --redefine-sym "''${up}main=''${up}''${a}_main" \
          --redefine-sym "''${up}usage_exit=''${up}''${a}_usage_exit" \
          "$a.c.o"
      done

      # Dispatcher: basename(argv[0]) → <tool>_main, '.exe' stripped (alias
      # path), plus a `${name} --unpin-program=<applet>` selector for the bare
      # binary — the unified multicall contract (no positional form).
      #
      # NOTE: intentionally does NOT use the shared nix-lib
      # lib.multicallTableDispatcherC, and is the LONE hand-written dispatcher left in
      # the catalog (xmllint and openjpeg fold into the generator). It earns the
      # exception: vpxenc/vpxdec's shared tools_common.c.o reaches usage_exit()
      # through die() — the COMMON fatal-error path (vpxdec's "Unrecognized
      # option", bad --codec, output-name errors; 6 sites in vpxdec.c + 2 in
      # tools_common.c) — and each tool's usage_exit prints its OWN static
      # show_help (encoder vs decoder options, vpxenc.c vs vpxdec.c). This
      # dispatcher carries a per-tool function-pointer trampoline (g_usage_exit,
      # set on dispatch) so a bad-option vpxdec keeps showing the DECODER help,
      # not the encoder's.
      #
      # The shared generator has no such hook. Folding would mean either the
      # aom-style "keep one usage_exit global + --localize the rest" — which makes
      # every die()-path error print the OTHER tool's full banner (a real,
      # common-path UX regression; aom itself ships with exactly this) — or
      # bolting a hook parameter onto the generator for this single consumer
      # (aom can't even reuse it: its other hook exec_name is a DATA symbol, no
      # trampoline). Keeping the forwarding here, where it's needed, is the
      # deliberate call: the one genuine divergence the shared generator doesn't
      # model. (Unlike openjpeg, whose exit-0 banner the rewritten generator's
      # bare fallback already reproduced for free.)
      {
        echo '#include <string.h>'
        echo '#include <stdio.h>'
        echo '#include <stdlib.h>'
        for a in "''${apps[@]}"; do
          echo "int ''${a}_main(int, char **);"
          echo "void ''${a}_usage_exit(void);"
        done
        echo 'struct applet { const char *name; int (*fn)(int, char **); void (*usage)(void); };'
        echo 'static const struct applet applets[] = {'
        for a in "''${apps[@]}"; do
          echo "    {\"$a\", ''${a}_main, ''${a}_usage_exit},"
        done
        cat <<'CBODY'
    {0, 0, 0}
};
/* tools_common.c.o calls usage_exit(); forward to the active tool's copy. */
static void (*g_usage_exit)(void) = 0;
void usage_exit(void) { if (g_usage_exit) g_usage_exit(); exit(EXIT_FAILURE); }
static void copy_basename(char *dst, size_t cap, const char *src) {
    const char *p = src, *s;
    s = strrchr(p, '/'); if (s) p = s + 1;
#ifdef _WIN32
    s = strrchr(p, '\\'); if (s) p = s + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(dst, p, n); dst[n] = 0;
    if (n > 4 && strcmp(dst + n - 4, ".exe") == 0) dst[n - 4] = 0;
}
CBODY
        cat <<CBODY
static int usage(const char *a0) {
    fprintf(stderr, "${name}: multicall binary; usage: %s <applet> [args]\n", a0);
    fprintf(stderr, "applets:");
    for (const struct applet *a = applets; a->name; a++)
        fprintf(stderr, " %s", a->name);
    fprintf(stderr, "\n");
    return 1;
}
int main(int argc, char **argv) {
    char base[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "${name}";
    copy_basename(base, sizeof base, a0);
    int is_canon = strcmp(base, "${name}") == 0;
    /* Alias path: a symlink named after an applet (not the canonical name)
       runs via argv[0]; --unpin-program is ignored (identity lock). The active
       tool's usage_exit hook is wired before dispatch. */
    if (!is_canon)
        for (const struct applet *a = applets; a->name; a++)
            if (strcmp(base, a->name) == 0) { g_usage_exit = a->usage; return a->fn(argc, argv); }
    /* Multitool: --unpin-program=NAME selects the applet (no positional form). */
    if (argc >= 2 && strncmp(argv[1], "--unpin-program=", 16) == 0) {
        const char *sel = argv[1] + 16;
        for (const struct applet *a = applets; a->name; a++)
            if (strcmp(sel, a->name) == 0) {
                argv[1] = (char *)sel; g_usage_exit = a->usage; return a->fn(argc - 1, argv + 1);
            }
        fprintf(stderr, "${name}: no program '%s'\n", sel);
        return usage(a0);
    }
    return usage(a0);
}
CBODY
      } > multicall/dispatcher.c
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # The full object set: both tool mains + every shared util/webm object at
      # the root, PLUS the vendored libwebm (mkvmuxer/mkvparser) and libyuv
      # (I420Scale…) objects under third_party/ — the examples reference these
      # but they're NOT folded into libvpx.a, so they must be listed explicitly.
      # Linked once; the linker pulls what each main references and the rest
      # ride along (only `main` clashes). $CXX for the C++ objects.
      objs=$(echo *.c.o *.cc.o)
      for d in third_party/libwebm third_party/libyuv; do
        [ -d "$d" ] && objs="$objs $(find "$d" \( -name '*.cc.o' -o -name '*.c.o' \) | tr '\n' ' ')"
      done

      # Demangler so a C++ clash the linker reports maps back to the raw nm
      # symbol objcopy needs (ld64 always demangles; GNU ld gets --no-demangle).
      nodemangle=-Wl,--no-demangle
      case "$($CC -dumpmachine)" in *darwin*) nodemangle="" ;; esac
      nmdir=$(dirname "$(command -v ''${NM%% *})")
      demangle=cat
      for c in c++filt llvm-cxxfilt; do
        if [ -x "$nmdir/$c" ]; then demangle="$nmdir/$c"; break; fi
        command -v "$c" >/dev/null 2>&1 && { demangle=$c; break; }
      done

      # Iterative link: each failed attempt names the remaining *strong*
      # duplicates; rename those per-tool and relink. Trust the linker, not nm
      # (COFF reports COMDAT as strong). Pure-C mains here, so this normally
      # converges in one extra pass after `main`.
      converged=0
      for _ in $(seq 1 30); do
        if eval "$CXX $objs multicall/dispatcher.o -o multicall/${name} -L. -lvpx -lm -lpthread $nodemangle ${extraLinkFlags}" 2>multicall/link.err; then
          converged=1; break
        fi
        cat multicall/link.err >&2
        sed -nE "s/.*multiple definition of [\`']([^']+)'.*/\1/p; s/.*duplicate symbol '([^']+)'.*/\1/p" \
          multicall/link.err | sort -u > multicall/clash.syms
        [ -s multicall/clash.syms ] || { echo "multicall: link failed without a duplicate-symbol diagnostic" >&2; exit 1; }
        while IFS= read -r sym; do
          hit=0
          for a in "''${apps[@]}"; do
            obj="$a.c.o"
            $NM --defined-only "$obj" | awk '{print $3}' > multicall/raw.syms
            sed 's/^_//' multicall/raw.syms | $demangle > multicall/dem.syms
            raw=$(paste multicall/raw.syms multicall/dem.syms \
                  | awk -F'\t' -v s="$sym" '$1==s || $2==s {print $1; exit}')
            [ -n "$raw" ] || continue
            $OBJCOPY --redefine-sym "$raw=''${up}''${a}__''${raw#"$up"}" "$obj"
            hit=1
          done
          [ "$hit" = 1 ] || { echo "multicall: clashing symbol '$sym' not defined by any tool object" >&2; exit 1; }
        done < multicall/clash.syms
      done
      [ "$converged" = 1 ] || { echo "multicall: link did not converge in 30 passes" >&2; exit 1; }

      # mingw gcc may auto-append .exe; normalize to the suffixless name
      # installPhase + withAliases expect (Windows postFixup re-adds .exe).
      [ -f multicall/${name} ] || mv multicall/${name}.exe multicall/${name}
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 multicall/${name} "$out/bin/${name}"
      while IFS= read -r a; do
        [ -n "$a" ] && ln -s ${name} "$out/bin/$a"
      done < multicall/apps.list
      runHook postInstall
    '';
  });
  aliased = lib.withAliases pkgs
    {
      primary = name;
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if pkgs.stdenv.hostPlatform.isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/${name}" ] && mv "$out/bin/${name}" "$out/bin/${name}.exe"
  '';
})
else aliased
