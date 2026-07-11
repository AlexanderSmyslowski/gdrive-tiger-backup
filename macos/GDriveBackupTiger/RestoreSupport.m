#import "RestoreSupport.h"

#include <limits.h>

static NSString *const GDTRestoreErrorDomain = @"com.commcats.gdrivebackup.restore";

typedef NS_ENUM(NSInteger, GDTRestoreErrorCode) {
    GDTRestoreErrorUnsafePath = 1,
    GDTRestoreErrorUnavailableSource = 2,
    GDTRestoreErrorUnavailableDestination = 3,
    GDTRestoreErrorIntegrityFailure = 4,
    GDTRestoreErrorCopyFailure = 5
};

static void GDTSetRestoreError(NSError **error, GDTRestoreErrorCode code, NSString *description) {
    if (!error) {
        return;
    }
    *error = [NSError errorWithDomain:GDTRestoreErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL GDTIsSafeRelativePath(NSString *relativePath, BOOL allowEmpty) {
    if (!relativePath.length) {
        return allowEmpty;
    }
    if (relativePath.isAbsolutePath || [relativePath containsString:@"\0"]) {
        return NO;
    }
    for (NSString *component in relativePath.pathComponents) {
        if ([component isEqualToString:@"."] || [component isEqualToString:@".."] ||
            !component.length) {
            return NO;
        }
    }
    return YES;
}

static BOOL GDTURLIsSymbolicLink(NSURL *url) {
    return [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:url.path
                                                                   error:nil].length > 0;
}

static NSURL *GDTCanonicalRootURL(NSURL *url) {
    if (GDTURLIsSymbolicLink(url)) {
        return url;
    }
    char resolved[PATH_MAX];
    if (realpath(url.path.UTF8String, resolved)) {
        return [NSURL fileURLWithPath:[NSString stringWithUTF8String:resolved]
                         isDirectory:YES];
    }
    return url;
}

static BOOL GDTURLIsSafeDirectory(NSURL *url) {
    NSNumber *isDirectory = nil;
    if (GDTURLIsSymbolicLink(url) ||
        ![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]) {
        return NO;
    }
    return isDirectory.boolValue;
}

static BOOL GDTURLIsSafeRegularFile(NSURL *url) {
    NSNumber *isRegularFile = nil;
    if (GDTURLIsSymbolicLink(url) ||
        ![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil]) {
        return NO;
    }
    return isRegularFile.boolValue;
}

static NSDate *GDTRunDate(NSString *runID) {
    static NSRegularExpression *expression;
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}[+-][0-9]{4})-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
                                                                 options:0 error:nil];
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH-mm-ssZ";
    });
    NSTextCheckingResult *match = [expression firstMatchInString:runID
                                                         options:0
                                                           range:NSMakeRange(0, runID.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }
    return [formatter dateFromString:[runID substringWithRange:[match rangeAtIndex:1]]];
}

static BOOL GDTURLContainsSymlinkBelowRoot(NSURL *url, NSURL *rootURL) {
    if (GDTURLIsSymbolicLink(rootURL)) {
        return YES;
    }
    NSArray<NSString *> *rootComponents = rootURL.path.pathComponents;
    NSArray<NSString *> *urlComponents = url.path.pathComponents;
    if (urlComponents.count < rootComponents.count) {
        return YES;
    }
    for (NSUInteger index = 0; index < rootComponents.count; index++) {
        if (![rootComponents[index] isEqualToString:urlComponents[index]]) {
            return YES;
        }
    }
    if (urlComponents.count == rootComponents.count) {
        return NO;
    }
    NSURL *cursor = rootURL;
    for (NSUInteger index = rootComponents.count; index < urlComponents.count; index++) {
        cursor = [cursor URLByAppendingPathComponent:urlComponents[index]];
        if (GDTURLIsSymbolicLink(cursor)) {
            return YES;
        }
    }
    return NO;
}

@interface GDTRestoreCatalog ()
@property(nonatomic, strong) NSURL *backupRootURL;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic) BOOL backupRootIsSymbolicLink;
@end

@implementation GDTRestoreCatalog

