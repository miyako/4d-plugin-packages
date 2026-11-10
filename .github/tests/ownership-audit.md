# Packages native ownership audit

## Provenance and scope

Baseline: `2d891eb47b29b75a37a2e1b422cdbd3bf77f0ca5`.
Guidance read through the immutable GitHub contents API:
`miyako/skills/4d-skills/skills/4dplugin/SKILL.md` at
`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9`.
The bundled implementation labels itself v14, the API header v13; neither
label establishes an upstream SDK release identity.

These exact Git blobs remain unchanged and are pinned by the test runner:

| Bundled file under `4D Plugin API/` | Git blob |
|---|---|
| `4DPluginAPI.c` | `bdb2e7894e66d5abf3ebfedb41aa4e47739e2fc6` |
| `4DPluginAPI.h` | `9054b45ffc7ff6f5b8d57529a3788a55d977b314` |
| `EntryPoints.h` | `730f2f77ff2713fb2fe4b7d6562baeedf5f664cb` |
| `Flags.h` | `fdd2757c25d9a2f95c23614a003d61669feb8638` |
| `PrivateTypes.h` | `77053dc0c0a3718d2d3b6f158371a6af78c6ae66` |
| `PublicTypes.h` | `2bb392e73e9c556c274fe0a75b3a6b83e310b77c` |
| `4DPluginAPI.def` | `996ecc4ab11ad165de9192eba2e7478db141c757` |

Inventory was established with `git ls-files`, reading the implementation and
interfaces, Xcode Sources/Headers/Frameworks/CopyFiles/Resources/Rez phases,
Visual Studio compile entries and filters, prefix header, SDK export definition,
both manifests and both existing workflow/script paths. Search absence alone
was not treated as proof of safety.

## Complete production native inventory

Both `Packages.xcodeproj/project.pbxproj` and `Packages.vcxproj` list all
18 production translation units: `4DPlugin.cpp`, `4DPluginAPI.c`, and the
16 wrappers below. All corresponding `.h` interfaces are tracked and included
in the audit; `C_TYPES.h` defines byte/UTF-16 strings and package parameter
aliases. There are no additional tracked native implementation copies or
uncompiled translation units. Several methods below are dormant relative to
the current dispatcher, but are still compiled, audited and tested.

| Files under `4D Plugin API/Classes/` (`.cpp` and `.h`) | Ownership findings / disposition |
|---|---|
| `ARRAY_TEXT` | Copies borrowed parameter buffers to C++ strings before any array mutation. Creates a distinct owned string for each outgoing slot, including slot 0; accepted SDK insertions transfer it. No immediate post-transfer disposal defect. Repeated replacement, churn, shrink, clear and Undefined destination covered. Allocation/resize OOM remains deferred below. |
| `C_TEXT` | Copies input borrowed buffers, stores independent UTF-16 code units, writes outputs/returns with the content setter rather than shallow scalar assignment. macOS/Windows converters use explicit returned unit counts for this wrapper. Cocoa copy helpers return owned objects (empty literal fallbacks are immortal). Scalar return and input mutation controls covered. |
| `C_PICTURE` / internal `CPicture` | Fixed path double cleanup, initialized-empty string/picture overwrite leaks, creation reference leak in `setBytes`, and UTF-16 converter bytes-as-units overread. Scoped command arguments each own their references; command outputs are retained before argument destruction. Successful command return owners are cleared separately. Error is checked before inspecting/adopting/clearing an unspecified returned command value. See metadata limitation below. |
| `C_POINTER` | `getVariable` acquired an owning `PA_GetPointerValue` result without clearing it. Now checks error before inspecting the result, copies its existing reference metadata, then clears the successful owner. Failed poisoned outputs are not read or cleared. Existing metadata interpretation is preserved, not redesigned. |
| `C_BLOB` / internal `CBytes` | Owns byte vectors/handles, not PA_Unistring allocations. Hex/Base64 helpers route text through `C_TEXT`; no shallow text transfer. No ownership changes. Dormant generic byte-vector and allocation edge behavior is not certified by these text/picture tests. |
| `ARRAY_BOOLEAN`, `ARRAY_INTEGER`, `ARRAY_LONGINT`, `ARRAY_REAL`, `ARRAY_DATE`, `ARRAY_TIME` | C++ value vectors, primitive/date SDK element setters, no string owners or text callbacks. Shared array allocation/resize constraints apply. No changes. |
| `C_INTEGER`, `C_LONGINT`, `C_REAL`, `C_DATE`, `C_TIME` | Primitive/date parameter and return copies; no string/picture owners. No changes. |

