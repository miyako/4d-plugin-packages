//%attributes = {"invisible":true}
$path:=System folder:C487(Desktop:K41:16)

//NSFileManager displayNameAtPath:
$dname:=PATH Get display name($path)
//NSURL getResourceValue:forKey:NSURLLocalizedNameKey
$lname:=PATH Get localized name($path)

$path:=System folder:C487(Desktop:K41:16)+Generate UUID:C1066+".folder"
CREATE FOLDER:C475($path)
SHOW ON DISK:C922($path)

TRACE:C157
PATH SET HIDDEN($path; 1)
$hidden:=PATH Is hidden($path)
TRACE:C157
PATH SET HIDDEN($path; 0)
$hidden:=PATH Is hidden($path)
TRACE:C157
PATH SET EXTENSION HIDDEN($path; 1)
$hidden:=PATH Is extension hidden($path)
TRACE:C157
PATH SET EXTENSION HIDDEN($path; 0)
$hidden:=PATH Is extension hidden($path)