# 4d-plugin-packages
Miscellaneous function for OS X, useful for managing packages.

More specifically, you can define a folder as a package, give it a custom icon and hide its extension.

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|||

### Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" />

Commands
---

```
PATH SET PACKAGE BIT
PATH Get package bit
PATH Is package
PATH SET EXTENSION HIDDEN
PATH Is extension hidden
PATH Get localized name
PATH SET HIDDEN
PATH Is hidden
PATH SET ICON
PATH Get icon
PATH Get display name
```

* packages

```
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

READ PICTURE FILE(Get 4D folder(Current resources folder)+"sample.png";$image)
ASSERT(0#Picture size($image))

PATH SET ICON ($path;$image)
$icon:=PATH Get icon ($path)
```

* visibility

```
$path:=System folder(Desktop)

  //NSFileManager displayNameAtPath:
$dname:=PATH Get display name ($path)
  //NSURL getResourceValue:forKey:NSURLLocalizedNameKey
$lname:=PATH Get localized name ($path)

$path:=System folder(Desktop)+Generate UUID+".folder"
CREATE FOLDER($path)
SHOW ON DISK($path)

TRACE
PATH SET HIDDEN ($path;1)
$hidden:=PATH Is hidden ($path)
TRACE
PATH SET HIDDEN ($path;0)
$hidden:=PATH Is hidden ($path)
TRACE
PATH SET EXTENSION HIDDEN ($path;1)
$hidden:=PATH Is extension hidden ($path)
TRACE
PATH SET EXTENSION HIDDEN ($path;0)
$hidden:=PATH Is extension hidden ($path)
```

Discussion
---

Read about [bundles and packages](https://developer.apple.com/library/ios/documentation/CoreFoundation/Conceptual/CFBundles/AboutBundles/AboutBundles.html). 

There are several ways to define a folder as a package:

1. Give it a specific [extension](https://developer.apple.com/library/ios/documentation/CoreFoundation/Conceptual/CFBundles/AboutBundles/AboutBundles.html): .app, .bundle, .framework, .plugin, .kext

2. Set the [bundle bit](https://developer.apple.com/library/ios/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html); the plugin command PATH SET PACKAGE BIT does this (10.8 or later).

3. Add a [pkginfo](https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPRuntimeConfig/Articles/ConfigApplications.html) file.

4. Create an app that registers an extension as a bundle type in its [Info.plist](https://developer.apple.com/library/ios/documentation/FileManagement/Conceptual/understanding_utis/understand_utis_declare/understand_utis_declare.html).

