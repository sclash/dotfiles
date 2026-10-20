// Appends the nix-ld library directory to LD_LIBRARY_PATH for shell commands.
//
// Why: NixOS does not put libstdc++ (or glib, nss, ...) on the default loader
// path. Anything that loads a PyPI wheel or a downloaded binary therefore fails:
//
//   ImportError: libstdc++.so.6: cannot open shared object file
//
// The deeper reason is that nixpkgs links with DT_RUNPATH, which glibc applies
// only to the object's own DT_NEEDED entries -- never to dlopen'd children. A
// PyPI wheel's .so files carry no RPATH of their own, so the interpreter's
// RUNPATH cannot satisfy them. LD_LIBRARY_PATH is the only per-process lever.
//
// Two distinct cases, and this hook only needs to cover one of them:
//
//  1. Nix-built programs (python, uv, node) loading PyPI wheels. Their own RPATH
//     is consulted first and is unaffected; the wheels themselves have no RPATH
//     and fall through to LD_LIBRARY_PATH. This is the case that matters here.
//
//  2. Non-Nix binaries (Playwright's bundled Chromium, for example). These
//     already resolve through nix-ld's own loader via the NIX_LD shim, which is
//     configured by programs.nix-ld.libraries in configuration.nix -- this hook
//     cannot help those. Extend that list instead.
//
// Ordering caveat: any entry in LD_LIBRARY_PATH outranks DT_RUNPATH, not just a
// leading one. So a libstdc++ sitting here shadows the runtime a Nix binary was
// deliberately linked against. The nix-ld dir is appended last so it acts as a
// fallback for libraries nothing else provides (libz, libzstd, libuuid, ...).

import { Plugin } from "@opencode/plugin";

const NIX_LD_LIB = "/run/current-system/sw/share/nix-ld/lib";

// V2 plugin. The V1 hook key was "shell.env"; V2 registers the same mutation as
// ctx.shell.hook("create.before") on the event's env.
export default Plugin.define({
  id: "nix-ld-env",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      const existing = event.env.LD_LIBRARY_PATH;
      if (existing === NIX_LD_LIB) return;
      if (!existing) {
        event.env.LD_LIBRARY_PATH = NIX_LD_LIB;
        return;
      }
      const parts = existing.split(":").filter(Boolean);
      if (parts.includes(NIX_LD_LIB)) return;
      event.env.LD_LIBRARY_PATH = `${existing}:${NIX_LD_LIB}`;
    });
  },
});
