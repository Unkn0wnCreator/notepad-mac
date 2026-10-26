/*
 * Notepad für macOS – alter Textspeicher (Vergleichsbasis für die Benchmarks).
 * LICENSE: LGPL-2.1-or-later
 */

#import "LegacyTextStorage.h"

@implementation LegacyTextStorage {
    NSMutableAttributedString *_backing;
}

- (instancetype)init {
    if ((self = [super init])) {
        _backing = [[NSMutableAttributedString alloc] init];
    }
    return self;
}

- (NSString *)string {
    return _backing.string;
}

- (NSMutableString *)backingString {
    // The real backing string; `mutableString` would return a slow forwarding proxy.
    return (NSMutableString *)_backing.string;
}

- (BOOL)fixesAttributesLazily {
    return YES;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)range {
    return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    [self beginEditing];
    [_backing replaceCharactersInRange:range withString:str];
    [self edited:NSTextStorageEditedCharacters
           range:range
  changeInLength:(NSInteger)str.length - (NSInteger)range.length];
    [self endEditing];
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    [self beginEditing];
    [_backing setAttributes:attrs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
    [self endEditing];
}

@end
