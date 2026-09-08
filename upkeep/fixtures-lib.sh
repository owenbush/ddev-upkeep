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
    upkeep_error "Missing fixture name. Usage: ddev ${UPKEEP_COMMAND_NAME:-upkeep-fixture-<cmd>} <name>"
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

# ---------------------------------------------------------------- manifests
#
# A dump is not a self-contained artifact. It encodes references to code —
# enabled extensions, plugin IDs inside config entities, field types, schema
# versions — and captures none of it. Loaded into a codebase that does not
# provide that code, Drupal cannot build its container, and the failure
# surfaces during whatever checks come next: late, and blaming the module
# under test rather than the fixture.
#
# So each dump gets a sidecar recording what it needs. It is generated, never
# hand-written: the create command already has the database open and the
# project's composer.json in front of it. A fixture with no sidecar behaves
# exactly as fixtures did before they existed.
#
# The dump stays a plain gzipped dump, so `gunzip -c <name>.sql.gz` and import
# it with anything is still true — the sidecar is additive.

# The sidecar beside a dump: <name>.sql.gz -> <name>.yml
upkeep_manifest_path() {
  echo "${1%.sql.gz}.yml"
}

# Machine name of the module this project is a checkout of, if it is one.
upkeep_module_name() {
  local info
  info="$(find "$DDEV_APPROOT" -maxdepth 1 -name '*.info.yml' -print -quit 2>/dev/null)" || return 1
  [ -n "$info" ] || return 1
  info="${info##*/}"
  echo "${info%.info.yml}"
}

# Extensions enabled in the current database, one per line.
#
# Read from config rather than `pm:list`, whose flags and output shape have
# moved between drush majors; `core.extension` is the same in every version
# that has existed. Silent failure is deliberate — a site that cannot answer
# gives a manifest without an extension list rather than no manifest at all.
upkeep_enabled_extensions() {
  local kind
  for kind in module theme; do
    { ddev drush config:get core.extension "$kind" --format=json 2>/dev/null || true; } \
      | grep -oE '"[a-z0-9_]+":' | tr -d '":' || true
  done | sort -u
}

# Packages the project requires beyond core, drush and the module under test.
#
# Read from the project's own composer.json on the host: it is a
# composer-written file, one requirement per line, so the block is parseable
# without a container round trip. Prints "package<TAB>constraint".
upkeep_project_requirements() {
  local composer_json="${DDEV_APPROOT}/composer.json" module
  [ -f "$composer_json" ] || return 0
  module="$(upkeep_module_name 2>/dev/null || true)"

  awk '
    /^[[:space:]]*"require"[[:space:]]*:[[:space:]]*\{/ { inreq = 1; next }
    inreq && /^[[:space:]]*\}/                          { inreq = 0 }
    inreq && match($0, /"[^"]+"[[:space:]]*:[[:space:]]*"[^"]+"/) {
      line = substr($0, RSTART, RLENGTH)
      split(line, parts, /"/)
      printf "%s\t%s\n", parts[2], parts[4]
    }
  ' "$composer_json" | while IFS="$(printf '\t')" read -r package constraint; do
    case "$package" in
      drupal/core|drupal/core-*|php|ext-*|composer/*|drush/drush) continue ;;
    esac
    if [ -n "$module" ] && [ "$package" = "drupal/${module}" ]; then
      continue
    fi
    printf '%s\t%s\n' "$package" "$constraint"
  done
}

# Is a package already required by this project?
upkeep_package_installed() {
  local lock="${DDEV_APPROOT}/composer.lock"
  [ -f "$lock" ] || return 1
  grep -q "\"name\": \"$1\"," "$lock"
}

# Is an extension present anywhere in the codebase?
#
# -L because the module under test is a symlink into its working copy, and its
# own submodules live behind that link.
upkeep_extension_present() {
  [ -n "$(find -L "${DDEV_APPROOT}/web" -maxdepth 5 -name "${1}.info.yml" -print -quit 2>/dev/null)" ]
}

# Write the sidecar for a dump that has just been created.
upkeep_write_manifest() {
  local manifest="$1" core_version core_major extensions requirements
  # `|| true` inside every substitution, not around the assignment: these run
  # under `set -e`, an assignment carries its substitution's exit status, and
  # a project without drush — a fixture captured before Drupal is installed,
  # or any non-Drupal project — must produce a smaller manifest rather than
  # kill the command that has just written a good dump.
  core_version="$(ddev drush status --field=drupal-version 2>/dev/null | tr -d '[:space:]' || true)"
  core_major="${core_version%%.*}"
  extensions="$(upkeep_enabled_extensions || true)"
  requirements="$(upkeep_project_requirements || true)"

  {
    echo "# Generated by 'ddev upkeep-fixture-create'. Describes what the dump"
    echo "# beside this file needs in order to mean anything. Commit both."
    if [ -n "$core_major" ]; then
      echo "core: '${core_major}'"
      echo "core_version: '${core_version}'"
    fi
    echo "db_engine: '$(upkeep_engine_id)'"
    echo "created_at: '$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    if [ -n "$requirements" ]; then
      echo "require:"
      printf '%s\n' "$requirements" | while IFS="$(printf '\t')" read -r package constraint; do
        [ -n "$package" ] && echo "  ${package}: '${constraint}'"
      done
    fi
    if [ -n "$extensions" ]; then
      echo "extensions:"
      printf '%s\n' "$extensions" | while read -r extension; do
        [ -n "$extension" ] && echo "  - ${extension}"
      done
    fi
  } > "$manifest"
}

# Read a top-level scalar out of a sidecar.
upkeep_manifest_scalar() {
  sed -n "s/^$2: *'\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$1" | head -1
}

# Read the "require:" map out of a sidecar as "package<TAB>constraint".
upkeep_manifest_requirements() {
  awk '
    /^require:/     { inreq = 1; next }
    /^[a-z_]+:/     { inreq = 0 }
    inreq && match($0, /^[[:space:]]+[^:]+:[[:space:]]*/) {
      key = $0
      sub(/^[[:space:]]+/, "", key)
      sub(/:.*/, "", key)
      value = $0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/'"'"'/, "", value)
      printf "%s\t%s\n", key, value
    }
  ' "$1"
}

