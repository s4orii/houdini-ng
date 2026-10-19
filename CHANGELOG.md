# Changes from upstream

## Next-gen ARM32 lab workflow

- Replaced the manual `build.prop` append and drag-and-drop ZIP recipe with a
  PowerShell installer and fixed device-side scripts.
- Limited the first supported path to ARM32 app translation: 340 pinned files,
  120,276,446 bytes. The upstream payload includes ARM64 and direct ARM
  executable components that this workflow does not enable.
- Reused the known Genymotion Android 11 ABI initializer instead of writing
  duplicate read-only properties to two files.
- Added a deterministic SHA-256 manifest, device/API/init-script checks,
  collision detection, file mode and SELinux context handling, and post-boot
  verification.
- Added managed repeat-install detection, host/device state records, and a
  hash-guarded rollback path. A cold recovery point must be created and tested
  before installation.
- Documented the observed APK outcome: ARM-only packages now install with
  `primaryCpuAbi=armeabi-v7a`, while both tested React Native apps still fail
  during `libreactnative.so` resolution before showing a stable UI.

The binary payload remains third-party and opaque. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the limits of its review.
