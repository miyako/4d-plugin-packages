# 4d-plugin-packages
Miscellaneous function for OS X, useful for managing packages 

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