- (instancetype)initWithBackupRootURL:(NSURL *)backupRootURL
                           fileManager:(NSFileManager *)fileManager {
    self = [super init];
    if (!self) {
        return nil;
    }
    _backupRootIsSymbolicLink = GDTURLIsSymbolicLink(backupRootURL);
    _backupRootURL = GDTCanonicalRootURL(backupRootURL);
    _fileManager = fileManager;
    return self;
}

- (NSArray<NSDictionary<NSString *, id> *> *)versionRunRecords {
    NSURL *versionsURL = [self.backupRootURL URLByAppendingPathComponent:@".gdrive-versions"
                                                             isDirectory:YES];
    if (!GDTURLIsSafeDirectory(versionsURL)) {
        return @[];
    }
    NSArray<NSURL *> *items = [self.fileManager contentsOfDirectoryAtURL:versionsURL
                                               includingPropertiesForKeys:@[
                                                   NSURLIsDirectoryKey,
                                                   NSURLIsSymbolicLinkKey
                                               ]
                                                                  options:0 error:nil] ?: @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *records = [NSMutableArray array];
    for (NSURL *item in items) {
        if ([item.lastPathComponent isEqualToString:@".retention-trash"] ||
            !GDTURLIsSafeDirectory(item)) {
            continue;
        }
        NSMutableDictionary<NSString *, id> *record = [@{
            @"runID": item.lastPathComponent,
            @"url": item
        } mutableCopy];
        NSDate *date = GDTRunDate(item.lastPathComponent);
        if (date) {
            record[@"date"] = date;
        }
        [records addObject:record];
    }
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSDate *leftDate = left[@"date"];
        NSDate *rightDate = right[@"date"];
        if (leftDate && rightDate) {
            NSComparisonResult result = [rightDate compare:leftDate];
            if (result != NSOrderedSame) {
                return result;
            }
        } else if (leftDate) {
            return NSOrderedAscending;
        } else if (rightDate) {
            return NSOrderedDescending;
        }
        return [right[@"runID"] compare:left[@"runID"] options:NSCaseInsensitiveSearch];
    }];
    return records;
}

- (NSArray<NSURL *> *)containerURLs {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithObject:self.backupRootURL];
    for (NSDictionary<NSString *, id> *record in [self versionRunRecords]) {
        [urls addObject:record[@"url"]];
    }
    return urls;
}

