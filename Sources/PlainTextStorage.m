/*
 * Notepad für macOS – schneller Textspeicher für große Dateien.
 * LICENSE: LGPL-2.1-or-later
 */

#import "PlainTextStorage.h"

#pragma mark - Gap buffer string

// Spare room (in code units) added whenever the buffer grows: 1/64 of the text, at least 4 K
// and at most 16 M code units. A huge gap left behind by a big deletion is given back once it
// exceeds both the text length and kGapShrinkThreshold.
static const NSUInteger kMinGap = 4096;
static const NSUInteger kMaxGap = (NSUInteger)16 << 20;
static const NSUInteger kGapShrinkThreshold = (NSUInteger)64 << 20;
// Characters are copied in chunks of this many code units when the source must be inspected.
enum { kChunk = 16384 };

static NSUInteger SpareGapForLength(NSUInteger length) {
    NSUInteger gap = length / 64;
    return gap < kMinGap ? kMinGap : (gap > kMaxGap ? kMaxGap : gap);
}

static void RaiseRange(id object, SEL selector, NSRange range, NSUInteger length) {
    [NSException raise:NSRangeException
                format:@"-[%@ %@]: Range {%lu, %lu} out of bounds; string length %lu",
                       NSStringFromClass([object class]), NSStringFromSelector(selector),
                       (unsigned long)range.location, (unsigned long)range.length, (unsigned long)length];
}

static inline BOOL RangeInBounds(NSRange range, NSUInteger length) {
    return range.location <= length && range.length <= length - range.location;
}

static void *AllocateUnits(NSUInteger count, size_t unitSize) {
    if (count > NSUIntegerMax / 4) {
        [NSException raise:NSMallocException format:@"GapBufferString: %lu characters are too many", (unsigned long)count];
    }
    void *buffer = malloc(count ? count * unitSize : 1);
    if (!buffer) {
        [NSException raise:NSMallocException format:@"GapBufferString: out of memory (%lu characters)", (unsigned long)count];
    }
    return buffer;
}

// Simple loops the compiler vectorizes.
static void WidenUnits(unichar *destination, const uint8_t *source, NSUInteger count) {
    for (NSUInteger i = 0; i < count; i++) destination[i] = source[i];
}

/// Stores the low bytes and returns the OR of all code units: > 0xFF means the destination
/// is unusable because some unit does not fit into one byte.
static unichar NarrowUnits(uint8_t *restrict destination, const unichar *restrict source, NSUInteger count) {
    unichar bits = 0;
    for (NSUInteger i = 0; i < count; i++) {
        bits |= source[i];
        destination[i] = (uint8_t)source[i];
    }
    return bits;
}

/// Stores Latin-1 text (all code units ≤ 0xFF, e.g. ASCII or German text) with one byte per
/// code unit (CFString does the same for ASCII); the first wider character converts the buffer
/// to UTF-16 once.
@implementation GapBufferString {
    void *_buffer;          // uint8_t (narrow) or unichar (wide) code units
    NSUInteger _capacity;   // code units allocated
    NSUInteger _gapStart;   // first code unit of the gap == number of characters before it
    NSUInteger _gapEnd;     // first code unit after the gap
    BOOL _wide;             // unichar storage
    BOOL _maybeNonASCII;    // narrow storage may contain bytes ≥ 0x80 (never reset by deletions)
}

#define NARROW ((uint8_t *)_buffer)
#define WIDE ((unichar *)_buffer)

- (instancetype)init {
    if ((self = [super init])) {
        _buffer = AllocateUnits(0, 1);
    }
    return self;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _buffer = AllocateUnits(capacity, 1);
        _capacity = _gapEnd = capacity;
    }
    return self;
}

- (instancetype)initWithCharactersNoCopy:(unichar *)characters length:(NSUInteger)length freeWhenDone:(BOOL)freeBuffer {
    self = [self initWithCharacters:characters length:length];
    if (freeBuffer) free(characters);
    return self;
}

