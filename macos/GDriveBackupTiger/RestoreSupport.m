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

static BOOL GDTIsSafeRemoteName(NSString *remoteName) {
    if (!remoteName.length || remoteName.length > 64) return NO;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
                             options:0 error:nil];
    return [expression numberOfMatchesInString:remoteName options:0
                                          range:NSMakeRange(0, remoteName.length)] == 1;
}

static BOOL GDTIsSafePathComponent(NSString *name) {
    return name.length && ![name isEqualToString:@"."] && ![name isEqualToString:@".."] &&
        ![name containsString:@"/"] &&
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

static NSString *GDTExecutablePathForRestore(NSString *command) {
    NSMutableOrderedSet<NSString *> *directories = [NSMutableOrderedSet orderedSet];
    NSString *path = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
    for (NSString *directory in [path componentsSeparatedByString:@":"]) {
        if (directory.length) [directories addObject:directory];
    }
    [directories addObjectsFromArray:@[
        @"/opt/homebrew/bin", @"/usr/local/bin", @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin"
    ]];
    for (NSString *directory in directories) {
        NSString *candidate = [directory stringByAppendingPathComponent:command];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

static NSDictionary<NSString *, id> *GDTRunRestoreCommand(NSString *command,
                                                           NSArray<NSString *> *arguments) {
    NSString *launchPath = GDTExecutablePathForRestore(command);
    if (!launchPath.length) return @{ @"status": @127, @"output": @"", @"timedOut": @NO };
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments ?: @[];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = pipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    @try {
        [task launch];
    } @catch (NSException *exception) {
        (void)exception;
        return @{ @"status": @127, @"output": @"", @"timedOut": @NO };
    }
    NSMutableData *capturedOutput = [NSMutableData data];
    __block BOOL outputTruncated = NO;
    dispatch_group_t readerGroup = dispatch_group_create();
    dispatch_group_async(readerGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const NSUInteger captureLimit = 8 * 1024 * 1024 + 1;
        while (YES) {
            NSData *chunk = [pipe.fileHandleForReading availableData];
            if (!chunk.length) break;
            if (capturedOutput.length < captureLimit) {
                NSUInteger remaining = captureLimit - capturedOutput.length;
                [capturedOutput appendData:chunk.length <= remaining
                    ? chunk : [chunk subdataWithRange:NSMakeRange(0, remaining)]];
            }
            if (capturedOutput.length >= captureLimit || chunk.length > captureLimit) {
                outputTruncated = YES;
            }
        }
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0 * 60.0];
    while (task.running && deadline.timeIntervalSinceNow > 0) {
        [NSThread sleepForTimeInterval:0.05];
    }
    BOOL timedOut = task.running;
    if (timedOut) [task terminate];
    [task waitUntilExit];
    dispatch_group_wait(readerGroup, DISPATCH_TIME_FOREVER);
    NSString *output = [[NSString alloc] initWithData:capturedOutput
                                             encoding:NSUTF8StringEncoding] ?: @"";
    return @{ @"status": timedOut ? @124 : @(task.terminationStatus),
              @"output": output, @"timedOut": @(timedOut),
              @"truncated": @(outputTruncated) };
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

@interface GDTCryptRestoreCatalog ()
@property(nonatomic, copy) NSString *remoteName;
@property(nonatomic, copy) NSString *versionsSubdirectory;
@property(nonatomic, copy) GDTRestoreCommandRunner commandRunner;
@end

@implementation GDTCryptRestoreCatalog

- (instancetype)initWithRemoteName:(NSString *)remoteName
               versionsSubdirectory:(NSString *)versionsSubdirectory
                       commandRunner:(GDTRestoreCommandRunner)commandRunner {
    self = [super init];
    if (!self) return nil;
    _remoteName = [remoteName copy] ?: @"";
    _versionsSubdirectory = [versionsSubdirectory copy] ?: @"";
    _commandRunner = [commandRunner copy];
    return self;
}

+ (instancetype)productionCatalogWithRemoteName:(NSString *)remoteName
                            versionsSubdirectory:(NSString *)versionsSubdirectory {
    return [[self alloc] initWithRemoteName:remoteName
                       versionsSubdirectory:versionsSubdirectory
                               commandRunner:^NSDictionary *(NSString *command, NSArray *arguments) {
        return GDTRunRestoreCommand(command, arguments);
    }];
}

- (NSString *)remotePathForRelativePath:(NSString *)relativePath container:(NSString *)container {
    NSString *base = container.length
        ? [NSString stringWithFormat:@"%@:%@", self.remoteName, container]
        : [self.remoteName stringByAppendingString:@":"];
    return relativePath.length
        ? [base stringByAppendingFormat:@"%@%@", [base hasSuffix:@":"] ? @"" : @"/", relativePath]
        : base;
}

- (nullable id)JSONForArguments:(NSArray<NSString *> *)arguments
                   missingIsNil:(BOOL)missingIsNil
                          error:(NSError **)error {
    if (!GDTIsSafeRemoteName(self.remoteName) ||
        !GDTIsSafeRelativePath(self.versionsSubdirectory, NO) || !self.commandRunner) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath,
                           @"The encrypted restore configuration is unsafe.");
        return nil;
    }
    NSDictionary<NSString *, id> *result = self.commandRunner(@"rclone", arguments);
    NSInteger status = [result[@"status"] integerValue];
    if (missingIsNil && status == 3) return nil;
    NSString *output = [result[@"output"] isKindOfClass:NSString.class] ? result[@"output"] : @"";
    NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
    if (status != 0 || [result[@"truncated"] boolValue] ||
        data.length == 0 || data.length > 8 * 1024 * 1024) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableSource,
                           @"The encrypted backup could not be read.");
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableSource,
                           @"The encrypted backup returned invalid data.");
    }
    return json;
}

