/*
 * Notepad für macOS – alter Textspeicher (Vergleichsbasis für die Benchmarks).
 * LICENSE: LGPL-2.1-or-later
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The previous PlainTextStorage implementation (backed by an NSMutableAttributedString),
/// kept only so the tests can compare it against the gap buffer storage.
@interface LegacyTextStorage : NSTextStorage
@property (nonatomic, readonly) NSMutableString *backingString;
@end

NS_ASSUME_NONNULL_END
