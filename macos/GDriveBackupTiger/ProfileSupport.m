#import "ProfileSupport.h"

#import "ConfigSupport.h"

static NSString * const GDTProfileErrorDomain = @"com.commcats.gdrivebackup.profiles";

static NSError *GDTProfileError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:GDTProfileErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL GDTValidProfileID(NSString *profileID) {
    if (![profileID isKindOfClass:NSString.class] || profileID.length > 64) {
        return NO;
    }
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^[a-z0-9][a-z0-9-]{0,63}$"
                             options:0 error:nil];
    NSRange range = NSMakeRange(0, profileID.length);
    NSTextCheckingResult *match = [expression firstMatchInString:profileID options:0 range:range];
    return match && NSEqualRanges(match.range, range);
}

static NSString *GDTNormalizedProfileName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 80 ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    return trimmed;
}

@interface GDTProfileStore ()
@property(nonatomic, copy, readwrite) NSString *configDirectory;
@end

@implementation GDTProfileStore

- (instancetype)initWithConfigDirectory:(NSString *)configDirectory {
    self = [super init];
    if (self) {
        _configDirectory = [configDirectory.stringByStandardizingPath copy];
    }
    return self;
}

- (NSString *)profilesDirectory {
    return [self.configDirectory stringByAppendingPathComponent:@"profiles"];
}

- (NSString *)activeProfilePath {
    return [self.configDirectory stringByAppendingPathComponent:@"active-profile"];
}

- (BOOL)pathIsRegularFile:(NSString *)path {
    NSDictionary *attributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:path error:nil];
    return [attributes[NSFileType] isEqualToString:NSFileTypeRegular];
}

- (BOOL)profilesDirectoryIsTrusted {
    NSDictionary *attributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:self.profilesDirectory error:nil];
    return [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
}

- (BOOL)ensureStoreDirectories:(NSError **)error {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *path in @[self.configDirectory, self.profilesDirectory]) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:error];
            if (!isDirectory || ![attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                if (error && !*error) {
                    *error = GDTProfileError(2, @"The profile store path is not a trusted directory.");
                }
                return NO;
            }
        } else if (![fileManager createDirectoryAtPath:path
                            withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700}
                                                  error:error]) {
            return NO;
        }
        if (![fileManager setAttributes:@{NSFilePosixPermissions: @0700}
                            ofItemAtPath:path error:error]) {
            return NO;
        }
    }
    return YES;
}

- (nullable NSString *)configPathForProfileID:(NSString *)profileID {
    if (!GDTValidProfileID(profileID)) return nil;
    return [[self profilesDirectory]
        stringByAppendingPathComponent:[profileID stringByAppendingPathExtension:@"conf"]];
}

- (nullable NSDictionary<NSString *, NSString *> *)profileForID:(NSString *)profileID {
    if (![self profilesDirectoryIsTrusted]) return nil;
    NSString *path = [self configPathForProfileID:profileID];
    if (!path || ![self pathIsRegularFile:path]) return nil;
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionaryAtPath(path);
    NSString *storedID = config[@"GDRIVE_BACKUP_PROFILE_ID"];
    NSString *name = GDTNormalizedProfileName(config[@"GDRIVE_BACKUP_PROFILE_NAME"]);
    if (![storedID isEqualToString:profileID] || !name) return nil;
    return @{ @"id": profileID, @"name": name, @"configPath": path };
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)profiles {
    if (![self profilesDirectoryIsTrusted]) return @[];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:self.profilesDirectory error:nil] ?: @[];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *profiles = [NSMutableArray array];
    for (NSString *entry in entries) {
        if (![entry.pathExtension isEqualToString:@"conf"]) continue;
        NSString *profileID = entry.stringByDeletingPathExtension;
        NSDictionary<NSString *, NSString *> *profile = [self profileForID:profileID];
        if (profile) [profiles addObject:profile];
    }
    [profiles sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        if ([left[@"id"] isEqualToString:@"default"]) return NSOrderedAscending;
        if ([right[@"id"] isEqualToString:@"default"]) return NSOrderedDescending;
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    return profiles;
}

