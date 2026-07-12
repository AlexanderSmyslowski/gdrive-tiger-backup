#import "SetupHealthSupport.h"

static NSDictionary<NSString *, id> *GDTSetupRow(NSString *status,
                                                  NSString *detailKey,
                                                  NSDictionary<NSString *, id> *extra) {
    NSMutableDictionary<NSString *, id> *row = [@{
        @"status": status,
        @"detailKey": detailKey
    } mutableCopy];
    if (extra) {
        [row addEntriesFromDictionary:extra];
    }
    return row;
}

static NSString *GDTNormalizedRemote(NSString *remote) {
    NSString *normalized = [remote ?: @"gdrive"
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([normalized hasSuffix:@":"]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    return normalized.length ? normalized : @"gdrive";
}

static BOOL GDTEncryptedAPFSDestinationIsValid(NSDictionary<NSString *, id> *result,
                                               NSString *destinationPath) {
    if ([result[@"status"] integerValue] != 0 ||
        ![result[@"output"] isKindOfClass:NSString.class]) {
        return NO;
    }
    NSData *data = [result[@"output"] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary<NSString *, id> *plist = [NSPropertyListSerialization
        propertyListWithData:data ?: NSData.data
                     options:NSPropertyListImmutable
                      format:nil
                       error:nil];
    if (![plist isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSString *configured = destinationPath.stringByStandardizingPath;
    NSString *mountPoint = [plist[@"MountPoint"] isKindOfClass:NSString.class]
        ? [plist[@"MountPoint"] stringByStandardizingPath]
        : @"";
    if ([NSFileManager.defaultManager fileExistsAtPath:configured]) {
        configured = configured.stringByResolvingSymlinksInPath;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:mountPoint]) {
        mountPoint = mountPoint.stringByResolvingSymlinksInPath;
    }

    return [plist[@"FilesystemType"] isEqual:@"apfs"] &&
        [plist[@"Encryption"] boolValue] &&
        ![plist[@"Locked"] boolValue] &&
        [mountPoint isEqualToString:configured] &&
        [plist[@"VolumeUUID"] isKindOfClass:NSString.class] &&
        [plist[@"VolumeUUID"] length] > 0 &&
        [plist[@"DeviceIdentifier"] isKindOfClass:NSString.class] &&
        [plist[@"DeviceIdentifier"] length] > 0;
}

static BOOL GDTSetupRemoteNameIsSafe(NSString *remoteName) {
    if (!remoteName.length || remoteName.length > 64) return NO;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
                             options:0 error:nil];
    return [expression numberOfMatchesInString:remoteName options:0
                                          range:NSMakeRange(0, remoteName.length)] == 1;
}

static BOOL GDTRcloneCryptConfigIsValid(NSDictionary<NSString *, id> *result,
                                        NSString *remoteName,
                                        NSString *destinationPath) {
    if ([result[@"status"] integerValue] != 0 ||
        ![result[@"output"] isKindOfClass:NSString.class] ||
        [result[@"output"] length] > 64 * 1024 ||
        !GDTSetupRemoteNameIsSafe(remoteName) || !destinationPath.length) {
        return NO;
    }
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    BOOL sawExpectedSection = NO;
    for (NSString *rawLine in [result[@"output"]
            componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@";"]) continue;
        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            NSString *section = [line substringWithRange:NSMakeRange(1, line.length - 2)];
            if (sawExpectedSection || ![section isEqualToString:remoteName]) return NO;
            sawExpectedSection = YES;
            continue;
        }
        NSRange separator = [line rangeOfString:@"="];
        if (!sawExpectedSection || separator.location == NSNotFound) return NO;
        NSString *key = [[line substringToIndex:separator.location]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[line substringFromIndex:NSMaxRange(separator)]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!key.length || values[key]) return NO;
        values[key] = value ?: @"";
    }
    NSString *configuredRoot = [values[@"remote"] stringByStandardizingPath];
    NSString *expectedRoot = destinationPath.stringByStandardizingPath;
    if ([NSFileManager.defaultManager fileExistsAtPath:configuredRoot]) {
        configuredRoot = configuredRoot.stringByResolvingSymlinksInPath;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:expectedRoot]) {
        expectedRoot = expectedRoot.stringByResolvingSymlinksInPath;
    }
    return sawExpectedSection && [values[@"type"] isEqualToString:@"crypt"] &&
        [configuredRoot isEqualToString:expectedRoot] && values[@"password"].length > 0 &&
        values[@"password2"].length > 0 &&
        [[values[@"filename_encryption"] lowercaseString] isEqualToString:@"standard"] &&
        [[values[@"directory_name_encryption"] lowercaseString] isEqualToString:@"true"] &&
        [[values[@"no_data_encryption"] lowercaseString] isEqualToString:@"false"] &&
        [[values[@"show_mapping"] lowercaseString] isEqualToString:@"false"];
}

