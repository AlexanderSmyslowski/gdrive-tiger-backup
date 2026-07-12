#import "ConfigSupport.h"

typedef NS_ENUM(NSUInteger, GDTConfigQuoteState) {
    GDTConfigQuoteStateUnquoted,
    GDTConfigQuoteStateSingleQuoted,
    GDTConfigQuoteStateDoubleQuoted,
    GDTConfigQuoteStateANSICQuoted
};

static BOOL GDTIsValidConfigKey(NSString *key) {
    if (!key.length) {
        return NO;
    }

    NSCharacterSet *firstCharacters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"];
    NSCharacterSet *remainingCharacters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789"];
    if (![firstCharacters characterIsMember:[key characterAtIndex:0]]) {
        return NO;
    }
    for (NSUInteger index = 1; index < key.length; index++) {
        if (![remainingCharacters characterIsMember:[key characterAtIndex:index]]) {
            return NO;
        }
    }
    return YES;
}

static BOOL GDTValidateUpdates(NSDictionary<NSString *, NSString *> *updates, NSError **error) {
    for (NSString *key in updates) {
        NSString *value = updates[key];
        // Both the app reader and the backup script treat one physical line as
        // one assignment, so accepting newlines would create a corrupt config.
        if (!GDTIsValidConfigKey(key) ||
            [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.config"
                                              code:64
                                          userInfo:@{NSLocalizedDescriptionKey: @"Config keys and values must fit on one safe shell-assignment line."}];
            }
            return NO;
        }
    }
    return YES;
}

static void GDTAppendUTF8(NSMutableData *data, NSString *value) {
    NSData *encoded = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (encoded) {
        [data appendData:encoded];
    }
}

static BOOL GDTAppendANSIEscape(NSMutableData *decoded, NSString *value, NSUInteger *index) {
    NSUInteger length = value.length;
    if (*index + 1 >= length) {
        return NO;
    }

    unichar escaped = [value characterAtIndex:++(*index)];
    switch (escaped) {
        case 'a': { uint8_t byte = 0x07; [decoded appendBytes:&byte length:1]; return YES; }
        case 'b': { uint8_t byte = 0x08; [decoded appendBytes:&byte length:1]; return YES; }
        case 'e':
        case 'E': { uint8_t byte = 0x1b; [decoded appendBytes:&byte length:1]; return YES; }
        case 'f': { uint8_t byte = 0x0c; [decoded appendBytes:&byte length:1]; return YES; }
        case 'n': { uint8_t byte = '\n'; [decoded appendBytes:&byte length:1]; return YES; }
        case 'r': { uint8_t byte = '\r'; [decoded appendBytes:&byte length:1]; return YES; }
        case 't': { uint8_t byte = '\t'; [decoded appendBytes:&byte length:1]; return YES; }
        case 'v': { uint8_t byte = 0x0b; [decoded appendBytes:&byte length:1]; return YES; }
        case '\\': { uint8_t byte = '\\'; [decoded appendBytes:&byte length:1]; return YES; }
        case '\'': { uint8_t byte = '\''; [decoded appendBytes:&byte length:1]; return YES; }
        case '"': { uint8_t byte = '"'; [decoded appendBytes:&byte length:1]; return YES; }
        default:
            break;
    }

    if (escaped >= '0' && escaped <= '7') {
        NSUInteger scalar = escaped - '0';
        NSUInteger digits = 1;
        while (digits < 3 && *index + 1 < length) {
            unichar next = [value characterAtIndex:*index + 1];
            if (next < '0' || next > '7') {
                break;
            }
            scalar = scalar * 8 + (next - '0');
            ++(*index);
            ++digits;
        }
        uint8_t byte = (uint8_t)(scalar & 0xff);
        [decoded appendBytes:&byte length:1];
        return YES;
    }

    if (escaped == 'x') {
        NSUInteger scalar = 0;
        NSUInteger digits = 0;
        while (digits < 2 && *index + 1 < length) {
            unichar next = [value characterAtIndex:*index + 1];
            NSUInteger nibble;
            if (next >= '0' && next <= '9') {
                nibble = next - '0';
            } else if (next >= 'a' && next <= 'f') {
                nibble = next - 'a' + 10;
            } else if (next >= 'A' && next <= 'F') {
                nibble = next - 'A' + 10;
            } else {
                break;
            }
            scalar = scalar * 16 + nibble;
            ++(*index);
            ++digits;
        }
        if (digits) {
            uint8_t byte = (uint8_t)scalar;
            [decoded appendBytes:&byte length:1];
        } else {
            GDTAppendUTF8(decoded, @"\\x");
        }
        return YES;
    }

    // Bash keeps the slash for unknown ANSI-C escapes, so the app mirrors that
    // behavior instead of silently changing values written by `printf %q`.
    GDTAppendUTF8(decoded, [NSString stringWithFormat:@"\\%C", escaped]);
    return YES;
}

