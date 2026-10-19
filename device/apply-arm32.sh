#!/system/bin/sh
set -eu

BASE=/data/local/tmp/houdini-nextgen
ARCHIVE=$BASE/payload-arm32.tar
MANIFEST=$BASE/payload-arm32.sha256
STAGE=$BASE/stage
STATE=$BASE/state
CREATED=$STATE/created.sha256
CREATED_NEW=$STATE/created.new.sha256
PHASE=$STATE/phase

fail() { echo "ERROR: $*" >&2; exit 1; }
set_phase() { printf '%s\n' "$1" > "$PHASE"; sync; }
mount_ro() { mount -o remount,ro / >/dev/null 2>&1 || true; }
trap mount_ro EXIT HUP INT TERM

[ "$(id -u)" = 0 ] || fail 'root shell required'
[ -f "$ARCHIVE" ] && [ -f "$MANIFEST" ] || fail 'staging files missing'
mkdir -p "$STATE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xf "$ARCHIVE" -C "$STAGE"

set_phase validating
: > "$CREATED_NEW"
while read -r expected relative; do
    [ -n "$expected" ] || continue
    case "$relative" in
        system/lib/libhoudini.so|system/bin/arm/linker|system/lib/arm/*) ;;
        *) fail "manifest path rejected: $relative" ;;
    esac
    case "$relative" in *..*) fail "traversal rejected: $relative" ;; esac
    source_file="$STAGE/$relative"
    [ -f "$source_file" ] || fail "staged file missing: $relative"
    actual="$(sha256sum "$source_file" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || fail "staged hash mismatch: $relative"
    target="/$relative"
    if [ -e "$target" ]; then
        current="$(sha256sum "$target" | awk '{print $1}')"
        [ "$current" = "$expected" ] || fail "unmanaged collision: $relative"
    else
        printf '%s  %s\n' "$expected" "$relative" >> "$CREATED_NEW"
    fi
done < "$MANIFEST"

if [ ! -s "$CREATED_NEW" ]; then
    rm -f "$CREATED_NEW"
    [ -s "$CREATED" ] || fail 'compliant files are not owned by this run'
    set_phase already_compliant_managed
    echo already_compliant_managed
    exit 0
fi

mv "$CREATED_NEW" "$CREATED"

set_phase applying
mount -o remount,rw / || fail 'remount rw failed'
while read -r expected relative; do
    [ -n "$expected" ] || continue
    source_file="$STAGE/$relative"
    target="/$relative"
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
    chown 0:0 "$target"
    case "$relative" in system/bin/arm/linker) chmod 0755 "$target" ;; *) chmod 0644 "$target" ;; esac
    restorecon "$target" >/dev/null 2>&1 || fail "restorecon failed: $relative"
    current="$(sha256sum "$target" | awk '{print $1}')"
    [ "$current" = "$expected" ] || fail "installed hash mismatch: $relative"
done < "$MANIFEST"
sync
mount -o remount,ro / || fail 'remount ro failed'
trap - EXIT HUP INT TERM
set_phase verify_pending
echo installed_reboot_required
