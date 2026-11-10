#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <codecvt>
#include <cstring>
#include <iostream>
#include <locale>
#include <stdexcept>

static std::map<PA_Unichar*, size_t> strings;
static std::map<PA_Picture, int> pictures;
static std::map<PA_Handle, size_t> handles;
static bool nullEmpty, failHandle, failCommand, failPointer, failResize;
static int platformMode, platformCalls, commandCalls;
static CUTF16String expected;

static void check(bool valid, const char* message)
{
    if (!valid) {
        std::cerr << message << "\n";
        std::exit(1);
    }
}

static CUTF16String utf16(const char* text)
{
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> codec;
    auto converted = codec.from_bytes(text);
    return CUTF16String(reinterpret_cast<const PA_Unichar*>(converted.data()), converted.size());
}

static PA_Unistring makeString(const PA_Unichar* text)
{
    size_t units = 0;
    while (text && text[units]) ++units;
    PA_Unistring value = {};
    if (units || !nullEmpty) {
        value.fString = new PA_Unichar[units + 1];
        if (units) std::memcpy(value.fString, text, units * sizeof(PA_Unichar));
        value.fString[units] = 0;
        value.fLength = static_cast<PA_long32>(units);
        strings[value.fString] = units;
    }
    return value;
}

static void disposeString(PA_Unistring value)
{
    if (!value.fString) {
        check(value.fLength == 0, "null string with nonzero length");
        return;
    }
    check(strings.count(value.fString), "duplicate/unowned string disposal");
    check(strings.at(value.fString) == static_cast<size_t>(value.fLength), "allocation length");
    strings.erase(value.fString);
    delete[] value.fString;
}

static void textEquals(PA_Unistring value, const CUTF16String& wanted)
{
    check(value.fLength == static_cast<PA_long32>(wanted.size()), "exact UTF16 length");
    check(value.fString || wanted.empty(), "missing text allocation");
    if (value.fString) {
        check(strings.count(value.fString), "read after string release");
        check(value.fString[value.fLength] == 0, "text terminator");
        check(CUTF16String(value.fString, value.fLength) == wanted, "exact UTF16 content");
    }
}

static PA_Picture makePicture()
{
    PA_Picture p = new unsigned char(42);
    pictures[p] = 1;
    return p;
}

static void releasePicture(PA_Picture p)
{
    if (!p) return;
    check(pictures.count(p), "duplicate/unowned picture disposal");
    if (--pictures[p] == 0) {
        pictures.erase(p);
        delete static_cast<unsigned char*>(p);
    }
}

static void clear(PA_Variable* v)
{
    if (v->fType == eVK_Unistring) disposeString(v->uValue.fString);
    else if (v->fType == eVK_Picture) releasePicture(v->uValue.fPicture);
    else if (v->fType == eVK_ArrayUnicode) {
        auto h = v->uValue.fArray.fData;
        check(handles.count(h), "invalid array handle");
        auto values = reinterpret_cast<PA_Unistring*>(*h);
        for (PA_long32 i = 0; i <= v->uValue.fArray.fNbElements; ++i) disposeString(values[i]);
        std::free(*h);
        delete h;
        handles.erase(h);
    } else check(v->fType == eVK_Undefined || v->fType == eVK_Longint,
                 "unsupported clear kind (including raw-kind0 failure sentinel)");
    v->fType = eVK_Undefined;
    v->fFiller = 0;
}

