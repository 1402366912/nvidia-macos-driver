# One build-only FX505GT cohort

Status: fixed-input source recipe. The four actual AsusSMC C++ translation units
passed a Linux-hosted Mach-O object compile and exact local replay. The full
Xcode kext link and AppKit/CLI/radio native builds have **not** run: this workspace
has no Apple build host/SDK. Do not infer native or hardware qualification.

## Fixed source inputs

`build/inputs.json` pins:

| Input | Commit | Use |
|---|---|---|
| [AsusSMC](https://github.com/hieplpvip/AsusSMC/tree/c15d2f297c86b65a3cb866cc2bcece595c136417) | `c15d2f297c86b65a3cb866cc2bcece595c136417` | Four kext TUs and Xcode project |
| [Lilu](https://github.com/acidanthera/Lilu/tree/89af9d3df5c1bcd91ffb8905d56be61003cc8c84) | `89af9d3df5c1bcd91ffb8905d56be61003cc8c84` | Contemporary BSD-licensed headers |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC/tree/2db1cd9481679eaaaf861e26241987431ee49af5) | `2db1cd9481679eaaaf861e26241987431ee49af5` | Contemporary BSD-licensed VirtualSMCSDK headers |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK/tree/3f750085caa17ec3a7880f11c11bf4f48cd6a164) | `3f750085caa17ec3a7880f11c11bf4f48cd6a164` | Complete public kernel headers and tracked x86_64 libkmod build input |

The Lilu/VirtualSMC pins predate the AsusSMC commit by hours/days. Their used
interfaces compile in the recorded object check. That does not establish
compatibility of arbitrary modern runtime kext versions. Lilu/VirtualSMC runtime
binaries are neither built nor bundled by this recipe, and still require a
separately reviewed matching runtime environment.

Already available official Xcode/macOS SDK, Python 3, Git and ACPICA **20250404**
are required on a native build host. The recipe installs/downloads nothing and
does not invoke upstream bootstrap. Apple toolchain versions, SDKSettings hash
and iasl binary hash are recorded in the output receipt. They are not falsely
presented as tested or byte-reproducible across different Xcode releases.

## Clean native entry

Obtain four clean Git checkouts at the exact pins above, with directory names
`AsusSMC`, `Lilu`, `VirtualSMC`, `MacKernelSDK` beneath one input directory. Keep
this delivered component directory clean as well. Then the single build entry is:

```sh
python3 tools/build_cohort.py \
  --inputs /path/to/pinned-checkouts \
  --output /path/to/new-fx505gt-build \
  --iasl /path/to/existing/iasl
```

This command is documented for a future native build; it was not run on a Mac.
The optional `--prepare-only` mode verifies/exports source without compilers and
can run on a non-Apple host. Output must be new and outside both input trees and
this delivered component. Failures retain their logs and partial outputs.

The entry:

1. Verifies every delivered source hash, exact Git HEAD and clean source inputs.
   It exports selected content-addressed Git blobs rather than copying worktrees,
   ignored files, Git credentials/configuration, CI files or symlinks.
2. Stages the exact expanded AsusSMC overlay; checks its before/after hashes and
   shared ABI bytes. It verifies profile ABI 1, Fn ABI 3 and connection cohort
   `0x46583250` against the input manifest.
3. Stages SDK header source under the historical resource search paths. This is
   **not a runnable Lilu.kext/VirtualSMC.kext distribution**. Two unreferenced Lilu
   header symlinks (`capstone`, `hde64.h`) are omitted; none of the four target TUs
   includes them. No dependency bootstrap, plugin_start.cpp or wrapper build runs.
4. Hash-guards the original AsusSMC Xcode project and removes its daemon dependency,
   installer-copy edge and ZIP archive edge; the shell archive phase itself is
   removed. No upstream installer/archive shell phase runs. The four original
   source target entries remain intact. Prepared project SHA-256:
   `bb6a4c9f63e213d09e019712dbaac45a296b32345ae1bab3f1d6b95a17f1a897`.
5. Builds only the AsusSMC Release target for x86_64/macOS 10.15 minimum. Signing
   is disabled as a build option, without changing OS security settings.
6. Builds the x86_64 CLI, fixed-command fxradio companion and AppKit app together.
   Also builds the existing 华硕控制.app and AsusAwake via build_platform.sh;
   these are recorded in the same receipt, with no source behavior change.
   The app embeds exact CLI/radio binary hashes plus ABI/source identity. Do not
   mix it with an independently rebuilt or modified companion.
7. Compiles the default-off BIOS303 SSDT with fixed-version iasl and warnings as
   errors. It does not create or install a DSDT replacement. The actual ACPI
   deployment path remains the separately exact-hash-guarded binary definition
   rename plus this SSDT, not recompiling the known-error original DSDT DSL.
8. Records required kext, CLI, app, helper, plist, identity header and AML output
   hashes in `BUILD_RECEIPT.json`. Any failed stage stops the cohort and retains
   evidence. No output program/AML is executed, signed, installed or loaded.

The default-off flags remain unchanged. No build step enables a profile, registers
a login item/daemon, accepts permission prompts, changes radios/display power or
executes firmware methods. Helper placement, signing/distribution and a unified
hardware test require separate authorization and review.

## Actual bounded object check

`validation/kernel-object-compile.json` records all **392 used input files**, their
hashes/provenance, exact compiler identity and arguments, and four Mach-O objects:

- AsusSMC.cpp, including the real IOUserClient/gate/notification implementation
- KeyImplementations.cpp
- VirtualAppleKeyboard.cpp
- KernEventServer.cpp

All four final compiles exited 0 without diagnostics; combined objects are
119,336 bytes. Exact local replay produced the same four object SHA-256 values.
Objects stay local; this publication contains source and text evidence only.

The reused header closure is deliberately described separately from the clean
native recipe: original Apple XNU `f6217f891ac0bb64f3d375211650a4c1ff8ca1ea`,
MacKernelSDK supplements at the pin above, other per-file pinned Apple headers,
five inherited availability/target headers and fifteen inherited genuine Apple
MIG outputs. The inherited generated headers are SHA-pinned, not claimed to be
newly fetched original Git blobs. This is **not** a complete pure-MacKernelSDK
native build. Source interfaces compiled here do not prove final linkage or
runtime kernel ABI compatibility.

`tools/replay_kernel_objects.py` verifies the recorded compiler and used inputs
before compiling only those four objects. Supply `--roots` as a local JSON object
mapping these labels to existing absolute paths:

- `compiler`: the exact recorded clang binary
- `clang_resource`: that compiler's resource directory
- `source`: patched AsusSMC source root
- `lilu`: pinned Lilu source's `Lilu/` directory
- `vsmc`: pinned VirtualSMC source root
- `sdk_extra`, `sdk_shared_extra`, `sdk_delta`, `sdk_base`: the four existing
  header-root layers used in the evidence, in the recorded search order

```sh
python3 tools/replay_kernel_objects.py --roots /path/to/local-roots.json \
  --output /path/to/new-object-check
```

It does not download/reconstruct a missing header closure or substitute mocks.
Compiler shared-library configuration must already be available to the caller.
A different compiler requires a separately recorded new validation run; the exact
replay intentionally rejects it.

## Validation performed here

- Portable policy/ABI/parser suite: pass (`validation/portable-v4-tests.txt`).
- Verified Git export and exact-project transformation tests: pass
  (`validation/build-preparation-tests.txt`). These are focused tests, not a
  claim that all four complete source checkouts were exported end-to-end here.
- Actual four-TU Mach-O compile and identical replay: pass.
- Initial missing-header logs and a real include-order failure retained in
  `validation/kernel-object-initial-failures.txt`. Lilu's `PRIVATE` visibility
  macro collided with public IOUserClient preprocessor checks when included via
  KeyImplementations.cpp. The bridge now saves/undefines/restores that macro
  around the new SDK includes; no SDK/Lilu header was edited to hide the error.
- BIOS303 SSDT offline ACPICA validation: existing pass, unchanged source.
- Native Xcode final linkage, Objective-C++ app/helper builds, installation,
  permissions and physical Fn/fan/display/radio behavior: **pending**.

## Existing platform application dependency

This build entry creates the Fn app and its pinned profile/radio companions.
It now also builds the existing `local.asus.platform.ui` application and
AsusAwake. It deliberately does not provision a login item, privileged helper,
sudoers rule or any application. The field setup
already supplies those separately. F11 notification dispatch requires that
platform application running; see `platform/README.md` for its source build
and fixed helper paths. A new machine needs a separately authorized deployment,
not just this source build. The OSD adds no second sleep/lid owner.

After a source change, the delivery manifest must be regenerated from the
reviewed tracked component files before using this guarded entry. Do not
bypass hash checks or include generated caches/output in the source manifest.

See [DEPLOY_USERLAND.md](DEPLOY_USERLAND.md) for the verified userland packaging
entry and inert login templates. No native package has been produced on Linux.
