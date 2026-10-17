# FX505GT userland delivery

This is a build-and-stage recipe, not an installer. A staged package requires
actual completed native compilation; source, Linux objects and shell scripts
are not substitutes for the two applications. No Apple SDK or ASUS assets are
included. Current source changes have not received native build/runtime QA.

## Build and package

Use the existing pinned-input command in BUILD_COHORT.md on an already prepared
Mac. It now builds the existing platform source as well as the Fn/OSD app,
matching helpers, kext and SSDT. Then run:

```
python3 tools/package_userland.py --build /path/to/completed-cohort --output /path/to/new-package
```

The packager verifies completed native receipt status, recorded output hashes,
linked x86_64 executable headers, bundle identities and the app's embedded
profile/radio helper hashes before staging anything. These are consistency
checks, not code signing, provenance authentication or hardware qualification.
It copies only selected outputs, the MIT license and deployment guidance;
there are no SDKs, kernel headers, third-party binaries or proprietary images.
PACKAGE_RECEIPT.json records staged file hashes. Preserve BUILD_RECEIPT.json
and the original build logs. Packaging does not execute any output.

## What must be present on the target

- /Applications/FX505GT Control.app: Fn listener and native OSD.
- /Applications/华硕控制.app: existing fan and independent sleep/lid UI,
  bundle ID local.asus.platform.ui. It owns the F11 sleep request.
- /Library/PrivilegedHelperTools/org.fx505gt.fxprofile: exact matching CLI.
- /Library/PrivilegedHelperTools/org.fx505gt.fxradio: exact matching radio helper.
- /Library/PrivilegedHelperTools/ASUSPlatform/AsusAwake: existing platform helper.

The helper files are ordinary non-setuid executables. Existing app checks
require the profile/radio helpers and their ancestors to meet their documented
ownership, permissions and ACL constraints; the field deployment uses
root:wheel 0755. Do not modify /Applications permissions to accommodate helpers.
Provisioning these paths and any sudo authorization is a separate reviewed
administrative deployment. No provision, chmod, sudoers or installation command
is executed by the build or packager. The old platform/sudoers.rule is a
site-specific historical reference and is deliberately not packaged. Do not
copy it blindly to another account. Platform actions require the reviewed
fixed-command authorization used by the existing deployment.

The already-tested matching AsusSMC ABI3/connection cohort, BIOS303 ACPI setup
and existing platform deployment remain prerequisites. This userland package
contains no kext/ACPI installer and cannot make an unconfigured machine ready.
Never replace the kernel component merely to preview an icon. Keep the tested
PR #1 cohort recoverable before a separately authorized deployment.

## Startup and first use

LaunchAgents-templates contains two inert per-user Aqua login templates. They
point to the exact app executable paths above; nothing loads or installs them.
A separately approved deployment may use them in the intended user's
~/Library/LaunchAgents. Preserve an existing matching startup item rather than
registering duplicate instances. The platform app's own “登录时打开” switch
manages local.asus.platform.ui; do not create a second platform login item.
Start both applications as the ordinary active console user, never root.

No template edits defaults or turns hardware actions on. The Fn app keeps the
existing HardwareFnEnabled and BluetoothCompanionEnabled preferences. On a
fresh account, explicitly enable Fn shortcuts in its menu after reviewing the
hardware prerequisites. Bluetooth control is independently opt-in. The OSD
switch alone does not authorize hardware actions. Custom volume, brightness
and keyboard-light overlays default off to avoid duplicate macOS HUDs.

F11 requires 华硕控制 to be running; otherwise the Fn app reports that dependency
and does not claim sleep occurred. Its two sleep/lid preferences remain
independent. No additional power policy or background daemon is introduced.

## Completion boundary

A successful package operation means native files were built and staged only.
Signing/notarization, approved installation, login behavior, helper trust checks,
Fn hardware outcomes and AppKit rendering still need the unified native trial.
Unknown fan mode, touchpad state and keyboard-light level remain honestly
unmeasured; a popup cannot make those hardware states measurable.