Other native surfaces: `4DPlugin.h` declares all 11 dispatch handlers;
`4D Plugin_Prefix.pch` imports Carbon; `4DPluginAPI.def` exports only
`FourDPackex`. SDK entry points store the host callback before calling
`PluginMain`; SDK engine/ABI files are not rewritten. Project membership,
manifests, prebuilt Mac/Windows binaries, resource exports and database files
are unchanged. The SDK has no object/collection variable kinds or property/
collection getter interfaces, and plugin sources have no such calls: object/
collection balances are zero by structural absence in this exact ABI, not a
test of modern 4D object/collection semantics.

## Command and manifest surfaces

Root `manifest.json` and the bundled resource manifest have identical 11
scalar-only signatures. There are no manifest array parameters. All commands
use a borrowed input text path copied by `C_TEXT` before native use.

| Selector | Manifest syntax | Other ownership surface |
|---|---|---|
| 1 | `PATH SET PACKAGE BIT(&T;&L)` | URL resource mutation |
| 2 | `PATH Get package bit(&T):L` | Borrowed NSNumber property result |
| 3 | `PATH Is package(&T):L` | Workspace query |
| 4 | `PATH SET EXTENSION HIDDEN(&T;&L)` | URL resource mutation |
| 5 | `PATH Is extension hidden(&T):L` | Borrowed NSNumber property result |
| 6 | `PATH Get localized name(&T):T` | Borrowed NSString property copied to wrapper; content-setter return |
| 7 | `PATH SET HIDDEN(&T;&L)` | URL resource mutation |
| 8 | `PATH Is hidden(&T):L` | Borrowed NSNumber property result |
| 9 | `PATH SET ICON(&T;&P)` | Borrowed picture input retained by wrapper, native image released after synchronous use |
| 10 | `PATH Get icon(&T):P` | Fixed overwrite leak: release the initialized empty picture before installing the successful creation owner |
| 11 | `PATH Get display name(&T):T` | Borrowed NSString copied to wrapper; content-setter return |

Cocoa `getResourceValue` is not a 4D owning object/property getter.
Only successful property output is inspected. Native temporary URLs/paths,
destination data/dictionaries and copied images retain their existing cleanup.
There are no plugin method-callback registrations. Dormant picture helpers
invoke synchronous 4D commands; their independently owned arguments can and
must be cleaned after completion. A command return is a separate owner.

## Contracts from this bundled SDK

- `PA_CreateVariable(eVK_Unistring/Picture)` creates an initial empty owner.
  `PA_SetStringVariable` and `PA_SetPictureVariable` shallow-assign and do not
  release previous contents. Use a string content setter or an Undefined
  destination when explicitly transferring an owned value.
- `PA_SetStringInArray` (`4DPluginAPI.c:4444`) accepts only Unicode arrays,
  non-null data, `0 <= index <= fNbElements`, non-null descriptor. It disposes
  the old slot then shallow-transfers the input allocation. Rejected calls do
  not transfer; slot 0 is accepted. `PA_GetStringInArray` is a borrowed alias.
  No post-transfer disposal or shared element allocation is introduced.
- `PA_SetUnistring`, used by `C_TEXT` output and return, delegates a UTF-16
  content update to the engine; it is not the array/scalar shallow setter.
  The shim models independent copying and replacement of the prior owner.
- `PA_GetPictureVariable` explicitly returns a borrowed picture;
  `PA_DuplicatePicture(p, 1)` retains it. `PA_SetPictureVariable` does not
  retain. Picture command output is retained before clearing owning arguments.
  Borrowed input pictures passed to cleanup-owning arguments are retained first.
