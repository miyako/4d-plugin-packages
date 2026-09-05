# 4d-plugin-packages

The Packages plugin lets 4D read and set macOS Finder-level file attributes that aren't exposed by 4D's built-in language: whether a folder is a bona fide "package" (bundle), whether a file's extension or the file itself is hidden in Finder, its localized/display name, and its Finder icon. It's a thin wrapper around Cocoa's `NSURL` resource-value API (`NSURLIsPackageKey`, `NSURLHasHiddenExtensionKey`, `NSURLIsHiddenKey`, `NSURLLocalizedNameKey`), `NSWorkspace`, and `NSFileManager`. Commands return `Longint` (booleans, as 0/1), `Text`, or `Picture` (a TIFF-encoded icon image) — there are no object or collection results.

| Command | Returns | Purpose |
|---|---|---|
| [`PATH SET PACKAGE BIT`](#path-set-package-bit) | — | Mark/unmark a folder as a package (bundle) |
| [`PATH Get package bit`](#path-get-package-bit) | Longint | Read the package bit set by the command above |
| [`PATH Is package`](#path-is-package) | Longint | Ask Finder directly whether a path is a package |
| [`PATH SET EXTENSION HIDDEN`](#path-set-extension-hidden) | — | Hide/show a file's extension in Finder |
| [`PATH Is extension hidden`](#path-is-extension-hidden) | Longint | Check whether a file's extension is hidden |
| [`PATH Get localized name`](#path-get-localized-name) | Text | Get the localized display name of a file/folder |
| [`PATH SET HIDDEN`](#path-set-hidden) | — | Hide/show a file or folder in Finder |
| [`PATH Is hidden`](#path-is-hidden) | Longint | Check whether a file or folder is hidden |
| [`PATH SET ICON`](#path-set-icon) | — | Assign a custom icon to a file or folder |
| [`PATH Get icon`](#path-get-icon) | Picture | Get a file or folder's current Finder icon |
| [`PATH Get display name`](#path-get-display-name) | Text | Get the Finder display name of a file/folder |

**Platforms:** macOS only (Carbon and Cocoa). There is no Windows implementation in this source — the entire plugin is built on Cocoa APIs (`NSURL`, `NSWorkspace`, `NSFileManager`).

---

## Requirements & platform notes

- **Failure is always silent, never a 4D error.** None of these commands raise a 4D error for an invalid, nonexistent, or inaccessible path. Every `Get`/`Is` command simply returns its default value instead: `0` for a `Longint` result, an empty string for a `Text` result, and an empty `Picture` for `PATH Get icon`. Every `SET` command silently does nothing. Always check the returned value rather than expecting an exception or error dialog.
- **`PATH SET PACKAGE BIT` requires macOS 10.8 (Mountain Lion) or later.** The command checks `NSFoundationVersionNumber` at runtime; on an older system it's a silent no-op — nothing is set, and no error is raised. `PATH Get package bit`/`PATH Is package` have no such guard and work on any supported macOS version, but obviously won't reflect a bit that was never allowed to be set.
- **Boolean parameters are plain integers, not 4D booleans.** `flag` parameters on the `SET` commands take a `Longint`: `1`/nonzero to turn the attribute on, `0` to turn it off.
- **`path` is mandatory everywhere; there's no optional form.** Every command takes exactly the parameters shown below — no command can be called with a parameter omitted.
- **`PATH Get localized name` and `PATH Get display name` are not interchangeable**, even though they sound similar. They call two different Cocoa APIs (`NSURL`'s `NSURLLocalizedNameKey` resource value vs. `NSFileManager displayNameAtPath:`) and can diverge in edge cases — see each command's own notes below.

---

## PATH SET PACKAGE BIT

### Syntax
```4d
PATH SET PACKAGE BIT ( path ; flag )
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the folder to mark/unmark as a package |
| `flag` | Longint | `1` to set the package bit, `0` to clear it |
| Result | — | No return value |

### Description
Sets the folder's `NSURLIsPackageKey` resource value. This is the same bit `NSURL`'s `setResourceValue:forKey:` API exposes since macOS 10.8, and is a distinct mechanism from naming a folder with a recognized bundle extension (`.app`, `.bundle`, etc.). **On macOS 10.7 and earlier**, this command does nothing at all — the version check fails before any Cocoa call is made, and no error surfaces to 4D.

### Example
From the plugin's own README.md sample code:
```4d
$path:=System folder(Desktop)+Generate UUID
CREATE FOLDER($path)

  //NSURL getResourceValue:forKey:NSURLIsPackageKey
ASSERT(0=PATH Get package bit ($path))
  //NSWorkspace isFilePackageAtPath:
ASSERT(0=PATH Is package ($path))

  //set a folder as package; requires 10.8 or later
PATH SET PACKAGE BIT ($path;1)

ASSERT(1=PATH Get package bit ($path))
ASSERT(1=PATH Is package ($path))
```

From the plugin's own test method (`unit_tests2.4dm`), the same pattern with real command tags:
```4d
$path:=System folder:C487(Desktop:K41:16)+Generate UUID:C1066
CREATE FOLDER:C475($path)

//NSURL getResourceValue:forKey:NSURLIsPackageKey
ASSERT:C1129(0=PATH Get package bit($path))
//NSWorkspace isFilePackageAtPath:
ASSERT:C1129(0=PATH Is package($path))

//set a folder as package; requires 10.8 or later
PATH SET PACKAGE BIT($path; 1)

ASSERT:C1129(1=PATH Get package bit($path))
ASSERT:C1129(1=PATH Is package($path))
```

To clear the bit again:
```4d
PATH SET PACKAGE BIT($path; 0)
```

---

## PATH Get package bit

### Syntax
```4d
PATH Get package bit ( path ) → Longint
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the folder to check |
| Result | Longint | `1` if the package bit is set, `0` if it isn't (or the path is invalid) |

### Description
Reads back the `NSURLIsPackageKey` resource value set by [`PATH SET PACKAGE BIT`](#path-set-package-bit). If the path can't be resolved to a URL, or the resource value can't be read, the command returns `0` — the same as an explicitly-cleared bit. There's no way to distinguish "bit is off" from "path was invalid" from the return value alone.

### Example
```4d
If (PATH Get package bit($path)=1)
    ALERT("This folder is a package.")
End if 
```

---

## PATH Is package

### Syntax
```4d
PATH Is package ( path ) → Longint
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder to check |
| Result | Longint | `1` if Finder considers the path a package, `0` otherwise |

### Description
Asks `NSWorkspace isFilePackageAtPath:` directly, rather than reading the resource-value bit. This can say `1` for things [`PATH Get package bit`](#path-get-package-bit) would say `0` for — e.g. a folder with a recognized bundle extension like `.app` is a package to Finder even if the explicit package bit was never set. If the path is invalid, the command returns `0`.

### Example
From the plugin's own README.md sample code (same snippet as above — both commands are checked side by side before and after setting the bit):
```4d
ASSERT(0=PATH Is package ($path))
PATH SET PACKAGE BIT ($path;1)
ASSERT(1=PATH Is package ($path))
```

---

## PATH SET EXTENSION HIDDEN

### Syntax
```4d
PATH SET EXTENSION HIDDEN ( path ; flag )
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file to change |
| `flag` | Longint | `1` to hide the extension in Finder, `0` to show it |
| Result | — | No return value |

### Description
Sets `NSURLHasHiddenExtensionKey` on the file. Unlike [`PATH SET PACKAGE BIT`](#path-set-package-bit), there's no OS-version guard in the source — this runs on any supported macOS version.

### Example
From the plugin's own README.md sample code:
```4d
$path:=System folder(Desktop)+Generate UUID+".folder"
CREATE FOLDER($path)
SHOW ON DISK($path)

TRACE
PATH SET EXTENSION HIDDEN ($path;1)
$hidden:=PATH Is extension hidden ($path)
TRACE
PATH SET EXTENSION HIDDEN ($path;0)
$hidden:=PATH Is extension hidden ($path)
```

---

## PATH Is extension hidden

### Syntax
```4d
PATH Is extension hidden ( path ) → Longint
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file to check |
| Result | Longint | `1` if the extension is hidden, `0` if it isn't (or the path is invalid) |

### Description
Reads back `NSURLHasHiddenExtensionKey`. Returns `0` on an invalid path or unreadable attribute, same fallback pattern as the other `Is`/`Get` commands.

### Example
From the plugin's own test method (`unit_tests1.4dm`):
```4d
TRACE:C157
PATH SET EXTENSION HIDDEN($path; 1)
$hidden:=PATH Is extension hidden($path)
TRACE:C157
PATH SET EXTENSION HIDDEN($path; 0)
$hidden:=PATH Is extension hidden($path)
```

---

## PATH Get localized name

### Syntax
```4d
PATH Get localized name ( path ) → Text
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder |
| Result | Text | The localized name from `NSURL`'s resource-value API, or an empty string if unavailable |

### Description
Reads `NSURLLocalizedNameKey` via `NSURL getResourceValue:forKey:error:`. This honors macOS's per-folder localization (e.g. `.localized` files inside special folders), and is a different code path from [`PATH Get display name`](#path-get-display-name) below — for most ordinary files the two will agree, but don't assume they always will. Returns an empty string if the path can't be resolved.

### Example
From the plugin's own README.md sample code:
```4d
$path:=System folder(Desktop)
  //NSURL getResourceValue:forKey:NSURLLocalizedNameKey
$lname:=PATH Get localized name ($path)
```

---

## PATH SET HIDDEN

### Syntax
```4d
PATH SET HIDDEN ( path ; flag )
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder to change |
| `flag` | Longint | `1` to hide it from Finder, `0` to show it |
| Result | — | No return value |

### Description
Sets `NSURLIsHiddenKey` on the item. This is the Finder-level hidden flag (distinct from a dot-prefixed filename).

### Example
From the plugin's own test method (`unit_tests1.4dm`), including the `CREATE FOLDER`/`SHOW ON DISK` setup the test always does first:
```4d
$path:=System folder:C487(Desktop:K41:16)+Generate UUID:C1066+".folder"
CREATE FOLDER:C475($path)
SHOW ON DISK:C922($path)

TRACE:C157
PATH SET HIDDEN($path; 1)
$hidden:=PATH Is hidden($path)
TRACE:C157
PATH SET HIDDEN($path; 0)
$hidden:=PATH Is hidden($path)
```

---

## PATH Is hidden

### Syntax
```4d
PATH Is hidden ( path ) → Longint
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder to check |
| Result | Longint | `1` if hidden, `0` if not (or the path is invalid) |

### Description
Reads back `NSURLIsHiddenKey`. Same silent-`0`-on-failure behavior as the other `Is`/`Get` commands.

### Example
```4d
If (PATH Is hidden($path)=1)
    PATH SET HIDDEN($path; 0)  //reveal it
End if 
```

---

## PATH SET ICON

### Syntax
```4d
PATH SET ICON ( path ; picture )
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder to assign the icon to |
| `picture` | Picture | The image to use as the custom icon |
| Result | — | No return value |

### Description
Passes the picture straight to `NSWorkspace setIcon:forFile:options:`. If `path` doesn't resolve, the command does nothing — there's no feedback that the assignment failed.

### Example
From the plugin's own test method (`unit_tests2.4dm`):
```4d
READ PICTURE FILE:C678(Get 4D folder:C485(Current resources folder:K5:16)+"sample.png"; $image)
ASSERT:C1129(0#Picture size:C356($image))

PATH SET ICON($path; $image)
```

---

## PATH Get icon

### Syntax
```4d
PATH Get icon ( path ) → Picture
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder |
| Result | Picture | The item's current Finder icon, TIFF-encoded, rasterized at up to 1024×1024 |

### Description
Retrieves the icon via `NSWorkspace iconForFile:`, rasterizes it to a `CGImage`, and encodes it as TIFF data before wrapping it as a 4D `Picture` — this avoids the memory overhead of `NSImage`'s `-TIFFRepresentation`. If the path doesn't resolve, or the file has no representable icon, the command returns an **empty `Picture`** rather than raising an error; check `Picture size` on the result before using it.

### Example
From the plugin's own test method (`unit_tests2.4dm`):
```4d
$icon:=PATH Get icon(System folder:C487(Desktop:K41:16)+"1.txt")
SET PICTURE TO PASTEBOARD:C521($icon)
```

Guarding against the empty-icon case:
```4d
$icon:=PATH Get icon($path)
If (Picture size($icon)#0)
    SET PICTURE TO PASTEBOARD($icon)
Else 
    ALERT("No icon available for this item.")
End if 
```

---

## PATH Get display name

### Syntax
```4d
PATH Get display name ( path ) → Text
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | Full path to the file or folder |
| Result | Text | The Finder display name, or an empty string if unavailable |

### Description
Calls `NSFileManager displayNameAtPath:` — a different Cocoa API from [`PATH Get localized name`](#path-get-localized-name), which goes through `NSURL`'s resource-value API instead. In practice both usually return the same string for an ordinary file, but they're independent code paths and aren't guaranteed to agree in every edge case (e.g. how each handles a hidden extension). Returns an empty string if the path can't be resolved.

### Example
From the plugin's own README.md sample code:
```4d
$path:=System folder(Desktop)
  //NSFileManager displayNameAtPath:
$dname:=PATH Get display name ($path)
```

---

## Error handling & troubleshooting

- **Nothing here raises a 4D error.** An invalid path, a file that was deleted between checks, or a permissions problem all just produce the same default result a `SET` no-op or a `Get`/`Is` fallback value (`0`, `""`, or an empty `Picture`) would produce on success-but-empty. Always validate your `path` and check the returned value; don't wrap these calls in `ON ERR CALL`.
- **`PATH SET PACKAGE BIT` silently does nothing pre-10.8.** If a package bit you set doesn't seem to "take," confirm the target Mac is running macOS 10.8 or later before assuming a bug elsewhere.
- **`PATH Get icon` can return an empty `Picture`.** This happens for an invalid path or a file with no icon representation Cocoa can rasterize. Check `Picture size(...)#0` on the result before displaying or storing it.
- **`flag` parameters are `Longint`, not 4D's `Boolean` type.** Pass `1`/`0` (or any nonzero/zero `Longint` expression) — don't pass a `Boolean` variable directly without converting it.
- **`PATH Get localized name` and `PATH Get display name` can disagree.** If you need Finder's exact displayed string (the one a user actually sees), prefer `PATH Get display name`; use `PATH Get localized name` if you specifically want the `NSURL` resource-value API's answer.
- **New folders may need `SHOW ON DISK` before Finder-visibility commands are meaningful.** The plugin's own test files (`unit_tests1.4dm`) always call `CREATE FOLDER` followed by `SHOW ON DISK` before exercising `PATH SET HIDDEN`/`PATH SET EXTENSION HIDDEN` — follow the same order for newly created items.

---

## Quick reference

```4d
$path:=System folder(Desktop)+Generate UUID+".folder"
CREATE FOLDER($path)
SHOW ON DISK($path)

//package bit (10.8+)
PATH SET PACKAGE BIT($path; 1)
$isPackage:=PATH Get package bit($path)      //or: PATH Is package($path)

//visibility
PATH SET HIDDEN($path; 1)
$isHidden:=PATH Is hidden($path)
PATH SET EXTENSION HIDDEN($path; 1)
$extHidden:=PATH Is extension hidden($path)

//names
$displayName:=PATH Get display name($path)
$localizedName:=PATH Get localized name($path)

//icon
READ PICTURE FILE(Get 4D folder(Current resources folder)+"sample.png"; $image)
PATH SET ICON($path; $image)
$icon:=PATH Get icon($path)
If (Picture size($icon)#0)
    SET PICTURE TO PASTEBOARD($icon)
End if 
```
