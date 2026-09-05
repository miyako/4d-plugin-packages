//%attributes = {"invisible":true}
$icon:=PATH Get icon(System folder:C487(Desktop:K41:16)+"1.txt"
SET PICTURE TO PASTEBOARD:C521($icon)

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

READ PICTURE FILE:C678(Get 4D folder:C485(Current resources folder:K5:16)+"sample.png"; $image)
ASSERT:C1129(0#Picture size:C356($image))

PATH SET ICON($path; $image)
$icon:=PATH Get icon($path)