static BOOL GDTIsSafeProfileID(NSString *profileID) {
    if (![profileID isKindOfClass:NSString.class] || !profileID.length || profileID.length > 64) {
        return NO;
    }
    NSCharacterSet *first = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789"];
    NSCharacterSet *remaining = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789-"];
    if (![first characterIsMember:[profileID characterAtIndex:0]]) return NO;
    for (NSUInteger index = 1; index < profileID.length; index++) {
        if (![remaining characterIsMember:[profileID characterAtIndex:index]]) return NO;
    }
    return YES;
}

NSString *GDTConfigPathForConfigDirectory(NSString *configDirectory) {
    NSString *root = configDirectory.stringByStandardizingPath;
    NSString *legacyPath = [root stringByAppendingPathComponent:@"config"];
    NSString *activePath = [root stringByAppendingPathComponent:@"active-profile"];
    NSDictionary *activeAttributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:activePath error:nil];
    if (![activeAttributes[NSFileType] isEqualToString:NSFileTypeRegular]) return legacyPath;
    NSString *profilesPath = [root stringByAppendingPathComponent:@"profiles"];
    NSDictionary *profilesAttributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:profilesPath error:nil];
    if (![profilesAttributes[NSFileType] isEqualToString:NSFileTypeDirectory]) return legacyPath;
    NSString *profileID = [[NSString stringWithContentsOfFile:activePath
                                                     encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!GDTIsSafeProfileID(profileID)) return legacyPath;
    NSString *profilePath = [profilesPath
        stringByAppendingPathComponent:[profileID stringByAppendingPathExtension:@"conf"]];
    NSDictionary *attributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:profilePath error:nil];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) return legacyPath;
    NSDictionary<NSString *, NSString *> *profile = GDTReadConfigDictionaryAtPath(profilePath);
    return [profile[@"GDRIVE_BACKUP_PROFILE_ID"] isEqualToString:profileID]
        ? profilePath : legacyPath;
}

NSString *GDTConfigPath(void) {
    const char *override = getenv("GDRIVE_BACKUP_CONFIG");
    if (override && override[0] != '\0') {
        return [NSString stringWithUTF8String:override];
    }
    const char *directoryOverride = getenv("GDRIVE_BACKUP_CONFIG_DIR");
    NSString *directory = directoryOverride && directoryOverride[0] != '\0'
        ? [NSString stringWithUTF8String:directoryOverride]
        : [NSHomeDirectory() stringByAppendingPathComponent:@".config/gdrive-tiger-backup"];
    return GDTConfigPathForConfigDirectory(directory);
}

NSString *GDTDecodeConfigValue(NSString *value) {
    // The backup script sources this file, but the UI must never execute it just
    // to display a setting. Decode only the literal quoting forms the app and
    // Bash's `printf %q` emit, leaving substitutions such as `$HOME` untouched.
    NSString *source = value ?: @"";
    NSMutableString *decoded = [NSMutableString stringWithCapacity:source.length];
    NSMutableData *ansiBytes = [NSMutableData data];
    GDTConfigQuoteState state = GDTConfigQuoteStateUnquoted;
    BOOL valid = YES;

    for (NSUInteger index = 0; index < source.length; index++) {
        unichar character = [source characterAtIndex:index];
        switch (state) {
            case GDTConfigQuoteStateUnquoted:
                if (character == '\'') {
                    state = GDTConfigQuoteStateSingleQuoted;
                } else if (character == '"') {
                    state = GDTConfigQuoteStateDoubleQuoted;
                } else if (character == '$' && index + 1 < source.length && [source characterAtIndex:index + 1] == '\'') {
                    state = GDTConfigQuoteStateANSICQuoted;
                    [ansiBytes setLength:0];
                    index++;
                } else if (character == '\\') {
                    if (index + 1 >= source.length) {
                        valid = NO;
                        index = source.length;
                    } else {
                        unichar next = [source characterAtIndex:++index];
                        if (next != '\n') {
                            [decoded appendFormat:@"%C", next];
                        }
                    }
                } else {
                    [decoded appendFormat:@"%C", character];
                }
                break;

            case GDTConfigQuoteStateSingleQuoted:
                if (character == '\'') {
                    state = GDTConfigQuoteStateUnquoted;
                } else {
                    [decoded appendFormat:@"%C", character];
                }
                break;

            case GDTConfigQuoteStateDoubleQuoted:
                if (character == '"') {
                    state = GDTConfigQuoteStateUnquoted;
                } else if (character == '\\' && index + 1 < source.length) {
                    unichar next = [source characterAtIndex:index + 1];
                    if (next == '$' || next == '`' || next == '"' || next == '\\') {
                        [decoded appendFormat:@"%C", next];
                        index++;
                    } else if (next == '\n') {
                        index++;
                    } else {
                        [decoded appendString:@"\\"];
                    }
                } else {
                    [decoded appendFormat:@"%C", character];
                }
                break;

            case GDTConfigQuoteStateANSICQuoted:
                if (character == '\'') {
                    NSString *ansiString = [[NSString alloc] initWithData:ansiBytes encoding:NSUTF8StringEncoding];
                    if (!ansiString) {
                        valid = NO;
                        index = source.length;
                    } else {
                        [decoded appendString:ansiString];
                        state = GDTConfigQuoteStateUnquoted;
                    }
                } else if (character == '\\') {
                    if (!GDTAppendANSIEscape(ansiBytes, source, &index)) {
                        valid = NO;
                        index = source.length;
                    }
                } else {
                    NSRange characterRange = [source rangeOfComposedCharacterSequenceAtIndex:index];
                    GDTAppendUTF8(ansiBytes, [source substringWithRange:characterRange]);
                    index = NSMaxRange(characterRange) - 1;
                }
                break;
        }
    }

    if (!valid || state != GDTConfigQuoteStateUnquoted) {
        return source;
    }
    return decoded;
}

