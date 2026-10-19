#!/system/bin/sh
set -eu

BASE=/data/local/tmp/houdini-nextgen
CREATED=$BASE/state/created.sha256
PHASE=$BASE/state/phase

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root shell required'
[ -f "$CREATED" ] || fail 'created-file journal missing'

while read -r expected relative; do
    [ -n "$expected" ] || continue
    case "$relative" in
        system/lib/libhoudini.so|system/bin/arm/linker|system/lib/arm/*) ;;
        *) fail "journal path rejected: $relative" ;;
    esac
    target="/$relative"
    [ -e "$target" ] || continue
    current="$(sha256sum "$target" | awk '{print $1}')"
    [ "$current" = "$expected" ] || fail "rollback drift: $relative"
done < "$CREATED"

mount -o remount,rw / || fail 'remount rw failed'
while read -r expected relative; do
    [ -n "$expected" ] || continue
    target="/$relative"
    [ ! -e "$target" ] || rm -f "$target"
done < "$CREATED"
find /system/lib/arm -depth -type d -empty -delete 2>/dev/null || true
rmdir /system/bin/arm 2>/dev/null || true
sync
mount -o remount,ro / || fail 'remount ro failed'
printf '%s\n' rolled_back > "$PHASE"
sync
echo rolled_back