- `PA_ConvertCharsetToCharset` (`:4776`) explicitly returns bytes used.
  `CPicture::createCopy` must divide by `sizeof(PA_Unichar)` before constructing
  a UTF-16 string. Capacity is bytes including space for a terminator; the
  returned byte count excludes the terminator in the tested engine contract.
- `PA_GetPointerValue` is owning (API header explicitly requires
  `PA_ClearVariable`). Check `PA_GetLastError` before examining its output.
- `PA_ExecuteCommandByID` (`:5257`) returns raw zero-initialized kind 0 if
  parameter-handle allocation fails. SDK kind normalization maps raw 0 to a
  string, so kind inspection cannot determine whether it is safe to clear.
  Check error first. The fixed helper throws a descriptive C++ exception;
  scoped arguments are released during unwinding. Success alone permits
  cleanup of the separately returned owner. No error is converted into an
  apparently successful empty picture or zero size by this helper.

## Isolated regression procedure

Run on macOS:

```sh
python3 .github/tests/test_ownership.py -v
```

The runner compiles all 18 actual translation units and the complete unchanged
SDK, pinned above, with Clang C++14 ASan/UBSan. Alignment instrumentation alone
is excluded for this legacy packed SDK ABI. LeakSanitizer is disabled on macOS;
explicit string allocations, picture retain counts and handle maps must
all end at zero in every successful subprocess. Objects/collections are
absent from this SDK, as noted above.

The forced-include `ownership_platform.h` first loads system declarations,
then redirects URL/workspace/file-manager/image class references and URL/image
destination functions before compiling production code. Stubs return only
synthetic objects and bytes. `nm -u` rejects linkage to the real corresponding
classes/functions and process-launch functions. The engine callback rejects
every unexpected engine selector. No filesystem resource query/mutation,
workspace query/mutation, real image decoding, 4D command or process launch
is executed. CoreFoundation memory allocation and string conversion remain
real, in-memory operations. The native-picture test deliberately passes an
opaque retained CFData sentinel only through the synthetic image constructor;
no real CGImage function consumes it.

Fixtures are exact ASCII, BMP `U+65E5`, supplementary `U+1F600` (two UTF-16
code units), and empty strings, with allocated-empty and null-empty engines.
Tests check length/content/terminator/capacity, array borrowed-copy independence,
replacement/churn/shrink/clear, rejected kind/index/data/descriptor predicates,
retained picture output lifetime, temporary creation-owner release, synchronous
command argument/return independence, poisoned command/pointer failure outputs,
command-handle failure and all 11 dispatcher selectors. Icon branches include
missing URL, missing icon, missing raster image and missing destination.

The exact same final harness must also be run against baseline sources:

```sh
mkdir -p "$ARTIFACTS/packages-baseline-2d891eb"
git archive 2d891eb47b29b75a37a2e1b422cdbd3bf77f0ca5 \
  -- '4D Plugin API' 4DPlugin.cpp 4DPlugin.h |
  tar -x -C "$ARTIFACTS/packages-baseline-2d891eb"
OWNERSHIP_SOURCE_ROOT="$ARTIFACTS/packages-baseline-2d891eb" \
  python3 .github/tests/test_ownership.py -v
```

The harness design was adapted from immutable
`miyako/4d-plugin-jpegoptim` commit
`e49adcd32bd5500cf3de680faa3649b32463ff5e`,
`.github/tests/ownership_host.mm` and `test_ownership.py`, retrieved through
the contents API. SDK hashes, dispatcher and platform redirection are specific
to Packages; results from that repository are not reused.

### Observed local results

macOS 26.7 (25G229), arm64, Apple Clang 21.0.0
(`clang-2100.1.1.101`): 15 named unittest groups, 89 leaf subprocess cases
on each source tree, with the same final harness and SDK hashes.