- (instancetype)initWithCharacters:(const unichar *)characters length:(NSUInteger)length {
    if ((self = [self initWithCapacity:length])) {
        [self putCharacters:characters count:length];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)string {
    NSUInteger length = string.length;
    if ((self = [self initWithCapacity:length])) {
        [self putString:string count:length];
    }
    return self;
}

- (void)dealloc {
    free(_buffer);
}

#pragma mark Primitives

- (NSUInteger)length {
    return _capacity - (_gapEnd - _gapStart);
}

- (unichar)characterAtIndex:(NSUInteger)index {
    NSUInteger physical = index < _gapStart ? index : index + (_gapEnd - _gapStart);
    if (physical >= _capacity) RaiseRange(self, _cmd, NSMakeRange(index, 1), self.length);
    return _wide ? WIDE[physical] : NARROW[physical];
}

/// Copies `count` code units starting at the physical position `physical` (outside the gap).
- (void)copyUnitsFrom:(NSUInteger)physical count:(NSUInteger)count into:(unichar *)out {
    if (_wide) memcpy(out, WIDE + physical, count * sizeof(unichar));
    else WidenUnits(out, NARROW + physical, count);
}

- (void)getCharacters:(unichar *)out range:(NSRange)range {
    if (!RangeInBounds(range, self.length)) RaiseRange(self, _cmd, range, self.length);
    NSUInteger location = range.location, remaining = range.length;
    if (location < _gapStart) {
        NSUInteger before = MIN(remaining, _gapStart - location);
        [self copyUnitsFrom:location count:before into:out];
        out += before;
        location += before;
        remaining -= before;
    }
    if (remaining) [self copyUnitsFrom:location + (_gapEnd - _gapStart) count:remaining into:out];
}

#pragma mark Editing

- (size_t)unitSize {
    return _wide ? sizeof(unichar) : 1;
}

/// Moves the gap so it starts at `position` (a logical index ≤ length).
- (void)moveGapTo:(NSUInteger)position {
    size_t unit = self.unitSize;
    char *bytes = _buffer;
    if (position < _gapStart) {
        NSUInteger count = _gapStart - position;
        memmove(bytes + (_gapEnd - count) * unit, bytes + position * unit, count * unit);
        _gapStart = position;
        _gapEnd -= count;
    } else if (position > _gapStart) {
        NSUInteger count = position - _gapStart;
        memmove(bytes + _gapStart * unit, bytes + _gapEnd * unit, count * unit);
        _gapStart += count;
        _gapEnd += count;
    }
}

/// Reallocates to `newCapacity` code units, keeping the gap where it is (the text after the
/// gap moves to the new end).
- (void)resizeTo:(NSUInteger)newCapacity {
    size_t unit = self.unitSize;
    NSUInteger tail = _capacity - _gapEnd;
    if (newCapacity < _capacity) {
        memmove((char *)_buffer + (newCapacity - tail) * unit, (char *)_buffer + _gapEnd * unit, tail * unit);
    }
    void *resized = realloc(_buffer, (newCapacity ? newCapacity : 1) * unit);
    if (!resized) {
        if (newCapacity < _capacity) resized = _buffer;   // shrinking failed: keep the larger block
        else [NSException raise:NSMallocException format:@"GapBufferString: out of memory (%lu characters)", (unsigned long)newCapacity];
    }
    _buffer = resized;
    if (newCapacity > _capacity) {
        memmove((char *)_buffer + (newCapacity - tail) * unit, (char *)_buffer + _gapEnd * unit, tail * unit);
    }
    _gapEnd = newCapacity - tail;
    _capacity = newCapacity;
}

/// Grows the buffer (keeping the gap where it is) so the gap holds at least `needed` units.
- (void)ensureGap:(NSUInteger)needed {
    if (_gapEnd - _gapStart >= needed) return;
    NSUInteger length = self.length;
    if (needed > NSUIntegerMax / 8 - length) [NSException raise:NSMallocException format:@"GapBufferString: string too long"];
    [self resizeTo:length + needed + SpareGapForLength(length + needed)];
}

/// Converts narrow storage to UTF-16 (same capacity and gap).
- (void)becomeWide {
    unichar *wide = AllocateUnits(_capacity, sizeof(unichar));
    WidenUnits(wide, NARROW, _gapStart);
    WidenUnits(wide + _gapEnd, NARROW + _gapEnd, _capacity - _gapEnd);
    free(_buffer);
    _buffer = wide;
    _wide = YES;
}

/// Writes `count` code units into the gap (which must have room for them) and advances it.
- (void)putCharacters:(const unichar *)characters count:(NSUInteger)count {
    if (!_wide) {
        unichar bits = NarrowUnits(NARROW + _gapStart, characters, count);
        if (bits <= 0xFF) {
            if (bits & 0x80) _maybeNonASCII = YES;
            _gapStart += count;
            return;
        }
        [self becomeWide];   // the narrow bytes just written are in the gap and get overwritten
    }
    memcpy(WIDE + _gapStart, characters, count * sizeof(unichar));
    _gapStart += count;
}

/// Writes the first `count` characters of `string` into the gap (which must have room).
- (void)putString:(NSString *)string count:(NSUInteger)count {
    if (!_wide) {
        // ASCII prefix in one go: a plain copy for 8-bit strings (typical for decoded files);
        // stops at the first non-ASCII character otherwise.
        CFIndex converted = 0;
        CFStringGetBytes((__bridge CFStringRef)string, CFRangeMake(0, (CFIndex)count), kCFStringEncodingASCII, 0, false,
                         NARROW + _gapStart, (CFIndex)count, &converted);
        _gapStart += (NSUInteger)converted;
        if ((NSUInteger)converted == count) return;
        const unichar *direct = CFStringGetCharactersPtr((__bridge CFStringRef)string);
        unichar chunk[kChunk];
        NSUInteger done = (NSUInteger)converted;
        while (done < count && !_wide) {
            NSUInteger n = MIN((NSUInteger)kChunk, count - done);
            if (direct) {
                [self putCharacters:direct + done count:n];
            } else {
                [string getCharacters:chunk range:NSMakeRange(done, n)];
                [self putCharacters:chunk count:n];
            }
            done += n;
        }
        if (done == count) return;
        string = [string substringFromIndex:done];   // became wide: copy the rest directly
        count -= done;
    }
    [string getCharacters:WIDE + _gapStart range:NSMakeRange(0, count)];
    _gapStart += count;
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    NSUInteger length = self.length;
    if (!RangeInBounds(range, length)) RaiseRange(self, _cmd, range, length);
    if (string == self) string = [string copy];
    NSUInteger count = string.length;

    if (range.length == length) {
        // Replacing everything (e.g. loading a file): start over with a fresh narrow buffer
        // instead of moving or reallocating the old contents.
        free(_buffer);
        _wide = _maybeNonASCII = NO;
        _capacity = _gapEnd = count + SpareGapForLength(count);
        _gapStart = 0;
        _buffer = AllocateUnits(_capacity, 1);
        [self putString:string count:count];
        return;
    }

    // Delete by moving the gap to whichever end of the range is closer, then swallowing it.
    if (range.length && _gapStart >= NSMaxRange(range)) {
        [self moveGapTo:NSMaxRange(range)];
        _gapStart = range.location;
    } else {
        [self moveGapTo:range.location];
        _gapEnd += range.length;
    }
    if (count) {
        [self ensureGap:count];
        [self putString:string count:count];
    } else {
        NSUInteger gap = _gapEnd - _gapStart;
        if (gap > kGapShrinkThreshold && gap > self.length) {
            [self resizeTo:self.length + SpareGapForLength(self.length)];   // give memory back
        }
    }
}

#pragma mark Fast paths

/// A new immutable string with the characters in `range` (one copy, no per-character work).
- (NSString *)immutableStringWithRange:(NSRange)range {
    if (range.length == 0) return @"";
    if (!_wide && !_maybeNonASCII) {
        uint8_t *bytes = AllocateUnits(range.length, 1);
        NSUInteger before = range.location < _gapStart ? MIN(range.length, _gapStart - range.location) : 0;
        memcpy(bytes, NARROW + range.location, before);
        memcpy(bytes + before, NARROW + range.location + before + (_gapEnd - _gapStart), range.length - before);
        return [[NSString alloc] initWithBytesNoCopy:bytes length:range.length encoding:NSASCIIStringEncoding freeWhenDone:YES];
    }
    unichar *characters = AllocateUnits(range.length, sizeof(unichar));
    [self getCharacters:characters range:range];
    return [[NSString alloc] initWithCharactersNoCopy:characters length:range.length freeWhenDone:YES];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self immutableStringWithRange:NSMakeRange(0, self.length)];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[GapBufferString alloc] initWithString:self];
}