- (NSArray<NSDictionary<NSString *, id> *> *)childrenAtRelativePath:(NSString *)relativePath
                                                               error:(NSError **)error {
    if (self.backupRootIsSymbolicLink) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath,
                           @"The configured backup root is a symbolic link.");
        return @[];
    }
    if (!GDTIsSafeRelativePath(relativePath, YES)) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath,
                           @"The selected backup path is not safe.");
        return @[];
    }

    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *entries =
        [NSMutableDictionary dictionary];
    for (NSURL *containerURL in [self containerURLs]) {
        NSURL *directoryURL = relativePath.length
            ? [containerURL URLByAppendingPathComponent:relativePath isDirectory:YES]
            : containerURL;
        if (!GDTURLIsSafeDirectory(directoryURL) ||
            GDTURLContainsSymlinkBelowRoot(directoryURL, containerURL)) {
            continue;
        }
        NSArray<NSURL *> *items = [self.fileManager contentsOfDirectoryAtURL:directoryURL
                                                   includingPropertiesForKeys:@[
                                                       NSURLIsDirectoryKey,
                                                       NSURLIsRegularFileKey,
                                                       NSURLIsSymbolicLinkKey
                                                   ] options:0 error:nil] ?: @[];
        for (NSURL *item in items) {
            NSString *name = item.lastPathComponent;
            if (!relativePath.length && [name isEqualToString:@".gdrive-versions"]) {
                continue;
            }
            NSNumber *isDirectory = nil;
            NSNumber *isRegularFile = nil;
            [item getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            [item getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
            if (GDTURLIsSymbolicLink(item) || (!isDirectory.boolValue && !isRegularFile.boolValue)) {
                continue;
            }
            NSString *childPath = relativePath.length
                ? [relativePath stringByAppendingPathComponent:name]
                : name;
            NSMutableDictionary<NSString *, id> *existing = entries[name];
            NSString *kind = isDirectory.boolValue ? @"directory" : @"file";
            if (!existing || [kind isEqualToString:@"directory"]) {
                entries[name] = [@{
                    @"name": name,
                    @"relativePath": childPath,
                    @"kind": kind
                } mutableCopy];
            }
        }
    }
    NSArray<NSDictionary<NSString *, id> *> *values = entries.allValues;
    return [values sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left,
                                                                   NSDictionary *right) {
        BOOL leftDirectory = [left[@"kind"] isEqualToString:@"directory"];
        BOOL rightDirectory = [right[@"kind"] isEqualToString:@"directory"];
        if (leftDirectory != rightDirectory) {
            return leftDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

- (NSDictionary<NSString *, id> *)versionRecordForURL:(NSURL *)url
                                                  kind:(NSString *)kind
                                                 runID:(nullable NSString *)runID
                                                  date:(nullable NSDate *)date {
    NSNumber *size = nil;
    NSDate *modified = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
    NSMutableDictionary<NSString *, id> *record = [@{
        @"sourceURL": url,
        @"kind": kind,
        @"size": size ?: @0
    } mutableCopy];
    if (runID) {
        record[@"runID"] = runID;
    }
    if (date ?: modified) {
        record[@"date"] = date ?: modified;
    }
    return record;
}

- (NSArray<NSDictionary<NSString *, id> *> *)versionsForRelativePath:(NSString *)relativePath
                                                                error:(NSError **)error {
    if (self.backupRootIsSymbolicLink) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath,
                           @"The configured backup root is a symbolic link.");
        return @[];
    }
    if (!GDTIsSafeRelativePath(relativePath, NO)) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath,
                           @"The selected backup path is not safe.");
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *records = [NSMutableArray array];
    NSURL *currentURL = [self.backupRootURL URLByAppendingPathComponent:relativePath];
    if (GDTURLIsSafeRegularFile(currentURL) &&
        !GDTURLContainsSymlinkBelowRoot(currentURL, self.backupRootURL)) {
        [records addObject:[self versionRecordForURL:currentURL kind:@"current"
                                                  runID:nil date:nil]];
    }
    for (NSDictionary<NSString *, id> *run in [self versionRunRecords]) {
        NSURL *runURL = run[@"url"];
        NSURL *sourceURL = [runURL URLByAppendingPathComponent:relativePath];
        if (!GDTURLIsSafeRegularFile(sourceURL) ||
            GDTURLContainsSymlinkBelowRoot(sourceURL, runURL)) {
            continue;
        }
        [records addObject:[self versionRecordForURL:sourceURL kind:@"historical"
                                                  runID:run[@"runID"] date:run[@"date"]]];
    }
    return records;
}

@end

@interface GDTRestoreCopier ()
@property(nonatomic, strong) NSURL *backupRootURL;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic) BOOL backupRootIsSymbolicLink;
@end


@implementation GDTRestoreCopier

- (instancetype)initWithBackupRootURL:(NSURL *)backupRootURL
                           fileManager:(NSFileManager *)fileManager {
    self = [super init];
    if (!self) {
        return nil;
    }
    _backupRootIsSymbolicLink = GDTURLIsSymbolicLink(backupRootURL);
    _backupRootURL = GDTCanonicalRootURL(backupRootURL);
    _fileManager = fileManager;
    __weak typeof(self) weakSelf = self;
    _digestProvider = [^NSString *(NSURL *url, NSError **error) {
        return [weakSelf sha256ForURL:url error:error];
    } copy];
    return self;
}

- (NSString *)sha256ForURL:(NSURL *)url error:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/shasum";
    task.arguments = @[@"-a", @"256", @"--", url.path];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        GDTSetRestoreError(error, GDTRestoreErrorIntegrityFailure,
                           @"The restored file could not be verified.");
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSString *digest = output.length >= 64 ? [output substringToIndex:64] : @"";
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    if (task.terminationStatus != 0 || digest.length != 64 ||
        [digest rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound) {
        GDTSetRestoreError(error, GDTRestoreErrorIntegrityFailure,
                           @"The restored file could not be verified.");
        return nil;
    }
    return digest;
}

