#!/usr/bin/env bash
set -euo pipefail

# Required explicit values. No host, account, or SSH identity is inferred.
: "${DEPLOY_HOST:?Set DEPLOY_HOST}"
: "${DEPLOY_USER:?Set DEPLOY_USER}"
: "${DEPLOY_APP_PATH:?Set DEPLOY_APP_PATH to a private directory outside public_html}"
: "${DEPLOY_PUBLIC_PATH:?Set DEPLOY_PUBLIC_PATH to the public API directory}"
: "${DEPLOY_DOMAIN_ROOT:?Set DEPLOY_DOMAIN_ROOT to the public domain document root}"
: "${DEPLOY_PUBLIC_URL:?Set DEPLOY_PUBLIC_URL to the public HTTPS API base URL}"
: "${SSH_IDENTITY_FILE:?Set SSH_IDENTITY_FILE to the key you explicitly want to use}"
: "${REMOTE_PHP:?Set REMOTE_PHP to the PHP 8.2+ CLI executable}"
: "${RUN_MIGRATIONS:?Set RUN_MIGRATIONS=1 to acknowledge the required migration}"
: "${QUIESCENCE_ACKNOWLEDGED:?Set QUIESCENCE_ACKNOWLEDGED=1 after pausing HTTP writes and workers}"
: "${DEPLOY_QUIESCENCE_TOKEN:?Set the one-time token written to storage/deploy-quiesced}"

deploy_port="${DEPLOY_PORT:-22}"
remote_php="$REMOTE_PHP"
run_migrations="$RUN_MIGRATIONS"
quiescence_acknowledged="$QUIESCENCE_ACKNOWLEDGED"
quiescence_token="$DEPLOY_QUIESCENCE_TOKEN"
public_parent="${DEPLOY_PUBLIC_PATH%/*}"
well_known_path="$DEPLOY_DOMAIN_ROOT/.well-known"
public_url="${DEPLOY_PUBLIC_URL%/}"
release_id="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}-$$"
release_path="$DEPLOY_APP_PATH/releases/$release_id"
quiescence_claim="$DEPLOY_APP_PATH/storage/deploy-quiesced.$release_id.claimed"

