#!/usr/bin/env bash
# Check that plugin versions in marketplace.json match individual plugin.json files.
# Also warns if plugin files changed but version wasn't bumped.
#
# Usage:
#   scripts/check-versions.sh          # standalone check
#   As a pre-commit hook (see install instructions below)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

MARKETPLACE=".claude-plugin/marketplace.json"
errors=0

# 1. Check version sync between marketplace.json and plugin.json
while IFS=$'\t' read -r name mp_ver; do
    plugin_json="plugins/${name}/.claude-plugin/plugin.json"
    if [[ ! -f "$plugin_json" ]]; then
        echo "ERROR: ${name} listed in marketplace.json but ${plugin_json} not found"
        errors=$((errors + 1))
        continue
    fi
    p_ver=$(python3 -c "import json; print(json.load(open('${plugin_json}'))['version'])")
    if [[ "$mp_ver" != "$p_ver" ]]; then
        echo "ERROR: ${name} version mismatch — marketplace.json=${mp_ver}, plugin.json=${p_ver}"
        errors=$((errors + 1))
    fi
done < <(python3 -c "
import json
with open('${MARKETPLACE}') as f:
    for p in json.load(f)['plugins']:
        print(f\"{p['name']}\t{p['version']}\")
")

# 2. If running in a git context, check if plugin files changed without a version bump
if git rev-parse HEAD >/dev/null 2>&1; then
    for plugin_dir in plugins/*/; do
        name=$(basename "$plugin_dir")
        plugin_json="${plugin_dir}.claude-plugin/plugin.json"
        [[ -f "$plugin_json" ]] || continue

        # Check if any non-version files in this plugin changed (staged)
        changed_files=$(git diff --cached --name-only -- "$plugin_dir" 2>/dev/null || true)
        [[ -z "$changed_files" ]] && continue

        # Check if plugin.json version actually changed
        version_changed=$(git diff --cached -- "$plugin_json" 2>/dev/null | grep -c '"version"' || true)
        if [[ "$version_changed" -eq 0 ]]; then
            echo "WARN: ${name} has staged changes but version was not bumped"
        fi
    done
fi

if [[ $errors -gt 0 ]]; then
    echo ""
    echo "${errors} version error(s) found. Fix before committing."
    exit 1
fi

echo "All plugin versions in sync."