- (NSArray<NSDictionary<NSString *, id> *> *)versionRunRecordsWithError:(NSError **)error {
    NSString *remotePath = [self remotePathForRelativePath:self.versionsSubdirectory container:@""];
    id json = [self JSONForArguments:@[@"lsjson", remotePath, @"--dirs-only", @"--max-depth", @"1",
                                        @"--no-mimetype", @"--no-modtime"]
                         missingIsNil:YES error:error];
    if (!json) return @[];
    if (![json isKindOfClass:NSArray.class]) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableSource,
                           @"The encrypted version list is invalid.");
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *records = [NSMutableArray array];
    for (id value in (NSArray *)json) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = value;
        NSString *name = [item[@"Name"] isKindOfClass:NSString.class] ? item[@"Name"] : @"";
        NSString *path = [item[@"Path"] isKindOfClass:NSString.class] ? item[@"Path"] : @"";
        NSDate *date = GDTRunDate(name);
        if (![item[@"IsDir"] boolValue] || !GDTIsSafePathComponent(name) ||
            ![path isEqualToString:name] || !date) continue;
        [records addObject:@{ @"runID": name, @"date": date,
                              @"container": [self.versionsSubdirectory
                                  stringByAppendingPathComponent:name] }];
    }
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSComparisonResult result = [right[@"date"] compare:left[@"date"]];
        return result != NSOrderedSame ? result : [right[@"runID"] compare:left[@"runID"]];
    }];
    return records;
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)listAtRelativePath:(NSString *)relativePath
                                                                container:(NSString *)container
                                                                    error:(NSError **)error {
    NSString *remotePath = [self remotePathForRelativePath:relativePath container:container];
    id json = [self JSONForArguments:@[@"lsjson", remotePath, @"--max-depth", @"1",
                                        @"--no-mimetype", @"--no-modtime"]
                         missingIsNil:YES error:error];
    if (!json) return nil;
    if (![json isKindOfClass:NSArray.class]) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableSource,
                           @"The encrypted directory listing is invalid.");
        return nil;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *safe = [NSMutableArray array];
    for (id value in (NSArray *)json) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = value;
        NSString *name = [item[@"Name"] isKindOfClass:NSString.class] ? item[@"Name"] : @"";
        NSString *path = [item[@"Path"] isKindOfClass:NSString.class] ? item[@"Path"] : @"";
        if (!GDTIsSafePathComponent(name) || ![path isEqualToString:name]) continue;
        [safe addObject:item];
    }
    return safe;
}