[[ "$DEPLOY_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid DEPLOY_HOST" >&2; exit 2; }
[[ "$DEPLOY_USER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid DEPLOY_USER" >&2; exit 2; }
[[ "$deploy_port" =~ ^[0-9]{1,5}$ ]] || { echo "Invalid DEPLOY_PORT" >&2; exit 2; }
[[ "$DEPLOY_APP_PATH" =~ ^/[A-Za-z0-9_./-]+$ ]] || { echo "Invalid DEPLOY_APP_PATH" >&2; exit 2; }
[[ "$DEPLOY_PUBLIC_PATH" =~ ^/[A-Za-z0-9_./-]+$ ]] || { echo "Invalid DEPLOY_PUBLIC_PATH" >&2; exit 2; }
[[ "$DEPLOY_DOMAIN_ROOT" =~ ^/[A-Za-z0-9_./-]+$ ]] || { echo "Invalid DEPLOY_DOMAIN_ROOT" >&2; exit 2; }
[[ "$public_parent" =~ ^/[A-Za-z0-9_./-]+$ ]] || { echo "Invalid public parent path" >&2; exit 2; }
[[ "$DEPLOY_APP_PATH" != "/" && "$DEPLOY_APP_PATH" != *"/../"* && "$DEPLOY_APP_PATH" != */.. ]] ||
  { echo "DEPLOY_APP_PATH is too broad or contains traversal" >&2; exit 2; }
[[ "$DEPLOY_PUBLIC_PATH" != "/" && "$DEPLOY_PUBLIC_PATH" != *"/../"* && "$DEPLOY_PUBLIC_PATH" != */.. ]] ||
  { echo "DEPLOY_PUBLIC_PATH is too broad or contains traversal" >&2; exit 2; }
[[ "$DEPLOY_DOMAIN_ROOT" != "/" && "$DEPLOY_DOMAIN_ROOT" != *"/../"* && "$DEPLOY_DOMAIN_ROOT" != */.. ]] ||
  { echo "DEPLOY_DOMAIN_ROOT is too broad or contains traversal" >&2; exit 2; }
[[ "$DEPLOY_APP_PATH" != */public_html && "$DEPLOY_APP_PATH" != *"/public_html/"* ]] ||
  { echo "DEPLOY_APP_PATH must stay outside public_html" >&2; exit 2; }
[[ "$DEPLOY_PUBLIC_PATH/" == "$DEPLOY_DOMAIN_ROOT/"* ]] ||
  { echo "DEPLOY_PUBLIC_PATH must be inside DEPLOY_DOMAIN_ROOT" >&2; exit 2; }
[[ "$public_url" =~ ^https://([A-Za-z0-9.-]+)(/.*)?$ ]] ||
  { echo "DEPLOY_PUBLIC_URL must be an HTTPS URL without credentials" >&2; exit 2; }
public_origin="https://${BASH_REMATCH[1]}"
[[ "$SSH_IDENTITY_FILE" =~ ^/[A-Za-z0-9_./-]+$ && -r "$SSH_IDENTITY_FILE" ]] ||
  { echo "SSH_IDENTITY_FILE must be an explicit readable absolute path" >&2; exit 2; }
[[ "$remote_php" =~ ^[A-Za-z0-9_./-]+$ ]] || { echo "Invalid REMOTE_PHP" >&2; exit 2; }
[[ "$run_migrations" == "1" ]] ||
  { echo "RUN_MIGRATIONS must be 1 for this schema-dependent release" >&2; exit 2; }
[[ "$quiescence_acknowledged" == "1" ]] ||
  { echo "QUIESCENCE_ACKNOWLEDGED must be 1" >&2; exit 2; }
[[ "$quiescence_token" =~ ^[A-Za-z0-9._-]{16,128}$ ]] ||
  { echo "DEPLOY_QUIESCENCE_TOKEN must be 16-128 safe ASCII characters" >&2; exit 2; }

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
app_dir="$(dirname -- "$script_dir")"
remote="${DEPLOY_USER}@${DEPLOY_HOST}"
ssh_command="ssh -p ${deploy_port} -i ${SSH_IDENTITY_FILE} -o IdentitiesOnly=yes -o BatchMode=yes"

"$script_dir/lint.sh"

ssh -p "$deploy_port" -i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes -o BatchMode=yes "$remote" \
  "set -eu &&
   test -x '$remote_php' &&
   test -f '$DEPLOY_APP_PATH/.env' &&
   { test ! -e '$DEPLOY_APP_PATH/current' || test -L '$DEPLOY_APP_PATH/current'; } &&
   test -f '$DEPLOY_APP_PATH/storage/deploy-quiesced' &&
   mv '$DEPLOY_APP_PATH/storage/deploy-quiesced' '$quiescence_claim' &&
   test \"\$(cat '$quiescence_claim')\" = '$quiescence_token' &&
   test \"\$(find '$quiescence_claim' -mmin -15 -print)\" = '$quiescence_claim' &&
   '$remote_php' -r '
     foreach ([\"curl\", \"fileinfo\", \"intl\", \"json\", \"mbstring\", \"openssl\", \"PDO\"] as \$extension) {
       if (!extension_loaded(\$extension)) {
         fwrite(STDERR, \"Missing PHP extension: {\$extension}\\n\");
         exit(1);
       }
     }
     if (!extension_loaded(\"pdo_sqlite\") && !extension_loaded(\"pdo_mysql\")) {
       fwrite(STDERR, \"Missing PDO database driver\\n\");
       exit(1);
     }
   ' &&
   umask 077 &&
   mkdir -p '$DEPLOY_APP_PATH/storage' '$DEPLOY_APP_PATH/storage/answer-media' '$DEPLOY_APP_PATH/releases' '$release_path' '$DEPLOY_PUBLIC_PATH' '$well_known_path' &&
   ln -s '$DEPLOY_APP_PATH/.env' '$release_path/.env' &&
   ln -s '$DEPLOY_APP_PATH/storage' '$release_path/storage' &&
   chmod 755 '$DEPLOY_DOMAIN_ROOT' '$public_parent' '$DEPLOY_PUBLIC_PATH' '$well_known_path'"

rsync -az --checksum \
  -e "$ssh_command" \
  --exclude '.env' \
  --exclude 'public/' \
  --exclude 'storage/' \
  "$app_dir/" "$remote:$release_path/"

ssh -p "$deploy_port" -i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes -o BatchMode=yes "$remote" \
  "cd '$release_path' && '$remote_php' bin/migrate.php --seed"

rsync -az --checksum \
  -e "$ssh_command" \
  "$app_dir/public/" "$remote:$DEPLOY_PUBLIC_PATH/"

rsync -az --checksum \
  -e "$ssh_command" \
  "$app_dir/deployment/apple-app-site-association" \
  "$remote:$well_known_path/apple-app-site-association"

rsync -az --checksum \
  -e "$ssh_command" \
  "$app_dir/deployment/well-known.htaccess" \
  "$remote:$well_known_path/.htaccess"

ssh -p "$deploy_port" -i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes -o BatchMode=yes "$remote" \
  "umask 077 &&
   ln -s '$release_path' '$DEPLOY_APP_PATH/.current-$release_id' &&
   mv -Tf '$DEPLOY_APP_PATH/.current-$release_id' '$DEPLOY_APP_PATH/current' &&
   printf '%s\n' '$DEPLOY_APP_PATH/current' > '$DEPLOY_PUBLIC_PATH/.app-root' &&
   chmod 700 '$DEPLOY_APP_PATH/storage' '$DEPLOY_APP_PATH/storage/answer-media' &&
   chmod 644 '$well_known_path/apple-app-site-association' '$well_known_path/.htaccess'"

curl --fail --silent --show-error "$public_url/v1/health" >/dev/null
curl --fail --silent --show-error \
  "$public_origin/.well-known/apple-app-site-association" >/dev/null

ssh -p "$deploy_port" -i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes -o BatchMode=yes "$remote" \
  "rm '$quiescence_claim'"

echo "Deployment is healthy. Public API: $public_url"
echo "Activated private release: $release_path"
echo "Associated domains file: $public_origin/.well-known/apple-app-site-association"