NSMutableDictionary<NSString *, NSString *> *GDTReadConfigDictionaryAtPath(NSString *path) {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    NSString *config = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSRange range = [line rangeOfString:@"="];
        if (range.location == NSNotFound || [trimmedLine hasPrefix:@"#"]) {
            continue;
        }
        NSString *key = [[line substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (key.length) {
            values[key] = GDTDecodeConfigValue([line substringFromIndex:range.location + 1]);
        }
    }
    return values;
}

NSMutableDictionary<NSString *, NSString *> *GDTReadConfigDictionary(void) {
    return GDTReadConfigDictionaryAtPath(GDTConfigPath());
}

NSString *GDTShellQuote(NSString *value) {
    NSString *escaped = [value ?: @"" stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

BOOL GDTWriteConfigUpdatesAtPath(NSDictionary<NSString *, NSString *> *updates,
                                 NSString *path,
                                 NSError **error) {
    if (!GDTValidateUpdates(updates, error)) {
        return NO;
    }

    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length &&
        ![NSFileManager.defaultManager createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) {
        return NO;
    }

    NSError *readError = nil;
    NSString *config = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:&readError];
    BOOL missingFile = [readError.domain isEqualToString:NSCocoaErrorDomain] &&
        readError.code == NSFileReadNoSuchFileError;
    if (!config && !missingFile) {
        if (error) {
            *error = readError;
        }
        return NO;
    }
    config = config ?: @"";
    NSMutableArray<NSString *> *lines = [[config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSMutableSet<NSString *> *remaining = [NSMutableSet setWithArray:updates.allKeys];

    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSRange range = [line rangeOfString:@"="];
        if (range.location == NSNotFound || [trimmedLine hasPrefix:@"#"]) {
            continue;
        }
        NSString *key = [[line substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = updates[key];
        if (value) {
            lines[index] = [NSString stringWithFormat:@"%@=%@", key, GDTShellQuote(value)];
            [remaining removeObject:key];
        }
    }

    if (lines.count && lines.lastObject.length == 0) {
        [lines removeLastObject];
    }

    NSArray<NSString *> *orderedKeys = @[
        @"GDRIVE_BACKUP_TARGET",
        @"GDRIVE_BACKUP_NAS_MOUNT",
        @"GDRIVE_BACKUP_NAS_URL",
        @"GDRIVE_BACKUP_NAS_SUBDIR",
        @"GDRIVE_BACKUP_NAS_START_ON_MOUNT",
        @"GDRIVE_BACKUP_SCHEDULE",
        @"GDRIVE_BACKUP_VERSIONING",
        @"GDRIVE_BACKUP_VERSIONS_SUBDIR",
        @"GDRIVE_BACKUP_RETENTION",
        @"GDRIVE_BACKUP_ENCRYPTION",
        @"GDRIVE_BACKUP_CRYPT_REMOTE",
        @"GDRIVE_BACKUP_LANG"
    ];
    for (NSString *key in orderedKeys) {
        if ([remaining containsObject:key]) {
            [lines addObject:[NSString stringWithFormat:@"%@=%@", key, GDTShellQuote(updates[key])]];
            [remaining removeObject:key];
        }
    }
    for (NSString *key in [remaining.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [lines addObject:[NSString stringWithFormat:@"%@=%@", key, GDTShellQuote(updates[key])]];
    }

    NSString *newConfig = [[lines arrayByAddingObject:@""] componentsJoinedByString:@"\n"];
    if (![newConfig writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }

    // NAS URLs may contain credentials, so every app-created or app-updated
    // config remains private to the owning account.
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @(0600)}
                                          ofItemAtPath:path
                                                 error:error];
}

BOOL GDTWriteConfigUpdates(NSDictionary<NSString *, NSString *> *updates, NSError **error) {
    return GDTWriteConfigUpdatesAtPath(updates, GDTConfigPath(), error);
}
