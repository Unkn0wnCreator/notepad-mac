/*
 * Notepad für macOS – schneller Textspeicher für große Dateien.
 * LICENSE: LGPL-2.1-or-later
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Mutable string stored as a gap buffer of code units: an edit costs O(length of the edit +
/// distance to the previous edit) instead of moving everything after the edit point. Text with
/// only Latin-1 characters (≤ U+00FF) takes one byte per character; the first wider character
/// converts the buffer to UTF-16 once (like CFMutableString does for ASCII text).
/// `getCharacters:range:` copies at most two contiguous pieces; `copy` returns a contiguous
/// immutable NSString (one copy pass). `CFStringGetCharactersPtr` returns NULL for it.
@interface GapBufferString : NSMutableString

/// Takes over a `malloc`ed buffer of `length` Latin-1 code units (one byte per character,
/// `capacity` bytes allocated) without copying it; the string frees it.
- (instancetype)initAdoptingLatin1Bytes:(uint8_t *)bytes length:(NSUInteger)length capacity:(NSUInteger)capacity;

@end

/// NSTextStorage backed by a `GapBufferString` and a compact array of attribute runs.
/// Written in Objective-C on purpose: a Swift subclass pays bridging costs on every call.
/// Attributes are fixed lazily, so loading 200 MB takes ~50 ms and jumping into the middle
/// needs no layout of everything before it. Typing anywhere in a 1 GB document is about as
/// fast as typing at its end (only the first keystroke at a new place moves the gap).
@interface PlainTextStorage : NSTextStorage

/// The characters without bridging or copying (the same object as `string`). Use this instead
/// of `string` in Swift code that runs per keystroke – bridging a mutable string to Swift
/// copies all of it. Typed as NSMutableString only because Swift does not bridge that type;
/// never mutate it.
@property (nonatomic, readonly) NSMutableString *backingString;

/// Replaces the whole text with `text`, which becomes the backing string itself (no copy) –
/// used when opening files. Attributes of the old first character carry over.
- (void)adoptText:(GapBufferString *)text;

@end

NS_ASSUME_NONNULL_END
