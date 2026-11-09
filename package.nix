{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
  cacert,
  gitMinimal,
  openssh,
  procps,
  pkg-config,
  z3,
  aws-lc,
  sqlite,
  zstd,
  openssl,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "openshell";
  version = "0.1.7";

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "OpenShell";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mBciX4fPWUtaszWhV8gCpYjQmuAJxKxkhwT6oVKq6jY=";
  };

  # cargoHash is computed by fetchCargoVendor from the PRISTINE source tree
  # (full Cargo.lock, members = crates/*) BEFORE postPatch runs, so patching
  # the workspace member list below does not change this hash.
  cargoHash = "sha256-4v3SuKRrEi97s4B1IDb0OCwo07/Ld4eKjgwYlXzYT+M=";

  # Disable nixpkgs' cargo-auditable integration (buildRustPackage arg,
  # on by default). Its wrapper runs `cargo metadata` for every rustc
  # invocation, passing the features of the crate being compiled
  # (reconstructed from `--cfg feature="..."`), and cargo applies those
  # features to EVERY workspace member. Compiling openshell-core with the
  # unified feature set {clap, driver-extraction, jwt, oauth, otel,
  # telemetry} therefore fails on members that lack these public features:
  # openshell-driver-vm has `clap` only as a `dep:`-gated optional
  # dependency (upstream cargo issue #12336; reproduced on a minimal
  # workspace). The manifest-level workaround would require adding six
  # alias features to every member crate, which is not maintainable. The
  # audit blob embedded by cargo-auditable is optional metadata; losing it
  # does not affect functionality.
  auditable = false;

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];
  # nixpkgs cargoSetupHook (commit 44cddf9) forces -sys crates to system libs
  buildInputs = [
    z3
    aws-lc
    sqlite
    zstd
    openssl
  ];

  # CLI test-suite tools; procps keeps pid-reuse assertions honest
  nativeCheckInputs = [
    cacert
    gitMinimal
    openssh
    procps
  ];

  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'version = "0.0.0"' 'version = "${finalAttrs.version}"'

    # Build both shipped binaries: the CLI and the gateway server. Note that
    # cargo auto-adds every path dependency residing in the workspace
    # directory as a member ("All path dependencies residing in the workspace
    # directory automatically become members", cargo book), so the effective
    # member set is the transitive path-dep closure of these two crates:
    # cargo build therefore also produces the standalone driver binaries
    # (openshell-driver-{docker,kubernetes,podman,kubernetes-secrets,vault}),
    # and cargoInstallHook copies every executable from target/release into
    # $out/bin. Extra binaries in $out/bin are expected and harmless.
    substituteInPlace Cargo.toml \
      --replace-fail 'members = ["crates/*"]' \
        'members = ["crates/openshell-cli", "crates/openshell-gateway"]'

    # Inert while core tests are not run; kept for future-proofing
    substituteInPlace crates/openshell-core/src/e2fsprogs.rs \
      --replace-fail '/bin/sleep' 'sleep' \
      --replace-fail '/bin/dd' 'dd'
  '';

  # Tests: run ONLY the CLI crate. nixpkgs' cargoCheckHook passes
  # cargoTestFlags before the `--` separator, so `-p` is parsed by cargo
  # itself (checkFlags would land after `--` as test-executable args and
  # break). Without -p, `cargo test` in a virtual workspace tests every
  # workspace member, and the path-dep closure (see the members comment
  # above) includes crates whose suites are untestable in the Nix sandbox
  # (audited v0.1.7):
  #  - openshell-sandbox: ~26 tests spawn /usr/bin/env, /bin/true, /bin/sleep
  #  - openshell-driver-vm: hardcoded PATH=/usr/bin:/bin, needs real cp
  #  - openshell-gateway: preflight tests fake tools with /bin/sleep
  #  - openshell-core: e2fsprogs tests fake tools with /bin/sleep, /bin/dd
  #  - openshell-prover: Z3 solver test with shared 10 s budget, timing-flaky
  # This makes checkPhase deterministic instead of passing by luck.
  cargoTestFlags = [ "-p" "openshell-cli" ];

  env = {
    OPENSHELL_IMAGE_TAG = finalAttrs.version;
  };

  doCheck = !stdenv.hostPlatform.isDarwin;

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    changelog = "https://github.com/NVIDIA/OpenShell/releases/tag/v${finalAttrs.version}";
    description = "The safe, private runtime for autonomous AI agents.";
    homepage = "https://docs.nvidia.com/openshell/index.html";
    license = lib.licenses.asl20;
    longDescription = ''
      NVIDIA OpenShell is the safe, private runtime for autonomous AI agents.
      It runs coding agents in isolated sandbox environments on the user's own
      infrastructure with policy-controlled filesystem, network and credential
      access. This package provides the `openshell` CLI and the
      `openshell-gateway` server binary for hosting sandboxes natively, e.g.
      with the rootless Podman compute driver.
    '';
    maintainers = with lib.maintainers; [ wishstudio ];
    mainProgram = "openshell";
    platforms = lib.platforms.all;
  };
})
