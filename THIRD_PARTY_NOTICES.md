# Third-party payload notice

This repository contains an opaque Intel Houdini binary payload copied from the
upstream project. Its SHA-256 identity can be verified, but its complete source,
vendor signature, software bill of materials, and per-component license
provenance are not available here. The repository-level MIT file does not, by
itself, establish rights or assurance for every binary under `system/`.

The next-gen workflow therefore:

- uses only the ARM32 application-translation subset;
- compares the checked-out payload byte-for-byte with the upstream release;
- records ELF metadata, dependencies, build IDs, and targeted strings review;
- was tested on a Genymotion Android 11 laboratory VM after a cold snapshot
  restore and boot recovery drill; and
- does not claim that hashing or inspection proves the binaries safe.

The original repository already distributes these binaries. This fork does
not claim to establish their separate redistribution rights or safety. Review
provenance and licensing before making further distributions, and keep runtime
use to controlled laboratory devices.