| Final harness group | Baseline passing / failing leaves | Fixed passing / failing leaves |
|---|---|---|
| Array transfer/copy/churn/shrink/clear/rejection | 2 / 0 | 2 / 0 |
| Command-handle and command-body failure for path/copy/gray/size/thumbnail | 0 / 10 | 10 / 0 |
| Copy byte/unit boundary (`.png`, BMP, supplementary) | 0 / 3 | 3 / 0 |
| Copy initialized-empty owners | 0 / 1 | 1 / 0 |
| All 11 dispatcher selectors | 10 / 1 | 11 / 0 |
| Icon success and five failure modes | 3 / 3 | 6 / 0 |
| Dispatcher exact string fixtures / missing URL / property failure | 33 / 0 | 33 / 0 |
| Grayscale initialized-empty owner | 0 / 1 | 1 / 0 |
| Path fixtures, both empty representations | 0 / 8 | 8 / 0 |
| Pointer owning result and poisoned failure | 0 / 2 | 2 / 0 |
| Scalar independent borrowed copies / content-setter returns | 8 / 0 | 8 / 0 |
| SDK raw-kind0 / physical-resize-failure characterization | 1 / 0 | 1 / 0 |
| `setBytes` temporary creation owner | 0 / 1 | 1 / 0 |
| Size input / initialized-empty owner | 0 / 1 | 1 / 0 |
| Thumbnail input / owning output | 0 / 1 | 1 / 0 |
| **Total** | **57 / 32** | **89 / 0** |

Baseline `.png` copy fails with an ASan heap-buffer-overflow while constructing
the UTF-16 string with a byte count. BMP/supplementary copy cases fail the
separate leaked-string-owner check. Path cases fail duplicate/unowned string
disposal (the null-empty/empty path can instead expose a picture over-retain).
Icon successful rasterization exposes the overwritten initial picture.
Pointer success exposes the unbalanced string owner; poisoned failure exposes
the missing error boundary. Command failures are rejected by double-disposal
or the explicit failure-surfacing assertion. The remaining picture helpers
fail owner balance or independently retained return assertions. All 57
baseline controls remain passing after the fix; all fixed subprocesses finish
with zero tracked owners/references/handles.

## Boundaries and concrete deferrals

- SDK initial string/array allocation failures have no reliable checked
  failure-preserving boundary in these existing void wrappers. SDK string
  creation does not update `sErrorCode`. A speculative empty-success fallback
  or global SDK rewrite is not a fix.
- The harness explicitly fails `PA_SetHandleSize` and proves
  `PA_ResizeArray` advances logical count to 7 while physical storage remains
  one slot. It restores only its local test descriptor before cleanup and
  never executes unsafe wrapper insertion afterward. Success tests do not
  certify resize OOM. Resolving this requires a separately designed checked
  wrapper contract; no SDK/ABI change is made.
- `PA_GetPictureData` metadata ownership is not stated by this SDK's comments
  or forwarding implementation. `_GetCount`/`loadImageOfType` successful
  metadata cleanup is therefore deferred, not guessed. The shim uses a
  poisoned failed metadata result and verifies that failure output is not
  inspected or disposed; it does not certify successful metadata lifetime.
- Generic wrapper copyability, pointer reference-metadata interpretation,
  dormant byte-wrapper bounds, host allocation failure of picture/native
  objects, and complete macOS image/error handling are not redesigned here.
  The fixed initial-empty picture overwrite is verified on successful creation.
- No Windows build or actual 4D host execution was performed. These results
  are synthetic ownership/length regressions, not Windows/4D certification.
- Existing `PluginMain` catch-all behavior is unchanged; dormant wrapper C++
  callers receive the new descriptive failures. Production dispatcher resource
  failures retain their existing behavior.

## Build and CI safety

Existing `release.yml` and `bump-version.yml` are manual-only. The former
builds, signs, notarizes, packages and publishes; neither is dispatched or
modified. Xcode's scheme selects Deployment for launch/profile/archive and
writes bundles beneath the tracked `Packages.4dbase/Plugins`; it also includes
copy/resource phases. No Xcode/Visual Studio project build is used.
No tracked database, user-preference or bundled binary is opened/executed.

New `ownership.yml` has read-only contents permission, a macos-latest unsigned
test job, relevant paths only, PR events and push events limited to `master`
and the exact audit branch `miyako-packages-ownership-audit`. It performs no
signing, notarization, install, packaging, releases, tags, uploads or dispatches.
