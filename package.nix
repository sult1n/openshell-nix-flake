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

  cargoHash = "sha256-4v3SuKRrEi97s4B1IDb0OCwo07/Ld4eKjgwYlXzYT+M=";

  # Requires a rustc >= 1.94 (workspace `rust-version`), i.e. a nixpkgs
  # revision from ~March 2026 onward (nixos-unstable is fine).
  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  # nixpkgs' cargoSetupHook (commit 44cddf9) forces aws-lc-sys, libsqlite3-sys,
  # zstd-sys and openssl-sys to link against system libraries, so provide them.
  # See https://github.com/NixOS/nixpkgs/issues/585124
  buildInputs = [
    z3
    aws-lc
    sqlite
    zstd
    openssl
  ];

  # Tools spawned by the openshell-cli test-suite:
  # - git: run/sandbox-upload tests drive local repos in tempdirs
  # - openssh: src/ssh.rs tests invoke the real `ssh` (e.g. `ssh -G`)
  # - procps: without `ps` the pid-reuse assertions in the lifecycle tests
  #   degrade to vacuous passes; keep them honest
  # - cacert: TLS trust store
  # coreutils (sleep/kill/printf/cp), tar (gnutar) and rustc are already on
  # the stdenv sandbox PATH.
  nativeCheckInputs = [
    cacert
    gitMinimal
    openssh
    procps
  ];

  # Belt: scope the check to the shipped crate even if the workspace member
  # restriction in postPatch ever stops applying. Older cargo-check-hooks
  # simply ignore this variable - then the patches + skips below carry it.
  cargoTestFlags = [ "-p" "openshell-cli" ];

  # Suspenders: timing-sensitive solver tests that are not reliable on loaded
  # build machines. `--skip` is passed to every test binary; binaries without
  # these tests simply ignore the pattern.
  checkFlags = [
    # openshell-prover: expects two Z3 solves to finish within a shared 10 s
    # budget before it can assert the fail-closed reason; failed twice here.
    "--skip=containment::tests::exact_boundary_deny_under_candidate_glob_requires_image_resolution"
    # openshell-prover-cli: asserts the child is still solving after 500 ms.
    "--skip=sigint_interrupts_the_check_with_exit_130"
  ];

  postPatch = ''
    # fill in package version to Cargo
    substituteInPlace Cargo.toml \
      --replace-fail 'version = "0.0.0"' 'version = "${finalAttrs.version}"'

    # Belt: restrict the workspace to the shipped crate. `cargo test` in a
    # virtual workspace runs the test-suite of EVERY member, and most non-CLI
    # crates are untestable in the Nix sandbox (audited against v0.1.7):
    # openshell-sandbox spawns /usr/bin/env, /bin/true, /bin/sleep (~26 tests),
    # openshell-driver-vm hardcodes PATH=/usr/bin:/bin, openshell-gateway's
    # preflight tests fake tools with /bin/sleep, openshell-core fakes tools
    # with /bin/sleep and /bin/dd. Patching 30+ upstream tests per release is
    # unmaintainable; the CLI crate is the artifact this package ships.
    substituteInPlace Cargo.toml \
      --replace-fail 'members = ["crates/*"]' 'members = ["crates/openshell-cli"]'

    # Suspenders: if the whole workspace does get tested anyway, make every
    # known sandbox-hostile test pass instead of failing one crate per rebuild.

    # openshell-core: fake mke2fs wrappers hardcode FHS paths; the Nix sandbox
    # has no /bin. Redirect to PATH lookups (coreutils); the timeout and
    # process-group behaviour under test is unaffected.
    substituteInPlace crates/openshell-core/src/e2fsprogs.rs \
      --replace-fail '/bin/sleep' 'sleep' \
      --replace-fail '/bin/dd' 'dd'

    # openshell-sandbox: tests spawn /usr/bin/env, /bin/true and /bin/sleep.
    substituteInPlace crates/openshell-sandbox/src/process.rs \
      crates/openshell-sandbox/src/child_env.rs \
      --replace-fail '/usr/bin/env' 'env'
    substituteInPlace crates/openshell-sandbox/src/boundary_exec.rs \
      crates/openshell-sandbox/src/boundary_server.rs \
      --replace-fail '/bin/true' 'true' \
      --replace-fail '/bin/sleep' 'sleep'
    substituteInPlace crates/openshell-sandbox/src/linux/child_seccomp.rs \
      --replace-fail '/bin/true' 'true'

    # openshell-gateway: preflight tests fake tools with /bin/sleep.
    substituteInPlace crates/openshell-gateway/tests/config_preflight.rs \
      --replace-fail '/bin/sleep' 'sleep'

    # openshell-driver-vm: two overlay tests run the driver with
    # PATH=/usr/bin:/bin and expect the real `cp` to be there. Point them at
    # the build PATH (expanded in the sandbox, where coreutils lives).
    substituteInPlace crates/openshell-driver-vm/tests/image_preparation.rs \
      --replace-fail '/usr/bin:/bin' "$PATH"
  '';

  env = {
    # docker image tag baked in at compile time, must match binary version
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
      NVIDIA OpenShell is an open source runtime to build and deploy autonomous,
      self-evolving agents more safely. OpenShell sits between your agent and
      your infrastructure to govern how the agent executes, what the agent can
      see and do, and where inference goes. It enables claws to run in isolated
      sandboxes, with fine-grained control over privacy and security.
    '';
    maintainers = with lib.maintainers; [ wishstudio ];
    mainProgram = "openshell";
    platforms = lib.platforms.all;
  };
})
