#!/system/bin/sh
set -eu

BASE=/data/local/tmp/houdini-nextgen
MANIFEST=$BASE/payload-arm32.sha256
PHASE=$BASE/state/phase

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(getprop ro.build.version.sdk)" = 30 ] || fail 'unexpected API level'
[ "$(getprop ro.dalvik.vm.native.bridge)" = libhoudini.so ] || fail 'native bridge inactive'
case "$(getprop ro.product.cpu.abilist)" in *armeabi-v7a*) ;; *) fail 'ARMv7 ABI missing' ;; esac
case "$(mount | awk '$3=="/" {print $6}')" in *ro*) ;; *) fail 'root filesystem is not read-only' ;; esac
cd /
sha256sum -c "$MANIFEST"
[ "$(stat -c '%a' /system/bin/arm/linker)" = 755 ] || fail 'linker mode mismatch'
[ "$(stat -c '%a' /system/lib/libhoudini.so)" = 644 ] || fail 'bridge mode mismatch'
echo verified