static NSString *GDTExecutablePath(NSString *command) {
    if (!command.length ||
        [command rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    if ([command containsString:@"/"]) {
        return [NSFileManager.defaultManager isExecutableFileAtPath:command] ? command : nil;
    }

    NSMutableOrderedSet<NSString *> *directories = [NSMutableOrderedSet orderedSet];
    const char *pathValue = getenv("PATH");
    if (pathValue) {
        NSString *path = [NSString stringWithUTF8String:pathValue] ?: @"";
        for (NSString *directory in [path componentsSeparatedByString:@":"]) {
            if (directory.length) {
                [directories addObject:directory];
            }
        }
    }
    [directories addObjectsFromArray:@[
        @"/opt/homebrew/bin", @"/usr/local/bin", @"/usr/bin",
        @"/bin", @"/usr/sbin", @"/sbin"
    ]];
    for (NSString *directory in directories) {
        NSString *candidate = [directory stringByAppendingPathComponent:command];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *GDTRunSetupCommand(NSString *command,
                                                         NSArray<NSString *> *arguments) {
    NSString *launchPath = GDTExecutablePath(command);
    if (!launchPath.length) {
        return @{@"status": @127, @"output": @"", @"timedOut": @NO};
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments ?: @[];
    NSPipe *outputPipe = NSPipe.pipe;
    task.standardOutput = outputPipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;

    @try {
        [task launch];
    } @catch (NSException *exception) {
        (void)exception;
        return @{@"status": @127, @"output": @"", @"timedOut": @NO};
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
    while (task.running && [deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.05];
    }
    BOOL timedOut = task.running;
    if (timedOut) {
        [task terminate];
    }
    [task waitUntilExit];

    NSData *outputData = [outputPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:outputData
                                             encoding:NSUTF8StringEncoding] ?: @"";
    return @{
        @"status": timedOut ? @124 : @(task.terminationStatus),
        @"output": output,
        @"timedOut": @(timedOut)
    };
}

@implementation GDTSetupHealthChecker

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = NSFileManager.defaultManager;
    }
    return self;
}

+ (instancetype)productionChecker {
    GDTSetupHealthChecker *checker = [[self alloc] init];
    checker.commandAvailability = ^BOOL(NSString *command) {
        return GDTExecutablePath(command).length > 0;
    };
    checker.commandRunner = ^NSDictionary<NSString *, id> *(NSString *command,
                                                             NSArray<NSString *> *arguments) {
        return GDTRunSetupCommand(command, arguments);
    };
    return checker;
}

- (NSDictionary<NSString *, id> *)snapshotForConfig:(NSDictionary<NSString *, NSString *> *)config {
    NSArray<NSString *> *requiredCommands = @[@"rclone", @"flock", @"jq"];
    NSMutableArray<NSString *> *missingCommands = [NSMutableArray array];
    for (NSString *command in requiredCommands) {
        if (!self.commandAvailability || !self.commandAvailability(command)) {
            [missingCommands addObject:command];
        }
    }

    NSDictionary<NSString *, id> *dependencies = missingCommands.count
        ? GDTSetupRow(@"failure", @"setupCheckDependenciesMissing", @{@"missing": missingCommands})
        : GDTSetupRow(@"ready", @"setupCheckDependenciesReady", @{});

    NSString *remoteName = GDTNormalizedRemote(config[@"RCLONE_REMOTE"]);
    NSDictionary<NSString *, id> *remote = nil;
    if (missingCommands.count || !self.commandRunner) {
        remote = GDTSetupRow(@"blocked", @"setupCheckRemoteBlocked", @{});
    } else {
        NSDictionary<NSString *, id> *listed = self.commandRunner(@"rclone", @[@"listremotes"]);
        NSString *configured = [listed[@"output"] isKindOfClass:NSString.class] ? listed[@"output"] : @"";
        NSString *expectedLine = [remoteName stringByAppendingString:@":"];
        BOOL found = NO;
        for (NSString *line in [configured componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            if ([line isEqualToString:expectedLine]) {
                found = YES;
                break;
            }
        }

        if ([listed[@"status"] integerValue] != 0 || !found) {
            remote = GDTSetupRow(@"failure", @"setupCheckRemoteMissing",
                                 @{@"action": @"configureRemote"});
        } else {
            NSDictionary<NSString *, id> *access = self.commandRunner(
                @"rclone",
                @[@"about", expectedLine, @"--json"]
            );
            remote = [access[@"status"] integerValue] == 0
                ? GDTSetupRow(@"ready", @"setupCheckRemoteReady", @{})
                : GDTSetupRow(@"failure", @"setupCheckRemoteUnavailable",
                              @{@"action": @"retryRemote"});
        }
    }

    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    NSString *destinationPath = [target isEqualToString:@"nas"]
        ? config[@"GDRIVE_BACKUP_NAS_MOUNT"]
        : config[@"GDRIVE_BACKUP_VOLUME"];
    BOOL isDirectory = NO;
    BOOL exists = destinationPath.length &&
        [self.fileManager fileExistsAtPath:destinationPath isDirectory:&isDirectory];
    BOOL accessible = exists && isDirectory &&
        [self.fileManager isReadableFileAtPath:destinationPath] &&
        [self.fileManager isWritableFileAtPath:destinationPath];
    NSDictionary<NSString *, id> *destination = accessible
        ? GDTSetupRow(@"ready", @"setupCheckDestinationReady", @{})
        : GDTSetupRow(@"failure", @"setupCheckDestinationUnavailable",
                      @{@"action": @"chooseDestination"});
    NSString *encryption = [config[@"GDRIVE_BACKUP_ENCRYPTION"] ?: @"none" lowercaseString];
    if ([encryption isEqualToString:@"apfs"]) {
        BOOL encryptedTargetReady = [target isEqualToString:@"apfs"] && accessible && self.commandRunner &&
            GDTEncryptedAPFSDestinationIsValid(
                self.commandRunner(@"diskutil", @[@"info", @"-plist", destinationPath]),
                destinationPath
            );
        if (!encryptedTargetReady) {
            destination = GDTSetupRow(@"failure", @"setupCheckEncryptedAPFSRequired",
                                      @{@"action": @"chooseDestination"});
        } else {
            destination = GDTSetupRow(@"ready", @"setupCheckEncryptedAPFSReady", @{});
        }
    } else if ([encryption isEqualToString:@"rclone-crypt"]) {
        NSString *cryptRemote = config[@"GDRIVE_BACKUP_CRYPT_REMOTE"] ?: @"";
        NSString *cryptDestination = destinationPath ?: @"";
        if ([target isEqualToString:@"nas"] && cryptDestination.length) {
            NSString *subdirectory = config[@"GDRIVE_BACKUP_NAS_SUBDIR"].length
                ? config[@"GDRIVE_BACKUP_NAS_SUBDIR"] : @"GoogleDrive-Backup";
            cryptDestination = [cryptDestination stringByAppendingPathComponent:subdirectory];
        }
        BOOL cryptReady = accessible && self.commandRunner &&
            GDTSetupRemoteNameIsSafe(cryptRemote) &&
            GDTRcloneCryptConfigIsValid(
                self.commandRunner(@"rclone", @[@"config", @"show", cryptRemote]),
                cryptRemote,
                cryptDestination
            );
        destination = cryptReady
            ? GDTSetupRow(@"ready", @"setupCheckRcloneCryptReady", @{})
            : GDTSetupRow(@"failure", @"setupCheckRcloneCryptInvalid",
                          @{@"action": @"configureEncryption"});
    }

    BOOL ready = [dependencies[@"status"] isEqualToString:@"ready"] &&
        [remote[@"status"] isEqualToString:@"ready"] &&
        [destination[@"status"] isEqualToString:@"ready"];
    return @{
        @"overall": ready ? @"ready" : @"failure",
        @"dependencies": dependencies,
        @"remote": remote,
        @"destination": destination
    };
}

@end