static void host(short selector, EngineBlock* eb)
{
    switch (selector) {
    case EX_CREATE_UNISTRING:
        eb->fUniString1 = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
        break;
    case EX_DISPOSE_UNISTRING:
        disposeString(eb->fUniString1);
        break;
    case EX_SET_UNISTRING: {
        auto replacement = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
        disposeString(eb->fUniString1);
        eb->fUniString1 = replacement;
        break;
    }
    case EX_CREATE_PICTURE:
        check(eb->fParam1 == 0 || eb->fPtr1, "picture bytes missing");
        eb->fPicture = makePicture();
        eb->fError = 0;
        break;
    case EX_DISPOSE_PICTURE:
        releasePicture(eb->fPicture);
        break;
    case EX_CREATE_NATIVE_PICTURE_FOR_SCREEN:
        check(pictures.count(eb->fPicture), "native conversion of dead picture");
        eb->fHandle = reinterpret_cast<PA_Handle>(CFDataCreateMutable(kCFAllocatorDefault, 0));
        eb->fError = 0;
        break;
    case EX_DUPLICATE_PICTURE:
        if (!eb->fPicture) break;
        check(pictures.count(eb->fPicture), "retain dead picture");
        if (eb->fParam1 == 0) ++pictures[eb->fPicture];
        else eb->fPicture = makePicture();
        break;
    case EX_GET_PICTURE_DATA:
        check(pictures.count(eb->fPicture), "enumerate dead picture");
        eb->fError = eER_IncompatibleTypes;
        // Metadata failure is intentionally poisonous, not an owning empty string.
        eb->fUniString1.fLength = -1;
        eb->fUniString1.fString = reinterpret_cast<PA_Unichar*>(1);
        break;
    case EX_CLEAR_VARIABLE:
        clear(static_cast<PA_Variable*>(eb->fPtr1));
        break;
    case EX_GET_INFORMATION:
        eb->fParam1 = 0;
        break;
    case EX_GET_POINTER_VALUE_PROPERTIES:
        eb->fParam1 = eVK_Unistring;
        eb->fParam2 = 0;
        eb->fParam3 = 0;
        eb->fError = 0;
        break;
    case EX_GET_POINTER_VALUE:
        if (failPointer) {
            std::memset(eb->fHandle, 0xa5, sizeof(PA_Variable));
            eb->fError = eER_IncompatibleTypes;
        } else {
            auto v = reinterpret_cast<PA_Variable*>(eb->fHandle);
            *v = PA_CreateVariable(eVK_Undefined);
            auto owned = makeString(expected.c_str());
            PA_SetStringVariable(v, &owned);
            eb->fError = 0;
        }
        break;
    case EX_HANDLE_MANAGER: {
        auto h = eb->fHandle;
        switch (eb->fParam1) {
        case 1:
            if (failHandle) {
                eb->fHandle = nullptr;
                eb->fError = eER_IncompatibleTypes;
                break;
            }
            h = new char*;
            *h = static_cast<char*>(std::calloc(1, std::max<sLONG_PTR>(1, eb->fParam2)));
            check(*h, "test handle allocation failed");
            handles[h] = eb->fParam2;
            eb->fHandle = h;
            break;
        case 2:
            check(handles.count(h), "dispose dead handle");
            std::free(*h);
            delete h;
            handles.erase(h);
            break;
        case 3: {
            check(handles.count(h), "resize dead handle");
            if (failResize) {
                eb->fError = eER_IncompatibleTypes;
                break;
            }
            auto data = static_cast<char*>(std::realloc(*h, std::max<sLONG_PTR>(1, eb->fParam2)));
            check(data, "test resize allocation failed");
            *h = data;
            handles[h] = eb->fParam2;
            break;
        }
        case 4:
            check(handles.count(h), "size dead handle");
            eb->fParam2 = handles[h];
            break;
        case 5:
            check(handles.count(h), "lock dead handle");
            eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h);
            break;
        case 6:
            check(handles.count(h), "unlock dead handle");
            break;
        default: check(false, "unexpected handle operation");
        }
        break;
    }
    case EX_CONVERT_CHARSET_TO_CHARSET: {
        check(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16, "conversion direction");
        std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> codec;
        auto in = static_cast<char*>(eb->fPtr1);
        auto out = codec.from_bytes(in, in + eb->fParam1);
        size_t bytes = out.size() * sizeof(PA_Unichar);
        check(bytes + sizeof(PA_Unichar) <= static_cast<size_t>(eb->fParam3), "UTF16 capacity");
        std::memcpy(eb->fPtr2, out.data(), bytes);
        std::memset(static_cast<char*>(eb->fPtr2) + bytes, 0, sizeof(PA_Unichar));
        eb->fParam3 = bytes;
        eb->fError = 0;
        break;
    }
    case EX_EXECUTE_COMMAND_BY_ID: {
        ++commandCalls;
        auto args = static_cast<PA_Variable**>(eb->fPtr1);
        auto result = static_cast<PA_Variable*>(eb->fPtr2);
        check(result->fType == eVK_Undefined, "command return initialization");
        if (failCommand) {
            std::memset(result, 0xa5, sizeof(*result));
            eb->fError = eER_IncompatibleTypes;
            break;
        }
        if (eb->fParam1 == 678) {
            textEquals(args[0]->uValue.fString, expected);
            clear(args[1]);
            PA_SetPictureVariable(args[1], makePicture());
        } else if (eb->fParam1 == 1002) {
            textEquals(args[1]->uValue.fString, expected);
            clear(args[0]);
            PA_SetPictureVariable(args[0], makePicture());
        } else if (eb->fParam1 == 988) {
            clear(args[0]);
            PA_SetPictureVariable(args[0], makePicture());
        } else if (eb->fParam1 == 457) {
            check(pictures.count(args[0]->uValue.fPicture), "size input dead");
            PA_SetLongintVariable(args[1], 23);
            PA_SetLongintVariable(args[2], 17);
        } else if (eb->fParam1 == 679) {
            check(pictures.count(args[0]->uValue.fPicture), "thumbnail input dead");
            clear(args[1]);
            PA_SetPictureVariable(args[1], makePicture());
        } else check(false, "unexpected command");
        // Successful command return is a separate owner, even for these procedures.
        auto owned = makeString(expected.c_str());
        PA_SetStringVariable(result, &owned);
        eb->fError = 0;
        break;
    }
    default:
        std::cerr << "unexpected engine selector " << selector << "\n";
        std::exit(1);
    }
}

