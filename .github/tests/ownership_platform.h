#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>

// Loaded after system declarations, before any production translation unit.
@interface OwnershipURL : NSObject
- (id)initWithString:(NSString *)value;
- (NSString *)absoluteString;
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error;
- (BOOL)setResourceValue:(id)value forKey:(NSString *)key error:(NSError **)error;
@end
@interface OwnershipImage : NSObject
- (id)initWithCGImage:(CGImageRef)image size:(NSSize)size;
- (CGImageRef)CGImageForProposedRect:(NSRect *)rect context:(id)context hints:(id)hints;
- (NSData *)TIFFRepresentation;
@end
@interface OwnershipWorkspace : NSObject
+ (OwnershipWorkspace *)sharedWorkspace;
- (BOOL)isFilePackageAtPath:(NSString *)path;
- (BOOL)setIcon:(id)image forFile:(NSString *)path options:(NSUInteger)options;
- (OwnershipImage *)iconForFile:(NSString *)path;
@end
@interface OwnershipFileManager : NSObject
+ (OwnershipFileManager *)defaultManager;
- (NSString *)displayNameAtPath:(NSString *)path;
@end

CFURLRef OwnershipCreateURL(CFAllocatorRef, CFStringRef, CFURLPathStyle, Boolean);
CFStringRef OwnershipCopyPath(CFURLRef, CFURLPathStyle);
CGImageDestinationRef OwnershipCreateDestination(CFMutableDataRef, CFStringRef, size_t, CFDictionaryRef);
void OwnershipAddImage(CGImageDestinationRef, CGImageRef, CFDictionaryRef);
bool OwnershipFinalize(CGImageDestinationRef);

#define NSURL OwnershipURL
#define NSImage OwnershipImage
#define NSWorkspace OwnershipWorkspace
#define NSFileManager OwnershipFileManager
#define CFURLCreateWithFileSystemPath OwnershipCreateURL
#define CFURLCopyFileSystemPath OwnershipCopyPath
#define CGImageDestinationCreateWithData OwnershipCreateDestination
#define CGImageDestinationAddImage OwnershipAddImage
#define CGImageDestinationFinalize OwnershipFinalize
