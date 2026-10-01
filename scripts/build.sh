#!/usr/bin/env bash
# Build image mega/compreface-postgres-db dari root repo ini (tanpa akses ke repo lain).
#
# Pemakaian:
#   scripts/build.sh [opsi]
#
# Opsi:
#   --version <ver>    tag image (default: isi file VERSION, mis. 1.2.0). 'latest' dilarang.
#   --no-cache         teruskan --no-cache ke docker build
#   --dry-run          tampilkan perintah tanpa menjalankan
#   -h | --help
#
# Env:
#   REGISTRY           prefix registry, mis. registry.example.internal  (kosong = lokal)
#   IMAGE_NAMESPACE    default: mega
#   DOCKER_BUILD_ARGS  argumen tambahan untuk docker build (mis. "--progress=plain")
#
# Output: daftar image yang dibangun ditulis ke build/images.txt (dipakai scripts/push.sh).
set -euo pipefail

SERVICE="compreface-postgres-db"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-mega}"
BUILD_ARGS_FILE="$ROOT/docker/build-args.env"
OUT_DIR="$ROOT/build"

VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
VARIANTS=()
NO_CACHE=""
DRY_RUN=false

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || die "--version butuh nilai"; VERSION="$2"; shift 2 ;;
    --variant) [[ -f "$BUILD_ARGS_FILE" ]] || die "--variant hanya untuk compreface-core"
               [[ $# -ge 2 ]] || die "--variant butuh nilai"; IFS=',' read -r -a v <<<"$2"; VARIANTS+=("${v[@]}"); shift 2 ;;
    --no-cache) NO_CACHE="--no-cache"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "argumen tidak dikenal: $1" ;;
  esac
done
[[ ${#VARIANTS[@]} -gt 0 ]] || VARIANTS=(default)

validate_version() {
  local v="$1"
  [[ "$v" != "latest" ]] || die "tag 'latest' dilarang — gunakan versi SemVer (mis. 1.2.0)"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "versi '$v' bukan SemVer (MAJOR.MINOR.PATCH[-suffix])"
}

image_ref() {
  local tag="$1" prefix=""
  [[ -n "$REGISTRY" ]] && prefix="${REGISTRY%/}/"
  echo "${prefix}${IMAGE_NAMESPACE}/${SERVICE}:${tag}"
}

# Baca satu varian dari docker/build-args.env → array global VARIANT_KV (KEY=VALUE)
load_variant() {
  local name="$1" section="" line found=false
  VARIANT_KV=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then section="${BASH_REMATCH[1]}"; continue; fi
    if [[ "$section" == "$name" ]]; then found=true; VARIANT_KV+=("$line"); fi
  done <"$BUILD_ARGS_FILE"
  $found || die "varian '$name' tidak ada di $BUILD_ARGS_FILE"
}

REVISION="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ "$REVISION" != "unknown" ]] && ! git -C "$ROOT" diff --quiet HEAD -- 2>/dev/null; then
  REVISION="${REVISION}-dirty"
fi
mkdir -p "$OUT_DIR"
BUILT=()

run() {
  echo "+ $*"
  $DRY_RUN || "$@"
}

build_one() {
  local tag="$1"; shift
  local ref; ref="$(image_ref "$tag")"
  validate_version "$tag"
  echo "==> build ${ref}"
  local start=$SECONDS
  # shellcheck disable=SC2086
  run env DOCKER_BUILDKIT=1 docker build $NO_CACHE ${DOCKER_BUILD_ARGS:-} \
    -f "$ROOT/Dockerfile" \
    --build-arg "VERSION=${tag}" \
    --build-arg "REVISION=${REVISION}" \
    "$@" \
    -t "$ref" "$ROOT"
  echo "==> selesai ${ref} ($((SECONDS - start)) s)"
  BUILT+=("$ref")
}

validate_version "$VERSION"
if [[ -f "$BUILD_ARGS_FILE" ]]; then
  for variant in "${VARIANTS[@]}"; do
    load_variant "$variant"
    args=(--build-arg "VARIANT=${variant}" --build-arg "BE_VERSION=${VERSION}" --build-arg "APP_VERSION_STRING=${VERSION}")
    suffix=""
    for kv in "${VARIANT_KV[@]}"; do
      key="${kv%%=*}"; val="${kv#*=}"
      case "$key" in
        TAG_SUFFIX) suffix="$val" ;;
        *) args+=(--build-arg "${key}=${val}") ;;
      esac
    done
    build_one "${VERSION}${suffix}" "${args[@]}"
  done
else
  build_one "$VERSION"
fi

if ! $DRY_RUN; then
  printf '%s\n' "${BUILT[@]}" >"$OUT_DIR/images.txt"
  echo
  echo "Image yang dibangun (ditulis ke build/images.txt):"
  for ref in "${BUILT[@]}"; do
    printf '  %-70s %s\n' "$ref" "$(docker image inspect -f '{{.Size}}' "$ref" | awk '{printf "%.0f MB", $1/1000/1000}')"
  done
fi
