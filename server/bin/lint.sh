#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
app_dir="$(dirname -- "$script_dir")"

find "$app_dir" -type f -name '*.php' -print0 |
  while IFS= read -r -d '' file; do
    php -l "$file"
  done

find "$app_dir/bin" -type f -name '*.sh' -print0 |
  while IFS= read -r -d '' file; do
    bash -n "$file"
  done

php -r '
  json_decode((string) file_get_contents($argv[1]), true, 64, JSON_THROW_ON_ERROR);
' "$app_dir/composer.json"
