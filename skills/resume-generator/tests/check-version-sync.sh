#!/usr/bin/env bash
# check-version-sync.sh - assert that the two plugin manifests agree on the
# version, because `/plugin update` only re-fetches when the version changes.
#
#   .claude-plugin/plugin.json       -> .version
#   .claude-plugin/marketplace.json  -> .metadata.version
#
# Prints both versions. Exit codes:
#   0 = in sync
#   1 = mismatch
#   2 = a manifest is missing or its version could not be read
#
# Uses python3's json module when available, else a sed/awk fallback.

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

repo_root="$(cd "$(skill_root)/../.." && pwd)"
plugin_json="$repo_root/.claude-plugin/plugin.json"
market_json="$repo_root/.claude-plugin/marketplace.json"

status=0
for f in "$plugin_json" "$market_json"; do
  if [ ! -f "$f" ]; then
    echo "missing manifest: $f" >&2
    status=2
  fi
done
[ "$status" -eq 0 ] || exit "$status"

# json_version <file> <plugin|marketplace>
json_version() {
  local file="$1" mode="$2" v=""
  if have python3; then
    v="$(python3 - "$file" "$mode" <<'PY' 2>/dev/null
import json, sys
path, mode = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8-sig") as fh:
    data = json.load(fh)
if mode == "plugin":
    v = data.get("version")
else:
    v = (data.get("metadata") or {}).get("version")
print("" if v is None else v)
PY
)"
  fi
  if [ -z "$v" ]; then
    if [ "$mode" = "plugin" ]; then
      v="$(tr -d '\r' < "$file" \
        | sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
        | head -n 1)"
    else
      v="$(tr -d '\r' < "$file" | awk '
        /"metadata"[[:space:]]*:/ { inside = 1 }
        inside && /"version"[[:space:]]*:/ {
          sub(/^[^:]*:[[:space:]]*"/, "")
          sub(/".*$/, "")
          print
          exit
        }')"
    fi
  fi
  printf '%s\n' "$v"
}

pv="$(json_version "$plugin_json" plugin)"
mv="$(json_version "$market_json" marketplace)"

echo "plugin.json      .version          = ${pv:-<unreadable>}"
echo "marketplace.json .metadata.version = ${mv:-<unreadable>}"

if [ -z "$pv" ] || [ -z "$mv" ]; then
  echo "could not read a version field" >&2
  exit 2
fi

if [ "$pv" != "$mv" ]; then
  echo "VERSION MISMATCH: bump both manifests to the same version." >&2
  exit 1
fi

echo "versions in sync ($pv)"
exit 0
