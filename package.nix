{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
  cacert,
  gitMinimal,
  openssh,
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

  nativeCheckInputs = [
    cacert
    gitMinimal
    # ssh.rs tests spawn the real `ssh` client
    openssh
  ];

  postPatch = ''
    # fill in package version to Cargo
    substituteInPlace Cargo.toml \
      --replace-fail 'version = "0.0.0"' 'version = "${finalAttrs.version}"'
    # only build openshell-cli crate
    substituteInPlace Cargo.toml \
      --replace-fail 'members = ["crates/*"]' 'members = ["crates/openshell-cli"]'

    # sandbox-incompatible test fixtures:
    # - openshell-core e2fsprogs tests generate fake mke2fs wrapper scripts
    #   invoking /bin/sleep and /bin/dd, which don't exist in the nix build
    #   sandbox; resolve them from PATH instead (coreutils is always there)
    # - openshell-sandbox-backend runtime test fixtures reference /bin/true
    #   as a program path; FHS paths don't exist in the nix build sandbox
    substituteInPlace crates/openshell-core/src/e2fsprogs.rs \
      --replace-fail '/bin/sleep' 'sleep' \
      --replace-fail '/bin/dd' 'dd'
    substituteInPlace crates/openshell-sandbox-backend/src/runtime.rs \
      --replace-fail '"/bin/true"' '"true"'
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
