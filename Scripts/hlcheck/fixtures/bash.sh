#!/usr/bin/env bash
# deploy.sh — build, bundle and ship Atelier to a remote host.
# Usage: ./deploy.sh [-v] [--dry-run] <host> [tag]
set -euo pipefail
IFS=$'\n\t'

readonly VERSION="1.4.2"
declare -a HOSTS=(pi.local "core@build.sterlingcore.dev")
declare -i RETRIES=3
export DEPLOY_ENV=${DEPLOY_ENV:-qa}
local_tmp="${TMPDIR:-/tmp}/deploy.$$"
count=0
count+=1
PATH="$HOME/.local/bin:$PATH"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

function usage {
    cat <<EOF
Usage: ${0##*/} [-v] [--dry-run] <host> [tag]
  -v          verbose
  --dry-run   print commands, don't run
EOF
    exit 64
}

die() { echo "fatal: $1" 1>&2; return 1; }

verbose=false
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) verbose=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) usage ;;
        -*) die "unknown option: $1" ;;
        *) break ;;
    esac
done

host=${1:?host required}
tag=${2:-"v$VERSION"}
[ -z "$host" ] && usage
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "bad tag: $tag"
elif [[ "$host" == pi.local && "$DEPLOY_ENV" != "prod" ]]; then
    log "targeting $host with ${#HOSTS[@]} hosts, ${HOSTS[0]} first"
else
    log 'prod deploy'
fi

# Build once, retrying on flaky network.
for ((i = 1; i <= RETRIES; i++)); do
    if make bundle 2>&1 | tee "$local_tmp.log" >/dev/null; then
        break
    fi
    sleep $((i * 2))
done

until ssh -o ConnectTimeout=5 "$host" true 2>/dev/null; do
    log "waiting for $host..."
    sleep 1
done

for f in dist/*.tar.gz dist/**/*.plist; do
    [[ -f "$f" ]] || continue
    size=$(stat -f %z "$f")
    sum=`shasum -a 256 "$f" | cut -d' ' -f1`
    log "$f: $size bytes ($sum)"
    echo "$f" >> "$local_tmp.manifest"
done < <(ls)

select choice in yes no; do
    [[ $choice == yes ]] && break
    exit 130
done

if ! $dry_run; then
    rsync -avz --delete --exclude='.git' dist/ "$host:~/atelier/" \
        || die "rsync failed with $?"
    ssh "$host" bash -s -- "$tag" <<-'REMOTE'
	cd ~/atelier && ./install.sh "$1"
	REMOTE
    cd "$local_tmp" || exit 1
    source ./post-deploy.sh; . ~/.profile
fi

trap 'rm -rf "$local_tmp"; echo done >&2' EXIT SIGINT SIGTERM
diff <(sort a.txt) <(sort b.txt) &> /dev/null &
wait $!
unset local_tmp
echo "shipped $tag to $host as $USER (pid $$, args: $@, first: $1, status: $?)"