- (NSArray<NSDictionary<NSString *, id> *> *)childrenAtRelativePath:(NSString *)relativePath
                                                               error:(NSError **)error {
    if (!GDTIsSafeRelativePath(relativePath, YES)) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath, @"The selected backup path is not safe.");
        return @[];
    }
    NSArray<NSDictionary<NSString *, id> *> *runs = [self versionRunRecordsWithError:error];
    if (error && *error) return @[];
    NSMutableArray<NSString *> *containers = [NSMutableArray arrayWithObject:@""];
    for (NSDictionary *run in runs) [containers addObject:run[@"container"]];
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *entries =
        [NSMutableDictionary dictionary];
    for (NSString *container in containers) {
        NSError *listError = nil;
        NSArray *items = [self listAtRelativePath:relativePath container:container error:&listError];
        if (listError) {
            if (error) *error = listError;
            return @[];
        }
        for (NSDictionary *item in items ?: @[]) {
            NSString *name = item[@"Name"];
            if (!relativePath.length && [name isEqualToString:self.versionsSubdirectory]) continue;
            BOOL isDirectory = [item[@"IsDir"] boolValue];
            NSString *kind = isDirectory ? @"directory" : @"file";
            NSString *childPath = relativePath.length
                ? [relativePath stringByAppendingPathComponent:name] : name;
            NSDictionary *existing = entries[name];
            if (!existing || isDirectory) {
                entries[name] = [@{ @"name": name, @"relativePath": childPath, @"kind": kind }
                    mutableCopy];
            }
        }
    }
    return [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left,
                                                                               NSDictionary *right) {
        BOOL leftDir = [left[@"kind"] isEqualToString:@"directory"];
        BOOL rightDir = [right[@"kind"] isEqualToString:@"directory"];
        if (leftDir != rightDir) return leftDir ? NSOrderedAscending : NSOrderedDescending;
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

- (nullable NSDictionary<NSString *, id> *)statRelativePath:(NSString *)relativePath
                                                   container:(NSString *)container
                                                        kind:(NSString *)kind
                                                       runID:(nullable NSString *)runID
                                                        date:(nullable NSDate *)date
                                                       error:(NSError **)error {
    NSString *remotePath = [self remotePathForRelativePath:relativePath container:container];
    id json = [self JSONForArguments:@[@"lsjson", remotePath, @"--stat", @"--no-mimetype"]
                         missingIsNil:YES error:error];
    if (!json) return nil;
    if (![json isKindOfClass:NSDictionary.class] || [json[@"IsDir"] boolValue]) return nil;
    NSString *name = relativePath.lastPathComponent;
    NSString *reportedName = [json[@"Name"] isKindOfClass:NSString.class] ? json[@"Name"] : @"";
    if (!GDTIsSafePathComponent(name) || ![reportedName isEqualToString:name]) return nil;
    NSMutableDictionary<NSString *, id> *record = [@{
        @"remotePath": remotePath, @"name": name, @"kind": kind,
        @"size": [json[@"Size"] isKindOfClass:NSNumber.class] ? json[@"Size"] : @0
    } mutableCopy];
    if (runID) record[@"runID"] = runID;
    if (date) record[@"date"] = date;
    return record;
}

- (NSArray<NSDictionary<NSString *, id> *> *)versionsForRelativePath:(NSString *)relativePath
                                                                error:(NSError **)error {
    if (!GDTIsSafeRelativePath(relativePath, NO)) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath, @"The selected backup path is not safe.");
        return @[];
    }
    NSMutableArray *records = [NSMutableArray array];
    NSError *statError = nil;
    NSDictionary *current = [self statRelativePath:relativePath container:@"" kind:@"current"
                                             runID:nil date:nil error:&statError];
    if (statError) { if (error) *error = statError; return @[]; }
    if (current) [records addObject:current];
    NSArray *runs = [self versionRunRecordsWithError:error];
    if (error && *error) return @[];
    for (NSDictionary *run in runs) {
        statError = nil;
        NSDictionary *record = [self statRelativePath:relativePath
                                             container:run[@"container"] kind:@"historical"
                                                 runID:run[@"runID"] date:run[@"date"] error:&statError];
        if (statError) { if (error) *error = statError; return @[]; }
        if (record) [records addObject:record];
    }
    return records;
}

@end

