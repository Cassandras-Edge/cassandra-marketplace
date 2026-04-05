#!/usr/bin/env bash
# acl-lint — Validates acl.yaml on write/edit operations.
#
# Runs as a PreToolUse hook on Write/Edit. Only fires when the target
# file is acl.yaml. Validates:
#   - Valid YAML syntax
#   - Known service names (not typos)
#   - Groups referenced by users actually exist
#   - Policy structure (groups.*.services.*.access must be allow/deny)

set -euo pipefail

HOOK_INPUT=$(cat)

# Extract the file path being written/edited
FILE_PATH=$(echo "$HOOK_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
params = data.get('tool_input', {})
print(params.get('file_path', params.get('path', '')))
" 2>/dev/null || echo "")

# Only validate acl.yaml files
case "$FILE_PATH" in
  *acl.yaml|*acl.yml) ;;
  *) exit 0 ;;
esac

# Get the content being written (for Write) or the file on disk (for Edit)
# For Edit, the file already exists — validate after the edit would apply
# For now, validate the file on disk if it exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Validate with Python
python3 -c "
import sys, yaml, json

KNOWN_SERVICES = {
    'yt-mcp', 'discord-mcp', 'market-research', 'twitter-mcp',
    'reddit-mcp', 'claudeai-mcp', 'gateway',
}

errors = []

try:
    with open('$FILE_PATH') as f:
        config = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(json.dumps({'decision': 'block', 'reason': f'acl.yaml has invalid YAML syntax: {e}'}))
    sys.exit(0)

if not isinstance(config, dict):
    print(json.dumps({'decision': 'block', 'reason': 'acl.yaml root must be a mapping'}))
    sys.exit(0)

# Check groups
groups = config.get('groups', {}) or {}
defined_groups = set(groups.keys())

for group_name, group_def in groups.items():
    if not isinstance(group_def, dict):
        errors.append(f'Group \"{group_name}\" must be a mapping')
        continue
    services = group_def.get('services', {}) or {}
    for svc_name, svc_def in services.items():
        if svc_name not in KNOWN_SERVICES and svc_name != '*':
            errors.append(f'Group \"{group_name}\" references unknown service \"{svc_name}\". Known: {sorted(KNOWN_SERVICES)}')
        if isinstance(svc_def, dict):
            access = svc_def.get('access')
            if access and access not in ('allow', 'deny'):
                errors.append(f'Group \"{group_name}\".services.\"{svc_name}\".access must be \"allow\" or \"deny\", got \"{access}\"')

# Check users reference valid groups
users = config.get('users', {}) or {}
for email, user_def in users.items():
    if not isinstance(user_def, dict):
        continue
    for grp in user_def.get('groups', []) or []:
        if grp not in defined_groups:
            errors.append(f'User \"{email}\" references undefined group \"{grp}\". Defined: {sorted(defined_groups)}')

if errors:
    msg = 'acl.yaml validation failed:\\n' + '\\n'.join(f'  - {e}' for e in errors)
    print(json.dumps({'decision': 'block', 'reason': msg}))
else:
    # Valid — allow the write
    pass
" 2>/dev/null || exit 0
