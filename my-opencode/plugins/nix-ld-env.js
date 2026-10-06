// Appends the nix-ld library directory to LD_LIBRARY_PATH for shell commands.
//
// Why: NixOS does not put libstdc++ (or glib, nss, ...) on the default loader
// path. Anything that loads a PyPI wheel or a downloaded binary therefore fails:
//
//   ImportError: libstdc++.so.6: cannot open shared object file
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
// Appended, never prepended: LD_LIBRARY_PATH is searched before DT_RUNPATH, so
// putting the nix-ld directory first would shadow the runtime a Nix binary was
// deliberately linked against.

const NIX_LD_LIB = "/run/current-system/sw/share/nix-ld/lib";

export default async () => {
  return {
    "shell.env": async (_input, output) => {
      const existing = output.env.LD_LIBRARY_PATH;
      if (existing === NIX_LD_LIB) return;
      if (!existing) {
        output.env.LD_LIBRARY_PATH = NIX_LD_LIB;
        return;
      }
      const parts = existing.split(":").filter(Boolean);
      if (parts.includes(NIX_LD_LIB)) return;
      output.env.LD_LIBRARY_PATH = `${existing}:${NIX_LD_LIB}`;
    },
  };
};