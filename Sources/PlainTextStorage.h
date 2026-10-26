/*
 * Notepad für macOS – schneller Textspeicher für große Dateien.
 * LICENSE: LGPL-2.1-or-later
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// NSTextStorage backed by an NSMutableAttributedString. Written in Objective-C on purpose:
/// a Swift subclass pays bridging costs on every call. Attributes are fixed lazily, so loading
/// 200 MB takes ~50 ms instead of ~600 ms and jumping into the middle needs no layout of
/// everything before it.
@interface PlainTextStorage : NSTextStorage

/// The characters without bridging or copying. Use this instead of `string` in Swift code
/// that runs per keystroke – bridging a mutable string to Swift copies all of it.
/// Typed as NSMutableString only because Swift does not bridge that type; never mutate it.
@property (nonatomic, readonly) NSMutableString *backingString;

@end

NS_ASSUME_NONNULL_END