@interface GDTCryptRestoreCopier ()
@property(nonatomic, copy) NSString *remoteName;
@property(nonatomic, strong) NSURL *backupRootURL;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic, copy) GDTRestoreCommandRunner commandRunner;
@end

@implementation GDTCryptRestoreCopier

- (instancetype)initWithRemoteName:(NSString *)remoteName
                       backupRootURL:(NSURL *)backupRootURL
                         fileManager:(NSFileManager *)fileManager
                       commandRunner:(GDTRestoreCommandRunner)commandRunner {
    self = [super init];
    if (!self) return nil;
    _remoteName = [remoteName copy] ?: @"";
    _backupRootURL = GDTCanonicalRootURL(backupRootURL);
    _fileManager = fileManager;
    _commandRunner = [commandRunner copy];
    return self;
}

+ (instancetype)productionCopierWithRemoteName:(NSString *)remoteName
                                   backupRootURL:(NSURL *)backupRootURL
                                     fileManager:(NSFileManager *)fileManager {
    return [[self alloc] initWithRemoteName:remoteName backupRootURL:backupRootURL
                                fileManager:fileManager
                              commandRunner:^NSDictionary *(NSString *command, NSArray *arguments) {
        return GDTRunRestoreCommand(command, arguments);
    }];
}

- (BOOL)remotePathIsSafe:(NSString *)remotePath name:(NSString *)name {
    NSString *prefix = [self.remoteName stringByAppendingString:@":"];
    if (!GDTIsSafeRemoteName(self.remoteName) || ![remotePath hasPrefix:prefix] ||
        !GDTIsSafePathComponent(name)) return NO;
    NSString *relative = [remotePath substringFromIndex:prefix.length];
    if (!GDTIsSafeRelativePath(relative, NO) || ![relative.lastPathComponent isEqualToString:name]) return NO;
    NSArray<NSString *> *components = relative.pathComponents;
    NSSet *areas = [NSSet setWithArray:@[@"My Drive", @"Shared with me", @"Shared Drives"]];
    if ([components.firstObject isEqualToString:@".gdrive-versions"]) {
        return components.count >= 4 && GDTRunDate(components[1]) != nil &&
            [areas containsObject:components[2]];
    }
    return [areas containsObject:components.firstObject];
}

- (NSURL *)availableDestinationForName:(NSString *)name directoryURL:(NSURL *)directoryURL {
    NSString *extension = name.pathExtension;
    NSString *base = extension.length ? name.stringByDeletingPathExtension : name;
    for (NSUInteger index = 0; index < NSUIntegerMax; index++) {
        NSString *suffix = index == 0 ? @"" : (index == 1 ? @" restored" :
            [NSString stringWithFormat:@" restored %lu", (unsigned long)index]);
        NSString *candidateName = extension.length
            ? [NSString stringWithFormat:@"%@%@.%@", base, suffix, extension]
            : [base stringByAppendingString:suffix];
        NSURL *candidate = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![self.fileManager fileExistsAtPath:candidate.path]) return candidate;
    }
    return nil;
}

- (void)trashTemporaryURL:(NSURL *)url {
    if ([self.fileManager fileExistsAtPath:url.path]) {
        [self.fileManager trashItemAtURL:url resultingItemURL:nil error:nil];
    }
}

- (void)clearPlaintextListAtURL:(NSURL *)url {
    if ([self.fileManager fileExistsAtPath:url.path]) {
        [NSData.data writeToURL:url options:0 error:nil];
    }
}

- (NSString *)sha256ForURL:(NSURL *)url {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/shasum";
    task.arguments = @[@"-a", @"256", @"--", url.path];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = pipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    @try { [task launch]; [task waitUntilExit]; } @catch (NSException *exception) { return nil; }
    NSString *output = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile]
                                             encoding:NSUTF8StringEncoding] ?: @"";
    NSString *digest = output.length >= 64 ? [output substringToIndex:64] : @"";
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return task.terminationStatus == 0 && digest.length == 64 &&
        [digest rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound ? digest : nil;
}