@implementation OwnershipURL
- (id)initWithString:(NSString *)value { return [super init]; }
- (NSString *)absoluteString { return @"synthetic"; }
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
    ++platformCalls;
    if (platformMode == 1) return NO;
    if ([key isEqualToString:NSURLLocalizedNameKey])
        *value = [NSString stringWithCharacters:expected.data() length:expected.size()];
    else *value = @YES;
    return YES;
}
- (BOOL)setResourceValue:(id)value forKey:(NSString *)key error:(NSError **)error
{ ++platformCalls; return platformMode != 1; }
@end
@implementation OwnershipImage
- (id)initWithCGImage:(CGImageRef)image size:(NSSize)size { return [super init]; }
- (NSData *)TIFFRepresentation { return [NSData dataWithBytes:"123" length:3]; }
- (CGImageRef)CGImageForProposedRect:(NSRect *)rect context:(id)context hints:(id)hints
{ ++platformCalls; return platformMode == 3 ? nullptr : reinterpret_cast<CGImageRef>(1); }
@end
@implementation OwnershipWorkspace
+ (OwnershipWorkspace *)sharedWorkspace { return [[[self alloc] init] autorelease]; }
- (BOOL)isFilePackageAtPath:(NSString *)path { ++platformCalls; return YES; }
- (BOOL)setIcon:(id)image forFile:(NSString *)path options:(NSUInteger)options
{ ++platformCalls; return YES; }
- (OwnershipImage *)iconForFile:(NSString *)path
{ ++platformCalls; return platformMode == 2 ? nil : [[[OwnershipImage alloc] init] autorelease]; }
@end
@implementation OwnershipFileManager
+ (OwnershipFileManager *)defaultManager { return [[[self alloc] init] autorelease]; }
- (NSString *)displayNameAtPath:(NSString *)path
{ ++platformCalls; return [NSString stringWithCharacters:expected.data() length:expected.size()]; }
@end
CFURLRef OwnershipCreateURL(CFAllocatorRef, CFStringRef, CFURLPathStyle, Boolean)
{ return platformMode == 4 ? nullptr : reinterpret_cast<CFURLRef>([[OwnershipURL alloc] init]); }
CFStringRef OwnershipCopyPath(CFURLRef, CFURLPathStyle)
{ return reinterpret_cast<CFStringRef>([[NSString alloc] initWithString:@"synthetic"]); }
CGImageDestinationRef OwnershipCreateDestination(CFMutableDataRef data, CFStringRef, size_t, CFDictionaryRef)
{
    ++platformCalls;
    const UInt8 bytes[] = {1, 2, 3};
    CFDataAppendBytes(data, bytes, sizeof(bytes));
    if (platformMode == 5) return nullptr;
    CFRetain(data);
    return reinterpret_cast<CGImageDestinationRef>(data);
}
void OwnershipAddImage(CGImageDestinationRef, CGImageRef image, CFDictionaryRef)
{ check(image == reinterpret_cast<CGImageRef>(1), "non-synthetic image"); ++platformCalls; }
bool OwnershipFinalize(CGImageDestinationRef) { ++platformCalls; return true; }