# Read the "extensions:" list out of a sidecar.
upkeep_manifest_extensions() {
  awk '
    /^extensions:/ { inext = 1; next }
    /^[a-z_]+:/    { inext = 0 }
    inext && /^[[:space:]]*- / {
      line = $0
      sub(/^[[:space:]]*- /, "", line)
      print line
    }
  ' "$1"
}

# Make the codebase able to hold this fixture, or refuse before touching the
# database.
#
# Order matters: install what is declared and missing, and only then look for
# extensions, because installing a package is what puts most of them there.
# A refusal happens before the import, so a fixture that cannot work leaves
# the database exactly as it was rather than half-replaced.
upkeep_satisfy_manifest() {
  local manifest="$1" name="$2"
  [ -f "$manifest" ] || return 0

  local want_core
  want_core="$(upkeep_manifest_scalar "$manifest" core)"
  if [ -n "$want_core" ]; then
    local have_core
    have_core="$(ddev drush status --field=drupal-version 2>/dev/null | tr -d '[:space:]' || true)"
    have_core="${have_core%%.*}"
    if [ -n "$have_core" ] && [ "$want_core" != "$have_core" ]; then
      upkeep_error "Fixture '${name}' was captured on Drupal ${want_core} and this site is Drupal ${have_core}. Loading it would import a database built against different core schemas. Capture a fixture per core version, or load this one in a Drupal ${want_core} environment."
      exit 1
    fi
  fi

  local missing=""
  while IFS="$(printf '\t')" read -r package constraint; do
    [ -n "$package" ] || continue
    if ! upkeep_package_installed "$package"; then
      missing="${missing} ${package}:${constraint}"
    fi
  done <<EOF
$(upkeep_manifest_requirements "$manifest")
EOF

  if [ -n "$missing" ]; then
    echo "Fixture '${name}' needs packages this project does not have:${missing}"
    echo "Installing them ..."
    # shellcheck disable=SC2086
    if ! ddev composer require --no-interaction $missing; then
      upkeep_error "Could not install what fixture '${name}' requires:${missing}. Install them yourself, or re-create the fixture in an environment that matches this one."
      exit 1
    fi
  fi

  local absent=""
  while read -r extension; do
    [ -n "$extension" ] || continue
    upkeep_extension_present "$extension" || absent="${absent} ${extension}"
  done <<EOF
$(upkeep_manifest_extensions "$manifest")
EOF

  if [ -n "$absent" ]; then
    upkeep_error "Fixture '${name}' has extensions enabled that are not in this codebase:${absent}. Drupal cannot build a container for a database naming code that is not there, so the import is refused rather than left to fail later. If these come from a package, add it to the fixture's manifest ($(basename "$manifest")); if they are custom, add them to the project by hand."
    exit 1
  fi
}
