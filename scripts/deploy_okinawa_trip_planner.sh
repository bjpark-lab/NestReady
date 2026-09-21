#!/usr/bin/env bash
# Publish only the public itinerary artifact. Never publish the NestReady repo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$REPO_DIR/okinawa-trip-planner.html"
GH_REPO="bjpark-lab/nestready-okinawa-trip"
GH_BRANCH="gh-pages"
GH_PATH="index.html"
PAGES_URL="https://bjpark-lab.github.io/nestready-okinawa-trip/"

if [ ! -f "$SOURCE_FILE" ]; then
  printf 'ERROR: source file not found: %s\n' "$SOURCE_FILE" >&2
  exit 1
fi

python3 - "$SOURCE_FILE" <<'PY'
import re
import sys
from pathlib import Path

content = Path(sys.argv[1]).read_text(encoding="utf-8")
patterns = {
    "card-number-like digit sequence": r"\b(?:\d{4}[ -]){3}\d{1,7}\b",
    "private-record path": r"records/private",
}
for label, pattern in patterns.items():
    if re.search(pattern, content):
        raise SystemExit(f"ERROR: public artifact contains {label}; deployment refused.")
print("Secret guard: no forbidden patterns found.")
PY

sha="$(gh api "repos/$GH_REPO/contents/$GH_PATH?ref=$GH_BRANCH" --jq '.sha')"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
python3 - "$SOURCE_FILE" "$sha" "$GH_BRANCH" "$payload" <<'PY'
import base64
import json
import sys
from pathlib import Path

source, sha, branch, payload = sys.argv[1:]
body = {
    "message": "chore: deploy Okinawa itinerary",
    "content": base64.b64encode(Path(source).read_bytes()).decode("ascii"),
    "sha": sha,
    "branch": branch,
}
Path(payload).write_text(json.dumps(body), encoding="utf-8")
PY

commit_sha="$(gh api "repos/$GH_REPO/contents/$GH_PATH" --method PUT --input "$payload" --jq '.commit.sha')"
printf 'Published Pages branch commit: %s\n' "$commit_sha"

if gh api "repos/$GH_REPO/contents/$GH_PATH?ref=$GH_BRANCH" --jq '.content' | tr -d '\n' | base64 -d | cmp -s "$SOURCE_FILE" -; then
  printf 'Verified: gh-pages index.html matches the local source.\n'
else
  printf 'ERROR: gh-pages index.html differs from the local source.\n' >&2
  exit 1
fi

printf 'Pages URL: %s\n' "$PAGES_URL"
