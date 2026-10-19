# Houdini NG

Instalador verificable de traducción ARM32 para laboratorios Genymotion Android 11.

This fork turns the original manual ZIP recipe into a repeatable ARM32
application-translation workflow for Genymotion Android 11 lab devices. It is
intended for authorized mobile testing, not production devices.

## Mejoras frente a la versión original

| Versión original | Esta versión |
| --- | --- |
| Pedía agregar propiedades con `tee -a` a dos archivos `build.prop`. Repetirlo podía duplicar claves. | Usa el servicio de inicio ABI que ya trae la imagen Genymotion comprobada. No modifica `build.prop`. |
| Instalación manual del ZIP completo, con ARM32 y ARM64. | Instala un conjunto ARM32 de 340 archivos fijados por SHA-256 (120.276.446 bytes). ARM64 queda fuera del alcance probado. |
| No verificaba identidad del dispositivo, hashes, modos ni resultado tras reiniciar. | Exige serial ADB explícito, Android 11/API 30, `vbox86p` y hashes conocidos del inicializador; comprueba archivos y bridge tras el reinicio. |
| No definía una repetición segura ni recuperación. | Registra archivos creados, rechaza colisiones, admite una segunda ejecución sin cambios y ofrece rollback que se detiene si detecta drift. |
| No distinguía un ABI anunciado de una aplicación funcional. | Prueba instalación y arranque por separado; documenta la falla real de React Native observada con los dos APK de prueba. |

El flujo instala `libhoudini.so`, el linker ARM32 y sus bibliotecas invitadas.
No instala `/system/bin/houdini`, así que no habilita ejecución directa de
binarios ARM mediante binfmt. Ajusta permisos, aplica `restorecon`, sincroniza
y devuelve `/` a solo lectura antes de reiniciar.

## Safety boundary

The Houdini payload is opaque third-party binary code. Hashes establish identity,
not safety. Create and test a recovery point before writing `/system`. The
tested machine used a cold VirtualBox snapshot because the Genymotion license
did not permit cloning. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Supported target: Genymotion Desktop Android 11/API 30 `vbox86p`, with the known
`init.genymotion.abi.sh` shipped by the tested image. ARM64 is deliberately out
of scope.

## Build and test

```powershell
./tools/New-Arm32Manifest.ps1
./tests/run.ps1
```

The manifest must be regenerated whenever the selected payload changes.

## Install on a recovered lab device

Stop the VM and create a cold recovery snapshot or a disposable clone. Boot-test
the recovery path and record the VM UUID and snapshot UUID before installing.
On the tested machine, the cold snapshot was restored and booted successfully
before the first `/system` write. Use the device's actual ADB serial:

```powershell
./Install-Houdini.ps1 -Serial 192.168.192.123:5555 -Action Inspect
./Install-Houdini.ps1 -Serial 192.168.192.123:5555 -Action Install
./Install-Houdini.ps1 -Serial 192.168.192.123:5555 -Action Verify
```

`Install` builds a local tar from the selected paths, validates local hashes,
stages fixed scripts and data via ADB, installs, reboots, and verifies the bridge.
A repeated install is accepted only when the device-side ownership journal is
present; a matching foreign/manual installation is reported as unmanaged and is
not adopted automatically.

Expected post-boot properties include:

```text
ro.product.cpu.abilist=x86_64,x86,armeabi-v7a,armeabi
ro.dalvik.vm.native.bridge=libhoudini.so
ro.dalvik.vm.isa.arm=x86
```

## Rollback

For a healthy VM, warm rollback is available:

```powershell
./Install-Houdini.ps1 -Serial 192.168.192.123:5555 -Action Rollback
```

Rollback stops on any file drift. It never deletes broad directory trees.
If the VM does not boot, stop it and restore the recorded cold snapshot in
VirtualBox. A tested example is:

```powershell
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' snapshot `
  '<vm-uuid>' restore '<snapshot-uuid>'
```

Replace the placeholders with the UUIDs recorded on your machine. Restoring
a snapshot discards changes made to that VM afterward.

## Limitations

- ARM32 translation does not guarantee that an app will pass emulator/root or
  anti-tamper checks, render correctly, or avoid vendor-specific native failures.
- SELinux is permissive in the tested Genymotion image; contexts are restored and
  inspected, but this does not prove behavior under enforcing policy.
- Play Store compatibility and ARM64 translation are not supported by this
  workflow.
- The two tested APKs installed as ARMv7, but both crashed in React Native
  SoLoader while resolving `libreactnative.so`; a working UI was not achieved.

Upstream source: <https://github.com/niizam/Genymotion_A11_libhoudini>
