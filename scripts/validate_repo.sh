#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

printf 'Checking Bash syntax...\n'
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' -print0)

printf 'Checking YAML syntax...\n'
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
for path in sorted([*root.rglob("*.yml"), *root.rglob("*.yaml")]):
    with path.open("r", encoding="utf-8") as handle:
        yaml.safe_load(handle)
    print(f"  OK {path.relative_to(root)}")
PY

printf 'Checking local Markdown links...\n'
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys
from urllib.parse import unquote

root = Path(sys.argv[1]).resolve()
pattern = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
errors = []

for md in root.rglob("*.md"):
    if "docs/history" in md.as_posix():
        continue
    text = md.read_text(encoding="utf-8", errors="replace")
    for raw in pattern.findall(text):
        target = raw.strip().split()[0].strip("<>")
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = unquote(target.split("#", 1)[0])
        if not target:
            continue
        resolved = (md.parent / target).resolve()
        try:
            resolved.relative_to(root)
        except ValueError:
            errors.append(f"{md.relative_to(root)}: link escapes repository: {raw}")
            continue
        if not resolved.exists():
            errors.append(f"{md.relative_to(root)}: missing target: {raw}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("  OK")
PY

printf 'Checking required examples...\n'
for path in \
  deploy/node/.env.example \
  deploy/vps/.env.example \
  scripts/.env.example \
  deploy/node/config/mariadb/50-server-node-a.cnf.example \
  deploy/node/config/mariadb/50-server-node-b.cnf.example; do
  [[ -f "$ROOT_DIR/$path" ]] || { echo "Missing $path" >&2; exit 1; }
done

printf 'Repository validation succeeded.\n'