static void pictureCase(const std::string& name, const char* text)
{
    expected = utf16(text);
    PA_Picture handoff = nullptr, returned = nullptr, param = makePicture();
    {
        CPicture picture;
        if (name == "path") {
            CUTF8String path(reinterpret_cast<const uint8_t*>(text));
            picture.fromFileAtPath(&path);
        } else if (name == "bytes") {
            const uint8_t synthetic[] = {1, 2, 3};
            picture.setBytes(synthetic, sizeof(synthetic));
            picture.setBytes(synthetic, sizeof(synthetic));
        } else if (name == "copy") handoff = picture.createCopy(text);
        else if (name == "gray") handoff = picture.createGrayScale();
        else if (name == "size") {
            unsigned width = 0, height = 0;
            picture.getSize(&width, &height);
            check(width == 23 && height == 17, "size outputs");
        } else if (name == "thumbnail") handoff = picture.createThumbnail(23, 17);
        else check(false, "unknown picture test");
        if (handoff) check(pictures[handoff] == 1, "handoff is not sole owned reference");
        check(pictures.count(picture.getPicture()), "wrapper died during callback");
        picture.setReturn(reinterpret_cast<sLONG_PTR*>(&returned));
        check(pictures[returned] == 2, "independently retained return");
        BytePtr params[] = {reinterpret_cast<BytePtr>(&param)};
        picture.toParamAtIndex(params, 1);
        check(param == returned && pictures[param] == 3, "independently retained parameter");
    }
    check(pictures.count(returned) && pictures[returned] == 2, "output survives wrapper");
    PA_DisposePicture(returned);
    PA_DisposePicture(param);
    if (handoff) PA_DisposePicture(handoff);
}

static void failureCase(const std::string& name, bool handleFailure)
{
    CPicture picture;
    failHandle = handleFailure;
    failCommand = !handleFailure;
    bool threw = false;
    try {
        if (name == "path") {
            CUTF8String path;
            picture.fromFileAtPath(&path);
        } else if (name == "copy") PA_DisposePicture(picture.createCopy(""));
        else if (name == "gray") PA_DisposePicture(picture.createGrayScale());
        else if (name == "size") {
            unsigned width = 90, height = 91;
            picture.getSize(&width, &height);
        } else if (name == "thumbnail") PA_DisposePicture(picture.createThumbnail(23, 17));
        else check(false, "unknown failure test");
    } catch (const std::runtime_error&) { threw = true; }
    failHandle = failCommand = false;
    check(threw, "command failure not surfaced");
    check(pictures.count(picture.getPicture()), "failure destroyed wrapper input");
}