- (nullable NSString *)activeProfileID {
    if (![self pathIsRegularFile:self.activeProfilePath]) return nil;
    NSString *profileID = [[NSString stringWithContentsOfFile:self.activeProfilePath
                                                     encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [self profileForID:profileID] ? profileID : nil;
}

- (nullable NSString *)activeConfigPath {
    NSString *profileID = self.activeProfileID;
    return profileID ? [self configPathForProfileID:profileID] : nil;
}

- (BOOL)writeActiveProfileID:(NSString *)profileID error:(NSError **)error {
    if ([NSFileManager.defaultManager fileExistsAtPath:self.activeProfilePath] &&
        ![self pathIsRegularFile:self.activeProfilePath]) {
        if (error) *error = GDTProfileError(7, @"The active profile pointer is not a trusted file.");
        return NO;
    }
    NSString *contents = [profileID stringByAppendingString:@"\n"];
    if (![contents writeToFile:self.activeProfilePath
                    atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                           ofItemAtPath:self.activeProfilePath error:error];
}

- (BOOL)migrateLegacyConfigAtPath:(NSString *)legacyPath error:(NSError **)error {
    if (![self ensureStoreDirectories:error]) return NO;
    NSArray<NSDictionary<NSString *, NSString *> *> *existing = self.profiles;
    if (existing.count) {
        if (self.activeProfileID) return YES;
        NSString *fallbackID = existing.firstObject[@"id"];
        return [self writeActiveProfileID:fallbackID error:error];
    }

    NSString *defaultPath = [self configPathForProfileID:@"default"];
    NSData *legacyData = nil;
    if ([self pathIsRegularFile:legacyPath]) {
        legacyData = [NSData dataWithContentsOfFile:legacyPath options:0 error:error];
        if (!legacyData) return NO;
        NSString *validUTF8 = [[NSString alloc] initWithData:legacyData
                                                    encoding:NSUTF8StringEncoding];
        if (!validUTF8) {
            if (error) *error = GDTProfileError(3, @"The existing configuration is not valid UTF-8.");
            return NO;
        }
    }
    if (!(legacyData ?: NSData.data).length) {
        legacyData = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (![legacyData writeToFile:defaultPath options:NSDataWritingAtomic error:error] ||
        ![NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                         ofItemAtPath:defaultPath error:error] ||
        !GDTWriteConfigUpdatesAtPath(@{
            @"GDRIVE_BACKUP_PROFILE_ID": @"default",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Default"
        }, defaultPath, error)) {
        return NO;
    }
    return [self writeActiveProfileID:@"default" error:error];
}

- (nullable NSDictionary<NSString *, NSString *> *)createProfileNamed:(NSString *)name
                                                          copyingConfig:(NSDictionary<NSString *, NSString *> *)config
                                                                  error:(NSError **)error {
    NSString *normalizedName = GDTNormalizedProfileName(name);
    if (!normalizedName) {
        if (error) *error = GDTProfileError(64, @"Profile names must be one safe non-empty line.");
        return nil;
    }
    if (![self ensureStoreDirectories:error]) return nil;
    NSString *profileID = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *path = [self configPathForProfileID:profileID];
    NSMutableDictionary<NSString *, NSString *> *updates = [config mutableCopy] ?: [NSMutableDictionary dictionary];
    updates[@"GDRIVE_BACKUP_PROFILE_ID"] = profileID;
    updates[@"GDRIVE_BACKUP_PROFILE_NAME"] = normalizedName;
    if (!GDTWriteConfigUpdatesAtPath(updates, path, error)) return nil;
    return [self profileForID:profileID];
}

- (BOOL)renameProfileID:(NSString *)profileID name:(NSString *)name error:(NSError **)error {
    NSString *normalizedName = GDTNormalizedProfileName(name);
    NSDictionary *profile = [self profileForID:profileID];
    if (!profile || !normalizedName) {
        if (error) *error = GDTProfileError(64, @"The profile or profile name is invalid.");
        return NO;
    }
    return GDTWriteConfigUpdatesAtPath(@{@"GDRIVE_BACKUP_PROFILE_NAME": normalizedName},
                                       profile[@"configPath"], error);
}

- (BOOL)selectProfileID:(NSString *)profileID error:(NSError **)error {
    if (![self profileForID:profileID]) {
        if (error) *error = GDTProfileError(4, @"The selected profile is unavailable.");
        return NO;
    }
    return [self writeActiveProfileID:profileID error:error];
}

- (BOOL)deleteProfileID:(NSString *)profileID error:(NSError **)error {
    NSDictionary *profile = [self profileForID:profileID];
    if (!profile || self.profiles.count <= 1 || [self.activeProfileID isEqualToString:profileID]) {
        if (error) *error = GDTProfileError(5, @"Select another profile before deleting this one.");
        return NO;
    }
    return [NSFileManager.defaultManager
        trashItemAtURL:[NSURL fileURLWithPath:profile[@"configPath"]]
      resultingItemURL:nil error:error];
}

@end
