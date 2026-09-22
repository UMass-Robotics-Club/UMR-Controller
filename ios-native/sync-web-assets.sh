#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
web_dir="$script_dir/UMRRemote/Web"

cp "$root_dir/index.html" "$web_dir/index.html"
cp "$root_dir/styles.css" "$web_dir/styles.css"
cp "$root_dir/app.js" "$web_dir/app.js"

echo "Synced web assets into $web_dir"