- (nullable NSDictionary<NSString *, id> *)restoreRemotePath:(NSString *)remotePath
                                                         name:(NSString *)name
                                               toDirectoryURL:(NSURL *)directoryURL
                                                        error:(NSError **)error {
    if (![self remotePathIsSafe:remotePath name:name] || !self.commandRunner) {
        GDTSetRestoreError(error, GDTRestoreErrorUnsafePath, @"The encrypted backup path is unsafe.");
        return nil;
    }
    NSURL *resolvedDestination = directoryURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *resolvedRoot = self.backupRootURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSString *rootPrefix = [resolvedRoot.path stringByAppendingString:@"/"];
    if ([resolvedDestination.path isEqualToString:resolvedRoot.path] ||
        [resolvedDestination.path hasPrefix:rootPrefix] || !GDTURLIsSafeDirectory(directoryURL) ||
        ![self.fileManager isWritableFileAtPath:directoryURL.path]) {
        GDTSetRestoreError(error, GDTRestoreErrorUnavailableDestination,
                           @"The restore destination is unavailable or unsafe.");
        return nil;
    }
    NSURL *destination = [self availableDestinationForName:name directoryURL:directoryURL];
    if (!destination) {
        GDTSetRestoreError(error, GDTRestoreErrorCopyFailure, @"A safe destination name is unavailable.");
        return nil;
    }

    NSURL *temporaryDirectory = [directoryURL URLByAppendingPathComponent:
        [@".gdrive-restore-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *fileError = nil;
    if (![self.fileManager createDirectoryAtURL:temporaryDirectory
                    withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @(0700)}
                                         error:&fileError]) {
        if (error) *error = fileError;
        return nil;
    }
    NSURL *temporaryFile = [temporaryDirectory URLByAppendingPathComponent:name];
    NSDictionary *copyResult = self.commandRunner(@"rclone", @[
        @"copyto", remotePath, temporaryFile.path, @"--no-traverse", @"--retries", @"3"
    ]);
    if ([copyResult[@"status"] integerValue] != 0 || !GDTURLIsSafeRegularFile(temporaryFile)) {
        [self trashTemporaryURL:temporaryDirectory];
        GDTSetRestoreError(error, GDTRestoreErrorCopyFailure, @"The encrypted backup file could not be copied.");
        return nil;
    }

    NSURL *filesList = [temporaryDirectory URLByAppendingPathComponent:
        [@".gdrive-files-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *filesValue = [name stringByAppendingString:@"\n"];
    if (![filesValue writeToURL:filesList atomically:YES encoding:NSUTF8StringEncoding error:&fileError] ||
        ![self.fileManager setAttributes:@{NSFilePosixPermissions: @(0600)}
                            ofItemAtPath:filesList.path error:&fileError]) {
        [self clearPlaintextListAtURL:filesList];
        [self trashTemporaryURL:temporaryDirectory];
        if (error) *error = fileError;
        return nil;
    }
    NSString *remoteParent = [remotePath stringByDeletingLastPathComponent];
    NSDictionary *checkResult = self.commandRunner(@"rclone", @[
        @"cryptcheck", temporaryDirectory.path, remoteParent, @"--one-way",
        @"--files-from-raw", filesList.path
    ]);
    if ([checkResult[@"status"] integerValue] != 0) {
        [self clearPlaintextListAtURL:filesList];
        [self trashTemporaryURL:temporaryDirectory];
        GDTSetRestoreError(error, GDTRestoreErrorIntegrityFailure,
                           @"The restored file did not match the encrypted backup.");
        return nil;
    }
    [self clearPlaintextListAtURL:filesList];
    [self trashTemporaryURL:filesList];
    NSString *digest = [self sha256ForURL:temporaryFile];
    if (!digest.length) {
        [self trashTemporaryURL:temporaryDirectory];
        GDTSetRestoreError(error, GDTRestoreErrorIntegrityFailure,
                           @"The restored file could not be verified.");
        return nil;
    }
    if (![self.fileManager moveItemAtURL:temporaryFile toURL:destination error:&fileError]) {
        [self trashTemporaryURL:temporaryDirectory];
        if (error) *error = fileError;
        return nil;
    }
    [self trashTemporaryURL:temporaryDirectory];
    NSNumber *size = nil;
    [destination getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    return @{ @"destinationURL": destination, @"sha256": digest, @"size": size ?: @0 };
}

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
