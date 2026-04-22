#!/usr/bin/env bash
# Clone official llvm-project at upstream commit, fetch amd/ from ROCm llvm-project
# at rocm commit, then configure CMake, build, and install into build/install.
#
# Pick --upstream-commit to match the LLVM base the ROCm amd/ tree targets (rocm
# release notes or a tag on the rocm remote); a mismatch can break the build.

set -euo pipefail

ROCM_COMMIT_DEFAULT=61f9516af963d6ade5eed936c064b7b5433230b6

print_help() {
  cat <<EOF
Usage: $0 --repo-dir <path> --upstream-commit <ref> [--rocm-commit <ref>]

  Clones https://github.com/llvm/llvm-project.git at --upstream-commit, adds the
  ROCm fork as a remote, and checks out only amd/ from --rocm-commit (default:
  ${ROCM_COMMIT_DEFAULT}).

  Then configures <path>/build and runs ninja install.

  Environment (optional):
    LLVM_UPSTREAM_URL   Default: https://github.com/llvm/llvm-project.git
    ROCM_LLVM_URL      Default: https://github.com/ROCm/llvm-project.git
EOF
}

REQ_ERR=0
REPO_DIR=""
UPSTREAM_COMMIT=""
ROCM_COMMIT="${ROCM_COMMIT_DEFAULT}"

error() {
  echo "Error: $1" >&2
  REQ_ERR=1
}

arg_val_next() {
  if [[ -z "${2:-}" || "$2" == --* ]]; then
    error "option $1 requires a value"
    return 1
  fi
  printf %s "$2"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_help
      exit 0
      ;;
    --repo-dir)
      REPO_DIR="$(arg_val_next "$@")" || { print_help; exit 1; }
      shift 2
      ;;
    --repo-dir=*)
      REPO_DIR="${1#*=}"
      shift
      ;;
    --upstream-commit)
      UPSTREAM_COMMIT="$(arg_val_next "$@")" || { print_help; exit 1; }
      shift 2
      ;;
    --upstream-commit=*)
      UPSTREAM_COMMIT="${1#*=}"
      shift
      ;;
    --rocm-commit)
      ROCM_COMMIT="$(arg_val_next "$@")" || { print_help; exit 1; }
      shift 2
      ;;
    --rocm-commit=*)
      ROCM_COMMIT="${1#*=}"
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      echo >&2
      print_help
      echo >&2
      echo "Run with --help for full usage." >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  error "--repo-dir is required"
fi
if [[ -z "$UPSTREAM_COMMIT" ]]; then
  error "--upstream-commit is required"
fi
if (( REQ_ERR )); then
  print_help
  echo >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

LLVM_UPSTREAM_URL="${LLVM_UPSTREAM_URL:-https://github.com/llvm/llvm-project.git}"
ROCM_LLVM_URL="${ROCM_LLVM_URL:-https://github.com/ROCm/llvm-project.git}"
LLVM_SRC_DIR="${REPO_DIR}"
LLVM_UPSTREAM_REF="${UPSTREAM_COMMIT}"
ROCM_AMD_REF="${ROCM_COMMIT}"

git clone "$LLVM_UPSTREAM_URL" "$LLVM_SRC_DIR"
cd "$LLVM_SRC_DIR"
git checkout "$LLVM_UPSTREAM_REF"

git remote add rocm "$ROCM_LLVM_URL"
git fetch rocm "$ROCM_AMD_REF"
git checkout "$ROCM_AMD_REF" -- amd

# Absolute paths keep CMake happy regardless of caller cwd.
LLVM_SRC_DIR="$(pwd -P)"
DEVICE_LIBS_SRC_DIR="${LLVM_SRC_DIR}/amd/device-libs"

mkdir -p build
cd build

# Stage installs under build/install/
INSTALL_PREFIX="$(pwd -P)/install"

cmake -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_CCACHE_BUILD=ON \
  -DLLVM_USE_SPLIT_DWARF=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU;SPIRV" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_EXTERNAL_PROJECTS="device-libs" \
  -DLLVM_EXTERNAL_DEVICE_LIBS_SOURCE_DIR="$DEVICE_LIBS_SRC_DIR" \
  ../llvm

ninja install
