#!/bin/bash
set -euo pipefail
preview_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$preview_dir/../../.." && pwd)"
preview_port="${PREVIEW_PORT:-13715}"
preview_session="tsutsuura-preview-export"
preview_cli="${PREVIEW_PLAYWRIGHT_CLI:-/Users/takamimarsh/.codex/skills/playwright/scripts/playwright_cli.sh}"
command -v npx >/dev/null
command -v python3 >/dev/null
cd "$project_dir"
mkdir -p output/playwright/tsutsuura-previews "$preview_dir/exports"
python3 -m http.server "$preview_port" --bind 127.0.0.1 > /tmp/tsutsuura-preview-export-http.log 2>&1 &
preview_server_pid=$!
cleanup() {
  "$preview_cli" -s="$preview_session" close >/dev/null 2>&1 || true
  kill "$preview_server_pid" 2>/dev/null || true
}
trap cleanup EXIT
for attempt in {1..30}; do
  if curl -sf --max-time 2 "http://127.0.0.1:$preview_port/release/app-store/previews-layout/" >/dev/null; then break; fi
  sleep 0.1
done
"$preview_cli" -s="$preview_session" open "http://127.0.0.1:$preview_port/release/app-store/previews-layout/?page=1"
"$preview_cli" -s="$preview_session" resize 1320 2868
for preview_page in 1 2 3 4; do
  case "$preview_page" in
    1) preview_name=store-01-family ;;
    2) preview_name=store-02-answer ;;
    3) preview_name=store-03-history ;;
    4) preview_name=store-04-personal-mark ;;
  esac
  "$preview_cli" -s="$preview_session" goto "http://127.0.0.1:$preview_port/release/app-store/previews-layout/?page=$preview_page"
  "$preview_cli" -s="$preview_session" run-code 'async (page) => { await page.waitForFunction(() => document.documentElement.dataset.ready === "true"); await page.evaluate(() => document.fonts.ready); }'
  "$preview_cli" -s="$preview_session" screenshot --filename="output/playwright/tsutsuura-previews/$preview_name.png"
  cp "output/playwright/tsutsuura-previews/$preview_name.png" "$preview_dir/exports/$preview_name.png"
done
"$preview_cli" -s="$preview_session" goto "http://127.0.0.1:$preview_port/release/app-store/previews-layout/"
"$preview_cli" -s="$preview_session" resize 1600 1000
"$preview_cli" -s="$preview_session" run-code 'async (page) => { await page.waitForFunction(() => document.documentElement.dataset.ready === "true"); await page.evaluate(() => document.fonts.ready); }'
"$preview_cli" -s="$preview_session" screenshot --filename=output/playwright/tsutsuura-previews/gallery.png
cp output/playwright/tsutsuura-previews/gallery.png "$preview_dir/exports/gallery.png"
node "$preview_dir/verify.mjs"