static void scalarCase(const char* text)
{
    auto wanted = utf16(text);
    auto input = PA_CreateUnistring(const_cast<PA_Unichar*>(wanted.c_str()));
    auto result = PA_CreateUnistring(nullptr), output = PA_CreateUnistring(nullptr);
    {
        C_TEXT wrapper;
        BytePtr params[] = {reinterpret_cast<BytePtr>(&input)};
        wrapper.fromParamAtIndex(params, 1);
        auto changed = utf16("changed");
        PA_SetUnistring(&input, const_cast<PA_Unichar*>(changed.c_str()));
        params[0] = reinterpret_cast<BytePtr>(&output);
        wrapper.toParamAtIndex(params, 1);
        auto resultPtr = &result;
        wrapper.setReturn(reinterpret_cast<sLONG_PTR*>(&resultPtr));
    }
    textEquals(result, wanted);
    textEquals(output, wanted);
    PA_DisposeUnistring(&input);
    PA_DisposeUnistring(&output);
    PA_DisposeUnistring(&result);
}

static void arrayCase()
{
    auto arr = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&arr, 4);
    const char* fixtures[] = {"ASCII", "\xe6\x97\xa5", "\xf0\x9f\x98\x80", "", ""};
    for (int i = 0; i <= 4; ++i) {
        auto text = utf16(fixtures[i]);
        auto owned = PA_CreateUnistring(const_cast<PA_Unichar*>(text.c_str()));
        PA_SetStringInArray(arr, i, &owned);
    }
    BytePtr params[] = {reinterpret_cast<BytePtr>(&arr)};
    ARRAY_TEXT copy;
    copy.fromParamAtIndex(params, 1);
    auto replacementText = utf16("replacement");
    auto replacement = PA_CreateUnistring(const_cast<PA_Unichar*>(replacementText.c_str()));
    PA_SetStringInArray(arr, 0, &replacement);
    for (int repeat = 0; repeat < 20; ++repeat) {
        auto churn = PA_CreateUnistring(const_cast<PA_Unichar*>(replacementText.c_str()));
        PA_DisposeUnistring(&churn);
        copy.toParamAtIndex(params, 1);
        for (int i = 0; i <= 4; ++i) textEquals(PA_GetStringInArray(arr, i), utf16(fixtures[i]));
    }
    auto reject = PA_CreateUnistring(const_cast<PA_Unichar*>(replacementText.c_str()));
    PA_SetStringInArray(arr, -1, &reject);
    PA_SetStringInArray(arr, 5, &reject);
    auto wrong = PA_CreateVariable(eVK_Longint);
    PA_SetStringInArray(wrong, 0, &reject);
    copy.toParamAtIndex(reinterpret_cast<PackagePtr>(params), 0);
    auto missing = arr;
    missing.uValue.fArray.fData = nullptr;
    PA_SetStringInArray(missing, 0, &reject);
    PA_SetStringInArray(arr, 0, nullptr);
    textEquals(reject, replacementText);
    PA_DisposeUnistring(&reject);
    copy.setSize(2);
    copy.toParamAtIndex(params, 1);
    copy.setSize(0);
    copy.toParamAtIndex(params, 1);
    PA_ClearVariable(&arr);
    arr = PA_CreateVariable(eVK_Undefined);
    params[0] = reinterpret_cast<BytePtr>(&arr);
    copy.appendUTF16String(replacementText.c_str());
    copy.toParamAtIndex(params, 1);
    PA_ClearVariable(&arr);
    auto input = PA_CreateUnistring(const_cast<PA_Unichar*>(replacementText.c_str()));
    auto arg = PA_CreateVariable(eVK_Undefined);
    PA_SetStringVariable(&arg, &input);
    textEquals(arg.uValue.fString, replacementText);
    PA_ClearVariable(&arg);
}

static void sdkFailureCase()
{
    failHandle = true;
    auto result = PA_ExecuteCommandByID(457, nullptr, 0);
    check(result.fType == 0 && PA_GetLastError() != eER_NoErr, "raw-kind0 command failure");
    check(PA_GetVariableKind(result) == eVK_Unistring, "raw-kind0 normalization");
    failHandle = false;
    auto arr = PA_CreateVariable(eVK_ArrayUnicode);
    auto bytes = PA_GetHandleSize(arr.uValue.fArray.fData);
    failResize = true;
    PA_ResizeArray(&arr, 7);
    check(arr.uValue.fArray.fNbElements == 7, "SDK failure changes logical count");
    check(PA_GetHandleSize(arr.uValue.fArray.fData) == bytes, "SDK failure preserves physical size");
    failResize = false;
    // Restore only the test descriptor before cleanup; do not execute unsafe wrapper writes.
    arr.uValue.fArray.fNbElements = 0;
    PA_ClearVariable(&arr);
}

