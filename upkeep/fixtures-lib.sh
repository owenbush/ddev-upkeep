#!/usr/bin/env bash
#ddev-generated
# Shared helpers for the upkeep fixture commands.
# Installed to .ddev/upkeep/fixtures-lib.sh by the upkeep add-on.
#
# Fixture model:
#   - A fixture is a named gzipped SQL dump: <name>.sql.gz. Dumps are the
#     portable source of truth.
#   - On first load, the dump is materialized into a fast-format snapshot
#     artifact (.ddev/upkeep/materialized/<name>.sql — uncompressed, streamed
#     straight into the DB server on restore). Subsequent loads restore that
#     artifact, which is much faster than a full `ddev import-db` of the dump.
#     (`ddev snapshot restore` was measured too: it needs a db-container
#     stop/start cycle costing ~25-30s regardless of DB size, so the streamed
#     artifact wins for fixture-sized databases.)
#   - A meta file (.ddev/upkeep/snapshots/<name>.meta) records the DB engine
#     identity and dump checksum at materialization time; the artifact is
#     rebuilt from the dump whenever either changes. Materialized artifacts
#     are disposable, engine-tied local caches — never authoritative.
#
# Resolution order (per-module first):
#   1. Module scope:  $DDEV_APPROOT/tests/fixtures/<name>.sql.gz
#      (active when the project root is a module checkout, i.e. a *.info.yml
#      file exists at the project root — the ddev-drupal-contrib layout)
#   2. Library scope: $UPKEEP_FIXTURE_LIBRARY, defaulting to
#      $UPKEEP_COCKPIT/fixtures, defaulting to $HOME/.upkeep/fixtures

set -eu -o pipefail

# Prefix used for any ddev-native snapshots the add-on has materialized
# (legacy; current materialization uses .ddev/upkeep/materialized/).
UPKEEP_SNAPSHOT_PREFIX="upkeep-fixture-"
UPKEEP_DEFAULT_SIZE_WARN_MB=5

# Overlay config from .ddev/.env.upkeep (ddev dotenv convention) without
# overriding variables already set in the caller's environment.
upkeep_load_env() {
  local env_file="${DDEV_APPROOT}/.ddev/.env.upkeep"
  [ -f "$env_file" ] || return 0
  local saved_library="${UPKEEP_FIXTURE_LIBRARY:-}"
  local saved_cockpit="${UPKEEP_COCKPIT:-}"
  local saved_warn="${UPKEEP_FIXTURE_SIZE_WARN_MB:-}"
  set -o allexport
  # shellcheck disable=SC1090
  . "$env_file"
  set +o allexport
  [ -n "$saved_library" ] && UPKEEP_FIXTURE_LIBRARY="$saved_library"
  [ -n "$saved_cockpit" ] && UPKEEP_COCKPIT="$saved_cockpit"
  [ -n "$saved_warn" ] && UPKEEP_FIXTURE_SIZE_WARN_MB="$saved_warn"
  return 0
}

upkeep_error() {
  echo "ERROR: $*" >&2
}

# Validate a fixture name: non-empty, filesystem-safe.
upkeep_require_name() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    upkeep_error "Missing fixture name. Usage: ddev ${UPKEEP_COMMAND_NAME:-fixture-<cmd>} <name>"
    exit 1
  fi
  case "$name" in
    *[!A-Za-z0-9._-]*)
      upkeep_error "Invalid fixture name '$name'. Use letters, digits, dot, dash, underscore."
      exit 1
      ;;
  esac
}

# Fail unless the ddev project is running (there is no site to dump/restore
# otherwise).
upkeep_require_running() {
  local status
  status="$(ddev describe -j 2>/dev/null | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"
  if [ "$status" != "running" ]; then
    upkeep_error "Project '${DDEV_PROJECT:-?}' is not running (status: ${status:-unknown}). Start it with 'ddev start'."
    exit 1
  fi
}

# Is the project root a module checkout (ddev-drupal-contrib layout)?
upkeep_is_module_checkout() {
  # shellcheck disable=SC2144
  [ -n "$(find "$DDEV_APPROOT" -maxdepth 1 -name '*.info.yml' -print -quit 2>/dev/null)" ]
}

upkeep_module_fixtures_dir() {
  echo "${DDEV_APPROOT}/tests/fixtures"
}

upkeep_library_dir() {
  if [ -n "${UPKEEP_FIXTURE_LIBRARY:-}" ]; then
    echo "$UPKEEP_FIXTURE_LIBRARY"
  elif [ -n "${UPKEEP_COCKPIT:-}" ]; then
    echo "${UPKEEP_COCKPIT}/fixtures"
  else
    echo "${HOME}/.upkeep/fixtures"
  fi
}

# Resolve a fixture dump, module scope first, then library scope.
# Prints "<scope>\t<path>" on success; returns 1 when not found.
upkeep_resolve_fixture() {
  local name="$1" candidate
  if upkeep_is_module_checkout; then
    candidate="$(upkeep_module_fixtures_dir)/${name}.sql.gz"
    if [ -f "$candidate" ]; then
      printf 'module\t%s\n' "$candidate"
      return 0
    fi
  fi
  candidate="$(upkeep_library_dir)/${name}.sql.gz"
  if [ -f "$candidate" ]; then
    printf 'library\t%s\n' "$candidate"
    return 0
  fi
  return 1
}

# Directory holding per-fixture materialization metadata.
upkeep_meta_dir() {
  echo "${DDEV_APPROOT}/.ddev/upkeep/snapshots"
}

upkeep_meta_file() {
  echo "$(upkeep_meta_dir)/$1.meta"
}

# Directory holding materialized snapshot artifacts (disposable caches).
upkeep_materialized_dir() {
  echo "${DDEV_APPROOT}/.ddev/upkeep/materialized"
}

upkeep_materialized_file() {
  echo "$(upkeep_materialized_dir)/$1.sql"
}

# Current DB engine identity, e.g. "mariadb:10.11".
upkeep_engine_id() {
  local json type version
  json="$(ddev describe -j 2>/dev/null)"
  type="$(printf '%s' "$json" | sed -n 's/.*"database_type":"\([^"]*\)".*/\1/p' | head -1)"
  version="$(printf '%s' "$json" | sed -n 's/.*"database_version":"\([^"]*\)".*/\1/p' | head -1)"
  echo "${type:-unknown}:${version:-unknown}"
}

upkeep_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

upkeep_file_size_bytes() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

upkeep_human_size() {
  local bytes="$1"
  if [ "$bytes" -ge 1048576 ]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f MB", b/1048576}'
  elif [ "$bytes" -ge 1024 ]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f KB", b/1024}'
  else
    echo "${bytes} B"
  fi
}

# Does fixture <name> have a materialized snapshot artifact on disk?
upkeep_snapshot_exists() {
  [ -f "$(upkeep_materialized_file "$1")" ]
}