- (NSString *)substringWithRange:(NSRange)range {
    if (!RangeInBounds(range, self.length)) RaiseRange(self, _cmd, range, self.length);
    return [self immutableStringWithRange:range];
}

- (NSString *)substringFromIndex:(NSUInteger)from {
    return [self substringWithRange:NSMakeRange(from, self.length - MIN(from, self.length))];
}

- (NSString *)substringToIndex:(NSUInteger)to {
    return [self substringWithRange:NSMakeRange(0, to)];
}

@end

#pragma mark - Text storage

// One attribute run: the attributes from `start` up to the next run's start (or the end).
// `attributes` holds a +1 reference to an immutable NSDictionary.
typedef struct {
    NSUInteger start;
    const void *attributes;
} AttributeRun;

static inline NSDictionary *RunAttributes(const AttributeRun *run) {
    return (__bridge NSDictionary *)run->attributes;
}

static inline BOOL SameAttributes(const void *a, const void *b) {
    return a == b || [(__bridge NSDictionary *)a isEqualToDictionary:(__bridge NSDictionary *)b];
}

@implementation PlainTextStorage {
    GapBufferString *_text;
    NSUInteger _length;          // == _text.length, kept here for the run bookkeeping
    AttributeRun *_runs;         // sorted by start, _runs[0].start == 0, no empty runs
    NSUInteger _runCount;
    NSUInteger _runCapacity;
    NSUInteger _lastRun;         // lookup hint: layout queries attributes mostly in order
}