static void pointerCase(bool failure)
{
    C_POINTER wrapper;
    PointerBlock pointer = {};
    pointer.fClass = 1;
    pointer.fScope = 0;
    BytePtr params[] = {reinterpret_cast<BytePtr>(&pointer)};
    wrapper.fromParamAtIndex(params, 1);
    failPointer = failure;
    PA_Variable output = PA_CreateVariable(eVK_Undefined);
    bool threw = false;
    try { wrapper.getVariable(&output); }
    catch (const std::runtime_error&) { threw = true; }
    failPointer = false;
    check(threw == failure, "pointer failure not surfaced");
    if (failure) check(output.fType == eVK_Undefined, "pointer failure mutated destination");
}

static void dispatchCase(int selector, int mode, const char* text)
{
    platformMode = mode;
    expected = utf16(text);
    auto input = PA_CreateUnistring(const_cast<PA_Unichar*>(expected.c_str()));
    PA_long32 flag = 1, result = -1;
    auto picture = makePicture();
    BytePtr params[] = {reinterpret_cast<BytePtr>(&input),
                       selector == 9 ? reinterpret_cast<BytePtr>(&picture) : reinterpret_cast<BytePtr>(&flag)};
    if (selector == 6 || selector == 11) {
        auto output = PA_CreateUnistring(nullptr);
        auto outputPtr = &output;
        CommandDispatcher(selector, reinterpret_cast<sLONG_PTR*>(&outputPtr), params);
        textEquals(output, selector == 6 && (mode == 1 || mode == 4) ? CUTF16String() : expected);
        PA_DisposeUnistring(&output);
    } else if (selector == 10) {
        PA_Picture output = nullptr;
        CommandDispatcher(selector, reinterpret_cast<sLONG_PTR*>(&output), params);
        check(pictures.count(output) && pictures[output] == 1, "dispatcher picture result owner");
        PA_DisposePicture(output);
    } else CommandDispatcher(selector, reinterpret_cast<sLONG_PTR*>(&result), params);
    PA_DisposeUnistring(&input);
    PA_DisposePicture(picture);
    check(platformCalls > 0 || mode == 4, "synthetic boundary not reached");
}

int main(int argc, char** argv)
{
    @autoreleasepool {
        check(argc >= 2, "test name required");
        gCall4D = host;
        nullEmpty = argc >= 4 && std::string(argv[3]) == "null";
        std::string name = argv[1];
        const char* text = argc >= 3 ? argv[2] : "";
        expected = utf16(text);
        if (name == "arrays") arrayCase();
        else if (name == "scalar") scalarCase(text);
        else if (name == "sdk-failures") sdkFailureCase();
        else if (name == "pointer") pointerCase(false);
        else if (name == "pointer-failure") pointerCase(true);
        else if (name == "dispatch") {
            check(argc == 6, "dispatch arguments");
            dispatchCase(std::stoi(argv[4]), std::stoi(argv[5]), text);
        } else if (name.find("-handle-failure") != std::string::npos)
            failureCase(name.substr(0, name.find("-handle-failure")), true);
        else if (name.find("-command-failure") != std::string::npos)
            failureCase(name.substr(0, name.find("-command-failure")), false);
        else pictureCase(name, text);
        check(strings.empty(), "unbalanced string allocations");
        check(pictures.empty(), "unbalanced picture references");
        check(handles.empty(), "unbalanced handles");
        std::cout << "PASS " << name << " strings=0 pictures=0 handles=0 objects=0 collections=0"
                  << " platform=" << platformCalls << " commands=" << commandCalls << "\n";
    }
}