- (NSURL *)availableDestinationForName:(NSString *)name directoryURL:(NSURL *)directoryURL {
    NSString *extension = name.pathExtension;
    NSString *baseName = extension.length ? name.stringByDeletingPathExtension : name;
    for (NSUInteger index = 0; index < NSUIntegerMax; index++) {
        NSString *suffix = index == 0 ? @"" :
            (index == 1 ? @" restored" : [NSString stringWithFormat:@" restored %lu",
                                           (unsigned long)index]);
        NSString *candidateName = extension.length
            ? [NSString stringWithFormat:@"%@%@.%@", baseName, suffix, extension]
            : [baseName stringByAppendingString:suffix];
        NSURL *candidate = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![self.fileManager fileExistsAtPath:candidate.path]) {
            return candidate;
        }
    }
    return nil;
}

- (void)trashTemporaryURL:(NSURL *)url {
    if ([self.fileManager fileExistsAtPath:url.path]) {
        [self.fileManager trashItemAtURL:url resultingItemURL:nil error:nil];
    }
}

- (nullable NSDictionary<NSString *, id> *)restoreSourceURL:(NSURL *)sourceURL
                                             toDirectoryURL:(NSURL *)directoryURL
                                                       error:(NSError **)error {
    NSURL *standardSource = sourceURL;
    NSString *rootPrefix = [self.backupRootURL.path stringByAppendingString:@"/"];
    if (self.backupRootIsSymbolicLink ||
        ![standardSource.path hasPrefix:rootPrefix] ||
        GDTURLContainsSymlinkBelowRoot(standardSource, self.backupRootURL) ||
        !GDTURLIsSafeRegularFile(standardSource)) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableSource,
                           @"The selected backup file is unavailable or unsafe.");
        return nil;
    }
    NSURL *resolvedDestination = directoryURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *resolvedRoot = self.backupRootURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSString *resolvedRootPrefix = [resolvedRoot.path stringByAppendingString:@"/"];
    if ([resolvedDestination.path isEqualToString:resolvedRoot.path] ||
        [resolvedDestination.path hasPrefix:resolvedRootPrefix] ||
        !GDTURLIsSafeDirectory(directoryURL) ||
        ![self.fileManager isWritableFileAtPath:directoryURL.path]) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableDestination,
                           @"The restore destination is unavailable or not writable.");
        return nil;
    }

    NSURL *destinationURL = [self availableDestinationForName:standardSource.lastPathComponent
                                                  directoryURL:directoryURL];
    if (!destinationURL) {
        GDTSetRestoreError(error, GDTRestoreErrorCopyFailure,
                           @"A safe destination name could not be created.");
        return nil;
    }
    NSURL *temporaryURL = [directoryURL URLByAppendingPathComponent:
        [NSString stringWithFormat:@".gdrive-restore-%@.tmp", NSUUID.UUID.UUIDString]];

    NSError *digestError = nil;
    NSString *sourceDigestBefore = self.digestProvider(standardSource, &digestError);
    if (!sourceDigestBefore.length) {
        if (error) {
            *error = digestError;
        }
        return nil;
    }
    NSError *copyError = nil;
    if (![self.fileManager copyItemAtURL:standardSource toURL:temporaryURL error:&copyError]) {
        if (error) {
            *error = copyError;
        }
        return nil;
    }

    NSString *sourceDigestAfter = self.digestProvider(standardSource, &digestError);
    NSString *copiedDigest = self.digestProvider(temporaryURL, &digestError);
    if (!sourceDigestAfter.length || !copiedDigest.length ||
        ![sourceDigestBefore isEqualToString:sourceDigestAfter] ||
        ![sourceDigestBefore isEqualToString:copiedDigest]) {
        [self trashTemporaryURL:temporaryURL];
        GDTSetRestoreError(error, GDTRestoreErrorIntegrityFailure,
                           @"The restored file did not match the backup copy.");
        return nil;
    }
    if (![self.fileManager moveItemAtURL:temporaryURL toURL:destinationURL error:&copyError]) {
        [self trashTemporaryURL:temporaryURL];
        if (error) {
            *error = copyError;
        }
        return nil;
    }
    NSNumber *size = nil;
    [destinationURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    return @{
        @"destinationURL": destinationURL,
        @"sha256": copiedDigest,
        @"size": size ?: @0
    };
}

@end