- (instancetype)init {
    if ((self = [super init])) {
        _text = [[GapBufferString alloc] init];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)str {
    return [self initWithString:str attributes:nil];
}

- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs {
    if ((self = [self init])) {
        [self replaceCharactersInRange:NSMakeRange(0, 0) withString:str];
        if (attrs) [self setAttributes:attrs range:NSMakeRange(0, _length)];
    }
    return self;
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr {
    if ((self = [self init])) {
        [self replaceCharactersInRange:NSMakeRange(0, 0) withString:attrStr.string];
        [attrStr enumerateAttributesInRange:NSMakeRange(0, attrStr.length) options:0
                                 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            [self setAttributes:attrs range:range];
        }];
    }
    return self;
}

- (void)dealloc {
    for (NSUInteger i = 0; i < _runCount; i++) CFRelease(_runs[i].attributes);
    free(_runs);
}

- (NSString *)string {
    return _text;
}

- (NSMutableString *)backingString {
    return _text;
}

- (NSUInteger)length {
    return _length;
}

- (BOOL)fixesAttributesLazily {
    return YES;
}

#pragma mark Runs

- (NSUInteger)runEnd:(NSUInteger)index {
    return index + 1 < _runCount ? _runs[index + 1].start : _length;
}

/// Index of the run containing `position` (< _length).
- (NSUInteger)runIndexAt:(NSUInteger)position {
    NSUInteger hint = _lastRun;
    if (hint < _runCount && _runs[hint].start <= position) {
        if (position < [self runEnd:hint]) return hint;
        if (hint + 1 < _runCount && position < [self runEnd:hint + 1]) return _lastRun = hint + 1;
    }
    NSUInteger low = 0, high = _runCount;   // last run with start <= position
    while (high - low > 1) {
        NSUInteger mid = low + (high - low) / 2;
        if (_runs[mid].start <= position) low = mid; else high = mid;
    }
    return _lastRun = low;
}

/// Opens room for `count` runs at `index` (the new slots are uninitialized).
- (void)openRuns:(NSUInteger)count at:(NSUInteger)index {
    if (_runCount + count > _runCapacity) {
        NSUInteger capacity = MAX(_runCapacity * 2, _runCount + count);
        capacity = MAX(capacity, 4);
        AttributeRun *grown = realloc(_runs, capacity * sizeof(AttributeRun));
        if (!grown) [NSException raise:NSMallocException format:@"PlainTextStorage: out of memory"];
        _runs = grown;
        _runCapacity = capacity;
    }
    memmove(_runs + index + count, _runs + index, (_runCount - index) * sizeof(AttributeRun));
    _runCount += count;
}

/// Removes (and releases) the runs in [index, index + count).
- (void)removeRuns:(NSUInteger)count at:(NSUInteger)index {
    if (!count) return;
    for (NSUInteger i = index; i < index + count; i++) CFRelease(_runs[i].attributes);
    memmove(_runs + index, _runs + index + count, (_runCount - index - count) * sizeof(AttributeRun));
    _runCount -= count;
}

- (void)shiftRunsFrom:(NSUInteger)index by:(NSInteger)delta {
    for (NSUInteger i = index; i < _runCount; i++) _runs[i].start += (NSUInteger)delta;
}

/// Makes a run start at `position` and returns its index (_runCount if position == _length).
- (NSUInteger)splitAt:(NSUInteger)position {
    if (position >= _length) return _runCount;
    NSUInteger index = [self runIndexAt:position];
    if (_runs[index].start == position) return index;
    [self openRuns:1 at:index + 1];
    _runs[index + 1].start = position;
    _runs[index + 1].attributes = CFRetain(_runs[index].attributes);
    return index + 1;
}

/// Merges run `index` into run `index - 1` if both have equal attributes.
- (void)mergeWithPrevious:(NSUInteger)index {
    if (index == 0 || index >= _runCount) return;
    if (SameAttributes(_runs[index - 1].attributes, _runs[index].attributes)) {
        [self removeRuns:1 at:index];
    }
}

/// Updates the runs for replacing `range` with `count` characters having `attributes`.
- (void)replaceRunsInRange:(NSRange)range count:(NSUInteger)count attributes:(NSDictionary *)attributes {
    NSInteger delta = (NSInteger)count - (NSInteger)range.length;
    NSUInteger newLength = _length + (NSUInteger)delta;
    if (newLength == 0) {
        [self removeRuns:_runCount at:0];
        _length = 0;
        return;
    }
    if (_runCount == 0) {
        [self openRuns:1 at:0];
        _runs[0].start = 0;
        _runs[0].attributes = CFBridgingRetain(attributes);
        _length = newLength;
        return;
    }

    // Common case: the edit stays inside one run whose attributes the new characters inherit
    // (always true for insertions) – just shift the following runs.
    NSUInteger index = [self runIndexAt:(range.length || range.location == 0) ? range.location : range.location - 1];
    NSUInteger runStart = _runs[index].start, runEnd = [self runEnd:index];
    if (NSMaxRange(range) <= runEnd && (NSInteger)(runEnd - runStart) + delta > 0) {
        [self shiftRunsFrom:index + 1 by:delta];
        _length = newLength;
        return;
    }

    // General case: cut out the runs covering the range, then insert one run for the new text.
    NSUInteger first = [self splitAt:range.location];
    NSUInteger last = [self splitAt:NSMaxRange(range)];
    [self removeRuns:last - first at:first];
    [self shiftRunsFrom:first by:-(NSInteger)range.length];
    _length -= range.length;
    if (count) {
        [self openRuns:1 at:first];
        _runs[first].start = range.location;
        _runs[first].attributes = CFBridgingRetain(attributes);
        [self shiftRunsFrom:first + 1 by:(NSInteger)count];
        _length += count;
        [self mergeWithPrevious:first + 1];
    }
    [self mergeWithPrevious:first];
    _lastRun = 0;
}

#pragma mark NSTextStorage primitives

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)range {
    if (location >= _length) RaiseRange(self, _cmd, NSMakeRange(location, 0), _length);
    NSUInteger index = _runCount == 1 ? 0 : [self runIndexAt:location];
    if (range) {
        NSUInteger start = _runs[index].start;
        *range = NSMakeRange(start, [self runEnd:index] - start);
    }
    return RunAttributes(&_runs[index]);
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    if (!RangeInBounds(range, _length)) RaiseRange(self, _cmd, range, _length);
    NSUInteger count = str.length;

    // New characters inherit the attributes of the first replaced character, otherwise of
    // the preceding one, otherwise of the following one (like NSMutableAttributedString).
    NSDictionary *inherited = nil;
    if (count) {
        if (_length == 0) inherited = @{};
        else if (range.length || range.location == 0) inherited = RunAttributes(&_runs[[self runIndexAt:range.location]]);
        else inherited = RunAttributes(&_runs[[self runIndexAt:range.location - 1]]);
    }

    [self beginEditing];
    [_text replaceCharactersInRange:range withString:str];
    [self replaceRunsInRange:range count:count attributes:inherited];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:(NSInteger)count - (NSInteger)range.length];
    [self endEditing];
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    if (!RangeInBounds(range, _length)) RaiseRange(self, _cmd, range, _length);
    [self beginEditing];
    if (range.length) {
        NSDictionary *attributes = attrs ? [attrs copy] : @{};
        NSUInteger first = [self splitAt:range.location];
        NSUInteger last = [self splitAt:NSMaxRange(range)];
        // Reuse run `first` for the whole range and drop the others.
        CFRelease(_runs[first].attributes);
        _runs[first].attributes = CFBridgingRetain(attributes);
        [self removeRuns:last - first - 1 at:first + 1];
        [self mergeWithPrevious:first + 1];
        [self mergeWithPrevious:first];
        _lastRun = 0;
    }
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
    [self endEditing];
}

@end
