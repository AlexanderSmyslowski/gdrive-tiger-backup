#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

typedef BOOL (^GDTTestCommandAvailability)(NSString *command);
typedef NSDictionary<NSString *, id> * (^GDTTestCommandRunner)(NSString *command,
                                                                NSArray<NSString *> *arguments);

extern NSString *GDTSetupInstallCommand(BOOL homebrewAvailable, NSArray<NSString *> *missingCommands);
extern NSDictionary<NSString *, NSString *> *GDTGoogleOAuthClientFromJSONData(NSData *data, NSString **reason);
extern NSString *GDTNewestGoogleOAuthClientFile(NSString *directory, NSDate *notBefore,
                                                NSFileManager *fileManager);

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSDictionary<NSString *, id> *Snapshot(
    NSDictionary<NSString *, NSString *> *config,
    GDTTestCommandAvailability availability,
    GDTTestCommandRunner runner,
    NSFileManager *fileManager
) {
    Class checkerClass = NSClassFromString(@"GDTSetupHealthChecker");
    if (!checkerClass) {
        return nil;
    }
    id checker = [[checkerClass alloc] init];
    [checker setValue:[availability copy] forKey:@"commandAvailability"];
    [checker setValue:[runner copy] forKey:@"commandRunner"];
    [checker setValue:fileManager forKey:@"fileManager"];

    SEL selector = NSSelectorFromString(@"snapshotForConfig:");
    if (![checker respondsToSelector:selector]) {
        return nil;
    }
    typedef NSDictionary<NSString *, id> *(*SnapshotMethod)(id, SEL, NSDictionary *);
    SnapshotMethod method = (SnapshotMethod)[checker methodForSelector:selector];
    return method(checker, selector, config);
}

static id ProductionChecker(void) {
    Class checkerClass = NSClassFromString(@"GDTSetupHealthChecker");
    SEL selector = NSSelectorFromString(@"productionChecker");
    if (!checkerClass || ![checkerClass respondsToSelector:selector]) {
        return nil;
    }
    typedef id (*ProductionMethod)(id, SEL);
    ProductionMethod method = (ProductionMethod)[checkerClass methodForSelector:selector];
    return method(checkerClass, selector);
}

static id ProductionCheckerWithTimeout(NSTimeInterval timeout) {
    Class checkerClass = NSClassFromString(@"GDTSetupHealthChecker");
    SEL selector = NSSelectorFromString(@"productionCheckerWithCommandTimeoutForTesting:");
    if (!checkerClass || ![checkerClass respondsToSelector:selector]) {
        return nil;
    }
    typedef id (*ProductionMethod)(id, SEL, NSTimeInterval);
    ProductionMethod method = (ProductionMethod)[checkerClass methodForSelector:selector];
    return method(checkerClass, selector, timeout);
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-setup-health-%@", NSUUID.UUID.UUIDString]];
        [fileManager createDirectoryAtPath:destination
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];

        __block NSMutableArray<NSString *> *commands = [NSMutableArray array];
        NSDictionary<NSString *, id> *snapshot = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                return [@[@"rclone", @"flock", @"jq"] containsObject:command];
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                [commands addObject:[NSString stringWithFormat:@"%@ %@", command,
                                     [arguments componentsJoinedByString:@" "]]];
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{@"status": @0, @"output": @"gdrive:\n"};
                }
                if ([arguments.firstObject isEqualToString:@"about"]) {
                    return @{@"status": @0, @"output": @"{\"total\": 1}"};
                }
                return @{@"status": @64, @"output": @""};
            },
            fileManager
        );

        Assert([snapshot[@"overall"] isEqualToString:@"ready"],
               @"setup is ready only when every health check passes");
        Assert([snapshot[@"dependencies"][@"status"] isEqualToString:@"ready"] &&
               [snapshot[@"remote"][@"status"] isEqualToString:@"ready"] &&
               [snapshot[@"destination"][@"status"] isEqualToString:@"ready"],
               @"ready setup exposes three explicit successful checks");
        Assert(commands.count == 3 &&
               [commands[0] hasSuffix:@"listremotes"] &&
               [commands[1] containsString:@"about gdrive:"] &&
               [commands[2] hasSuffix:@"config show gdrive"],
               @"remote validation lists remotes, tests access, then checks which Google client is used");
        Assert(!snapshot[@"output"] && !snapshot[@"token"] && !snapshot[@"credentials"],
               @"setup health never returns command output or credentials");

        __block NSInteger blockedRunnerCalls = 0;
        NSDictionary<NSString *, id> *missingDependency = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                return ![command isEqualToString:@"jq"];
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                (void)arguments;
                blockedRunnerCalls++;
                return @{@"status": @0, @"output": @""};
            },
            fileManager
        );
        Assert([missingDependency[@"dependencies"][@"status"] isEqualToString:@"failure"] &&
               [missingDependency[@"dependencies"][@"missing"] isEqual:@[@"jq"]],
               @"missing dependency names are explicit and machine-readable");
        NSDictionary<NSString *, id> *withoutFlock = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                return ![command isEqualToString:@"flock"];
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                (void)arguments;
                return @{@"status": @0, @"output": @"gdrive:\n"};
            },
            fileManager
        );
        Assert([withoutFlock[@"dependencies"][@"status"] isEqualToString:@"ready"],
               @"flock is optional because the engine falls back to a perl lock");
        Assert([missingDependency[@"remote"][@"status"] isEqualToString:@"blocked"] &&
               blockedRunnerCalls == 0,
               @"remote access is blocked, not failed, when required tools are missing");

        __block NSInteger missingRemoteRunnerCalls = 0;
        NSDictionary<NSString *, id> *missingRemote = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                missingRemoteRunnerCalls++;
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{@"status": @0, @"output": @"archive:\n"};
                }
                return @{@"status": @0, @"output": @"{}"};
            },
            fileManager
        );
        Assert([missingRemote[@"remote"][@"status"] isEqualToString:@"failure"] &&
               [missingRemote[@"remote"][@"detailKey"] isEqualToString:@"setupCheckRemoteMissing"] &&
               [missingRemote[@"remote"][@"action"] isEqualToString:@"configureRemote"],
               @"missing remote offers one explicit configuration action");
        Assert(missingRemoteRunnerCalls == 1,
               @"missing remote never attempts an authenticated access check");

        NSDictionary<NSString *, id> *unreachableRemote = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{@"status": @0, @"output": @"gdrive:\n"};
                }
                return @{@"status": @1, @"output": @"private provider error"};
            },
            fileManager
        );
        Assert([unreachableRemote[@"remote"][@"detailKey"]
                   isEqualToString:@"setupCheckRemoteUnavailable"] &&
               [unreachableRemote[@"remote"][@"action"] isEqualToString:@"retryRemote"],
               @"unreachable remote offers a retry without exposing provider output");
        Assert(![unreachableRemote.description containsString:@"private provider error"],
               @"provider errors and tokens never enter the health snapshot");

        NSDictionary<NSString *, id> *nasMountReady = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"nas",
                @"GDRIVE_BACKUP_NAS_MOUNT": destination,
                @"GDRIVE_BACKUP_NAS_SUBDIR": @"Folder that does not exist yet",
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                if ([command isEqualToString:@"mount"]) {
                    return @{ @"status": @0, @"output": [NSString stringWithFormat:
                        @"//backup.test/share on %@ (smbfs, nodev, nosuid)\n", destination] };
                }
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            },
            fileManager
        );
        Assert([nasMountReady[@"destination"][@"status"] isEqualToString:@"ready"],
               @"NAS health checks the mounted volume instead of requiring the backup folder");

        NSDictionary<NSString *, id> *plainDirectoryNAS = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"nas",
                @"GDRIVE_BACKUP_NAS_MOUNT": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) { (void)command; return YES; },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                if ([command isEqualToString:@"mount"]) {
                    return @{ @"status": @0, @"output": @"/dev/disk3s5 on /System/Volumes/Data (apfs, local)\n" };
                }
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{ @"status": @0, @"output": @"gdrive:\n" }
                    : @{ @"status": @0, @"output": @"{}" };
            },
            fileManager
        );
        Assert([plainDirectoryNAS[@"destination"][@"status"] isEqualToString:@"failure"],
               @"setup never reports a plain local directory as a ready NAS mount");

        NSDictionary<NSString *, id> *missingDestination = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": @"/path/that/does/not/exist",
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            },
            fileManager
        );
        Assert([missingDestination[@"destination"][@"status"] isEqualToString:@"failure"] &&
               [missingDestination[@"destination"][@"action"] isEqualToString:@"chooseDestination"],
               @"missing destination offers one explicit target-selection action");

        NSString *unencryptedPlist = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
             "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
             "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
             "<plist version=\"1.0\"><dict>"
             "<key>FilesystemType</key><string>apfs</string>"
             "<key>Encryption</key><false/>"
             "<key>Locked</key><false/>"
             "<key>MountPoint</key><string>%@</string>"
             "<key>VolumeUUID</key><string>TEST-UUID</string>"
             "<key>DeviceIdentifier</key><string>disk9s1</string>"
             "</dict></plist>", destination];
        __block NSInteger diskChecks = 0;
        NSDictionary<NSString *, id> *unencryptedTarget = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"apfs",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                if ([command isEqualToString:@"diskutil"]) {
                    diskChecks++;
                    return @{@"status": @0, @"output": unencryptedPlist};
                }
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            },
            fileManager
        );
        Assert(diskChecks == 1 &&
               [unencryptedTarget[@"destination"][@"status"] isEqualToString:@"failure"] &&
               [unencryptedTarget[@"destination"][@"detailKey"]
                   isEqualToString:@"setupCheckEncryptedAPFSRequired"],
               @"encrypted mode rejects a writable but unencrypted APFS destination");

        NSString *encryptedPlist = [unencryptedPlist
            stringByReplacingOccurrencesOfString:@"<key>Encryption</key><false/>"
                                      withString:@"<key>Encryption</key><true/>"];
        NSDictionary<NSString *, id> *encryptedTarget = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"apfs",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) {
                (void)command;
                return YES;
            },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                if ([command isEqualToString:@"diskutil"]) {
                    return @{@"status": @0, @"output": encryptedPlist};
                }
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            },
            fileManager
        );
        Assert([encryptedTarget[@"destination"][@"status"] isEqualToString:@"ready"] &&
               [encryptedTarget[@"destination"][@"detailKey"]
                   isEqualToString:@"setupCheckEncryptedAPFSReady"],
               @"encrypted APFS readiness is explicit instead of implied by writability");

        NSString *validCryptConfig = [NSString stringWithFormat:
            @"[backup-crypt]\n"
             "type = crypt\nremote = %@\npassword = *** ENCRYPTED ***\n"
             "password2 = *** ENCRYPTED ***\nfilename_encryption = standard\n"
             "directory_name_encryption = true\nno_data_encryption = false\nshow_mapping = false\n",
             destination];
        __block NSMutableArray<NSString *> *cryptCommands = [NSMutableArray array];
        NSDictionary<NSString *, id> *cryptReady = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"rclone-crypt",
                @"GDRIVE_BACKUP_CRYPT_REMOTE": @"backup-crypt",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) { (void)command; return YES; },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                [cryptCommands addObject:[NSString stringWithFormat:@"%@ %@", command,
                    [arguments componentsJoinedByString:@" "]]];
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{ @"status": @0, @"output": @"gdrive:\nbackup-crypt:\n" };
                }
                if ([arguments.firstObject isEqualToString:@"about"]) {
                    return @{ @"status": @0, @"output": @"{}" };
                }
                if ([arguments.firstObject isEqualToString:@"config"]) {
                    return @{ @"status": @0, @"output": validCryptConfig };
                }
                return @{ @"status": @64, @"output": @"" };
            },
            fileManager
        );
        Assert([cryptReady[@"overall"] isEqualToString:@"ready"] &&
               [cryptReady[@"destination"][@"detailKey"]
                   isEqualToString:@"setupCheckRcloneCryptReady"] &&
               [cryptCommands containsObject:@"rclone config show backup-crypt"],
               @"setup verifies the exact rclone crypt policy before reporting ready");
        Assert(![cryptReady.description containsString:@"ENCRYPTED"] &&
               !cryptReady[@"password"] && !cryptReady[@"output"],
               @"crypt health snapshots never expose masked or real key material");

        NSDictionary<NSString *, id> *weakCrypt = Snapshot(
            @{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": destination,
                @"GDRIVE_BACKUP_ENCRYPTION": @"rclone-crypt",
                @"GDRIVE_BACKUP_CRYPT_REMOTE": @"backup-crypt",
                @"RCLONE_REMOTE": @"gdrive"
            },
            ^BOOL(NSString *command) { (void)command; return YES; },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{ @"status": @0, @"output": @"gdrive:\nbackup-crypt:\n" };
                }
                if ([arguments.firstObject isEqualToString:@"about"]) {
                    return @{ @"status": @0, @"output": @"{}" };
                }
                return @{ @"status": @0, @"output":
                    [validCryptConfig stringByReplacingOccurrencesOfString:@"no_data_encryption = false"
                                                                withString:@"no_data_encryption = true"] };
            },
            fileManager
        );
        Assert([weakCrypt[@"overall"] isEqualToString:@"failure"] &&
               [weakCrypt[@"destination"][@"detailKey"]
                   isEqualToString:@"setupCheckRcloneCryptInvalid"],
               @"setup fails closed when a crypt remote weakens content encryption");

        NSString *fakeBin = [destination stringByAppendingPathComponent:@"bin"];
        [fileManager createDirectoryAtPath:fakeBin
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
        NSString *fakeCommand = [fakeBin stringByAppendingPathComponent:@"health-probe"];
        NSData *fakeContents = [@"#!/bin/sh\n"
            "if [ \"${1:-}\" = large-output ]; then\n"
            "  exec /usr/bin/awk 'BEGIN { for (i = 0; i < 20000; i++) print \"0123456789abcdef\" }'\n"
            "fi\n"
            "if [ \"${1:-}\" = ignore-term ]; then\n"
            "  trap '' TERM\n"
            "  while :; do /bin/sleep 1; done\n"
            "fi\n"
            "printf 'probe-ok\\n'\n"
            dataUsingEncoding:NSUTF8StringEncoding];
        [fileManager createFileAtPath:fakeCommand
                            contents:fakeContents
                          attributes:@{NSFilePosixPermissions: @0755}];
        NSString *originalPath = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
        setenv("PATH", fakeBin.fileSystemRepresentation, 1);

        id productionChecker = ProductionChecker();
        GDTTestCommandAvailability productionAvailability =
            [productionChecker valueForKey:@"commandAvailability"];
        GDTTestCommandRunner productionRunner =
            [productionChecker valueForKey:@"commandRunner"];
        NSDictionary<NSString *, id> *probeResult = productionRunner
            ? productionRunner(@"health-probe", @[@"literal argument"])
            : nil;
        NSDictionary<NSString *, id> *largeProbeResult = productionRunner
            ? productionRunner(@"health-probe", @[@"large-output"])
            : nil;
        Assert(productionChecker && productionAvailability && productionRunner &&
               productionAvailability(@"health-probe") &&
               !productionAvailability(@"definitely-not-installed"),
               @"production checker resolves only executable commands on PATH");
        Assert([probeResult[@"status"] isEqual:@0] &&
               [probeResult[@"output"] isEqualToString:@"probe-ok\n"],
               @"production runner executes arguments directly and captures bounded output");
        Assert([largeProbeResult[@"status"] isEqual:@0] &&
               [largeProbeResult[@"output"] length] > 300000,
               @"production setup health drains output larger than its pipe without timing out");
        id shortTimeoutChecker = ProductionCheckerWithTimeout(0.1);
        GDTTestCommandRunner shortTimeoutRunner =
            [shortTimeoutChecker valueForKey:@"commandRunner"];
        NSDate *timeoutStarted = NSDate.date;
        NSDictionary<NSString *, id> *ignoredTermResult = shortTimeoutRunner
            ? shortTimeoutRunner(@"health-probe", @[@"ignore-term"])
            : nil;
        NSTimeInterval timeoutElapsed = -[timeoutStarted timeIntervalSinceNow];
        Assert(shortTimeoutChecker &&
               [ignoredTermResult[@"status"] isEqual:@124] &&
               [ignoredTermResult[@"timedOut"] boolValue] &&
               timeoutElapsed < 5.0,
               @"production setup health stays bounded when a command ignores TERM");
        setenv("PATH", originalPath.fileSystemRepresentation, 1);

        [fileManager removeItemAtURL:[NSURL fileURLWithPath:destination] error:nil];
    }

    Assert([GDTSetupInstallCommand(YES, @[@"rclone"]) isEqualToString:@"brew install rclone"] &&
           [GDTSetupInstallCommand(YES, @[@"jq", @"rclone", @"rm -rf /"]) isEqualToString:@"brew install jq rclone"],
           @"install command lists only the missing known tools");
    NSString *withHomebrew = GDTSetupInstallCommand(NO, @[@"jq"]);
    Assert([withHomebrew hasPrefix:@"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""] &&
           [withHomebrew hasSuffix:@"&& brew install jq"],
           @"install command installs Homebrew first when it is missing");

    // --- Own Google OAuth client instead of rclone's retiring shared one ---
    NSString *clientID = @"422579661830-d9fubsqauhu020p2mk2dftkivptr244l.apps.googleusercontent.com";
    NSString *clientSecret = @"GOCSPX-test_Secret-123";
    NSData *(^ClientJSON)(NSString *, NSString *, NSString *) =
        ^NSData *(NSString *type, NSString *identifier, NSString *secret) {
            return [NSJSONSerialization dataWithJSONObject:@{type: @{
                @"client_id": identifier, @"client_secret": secret,
                @"project_id": @"tiger-backup"}} options:0 error:nil];
        };
    NSString *reason = nil;
    NSDictionary *parsed = GDTGoogleOAuthClientFromJSONData(
        ClientJSON(@"installed", clientID, clientSecret), &reason);
    Assert([parsed[@"clientID"] isEqualToString:clientID] &&
           [parsed[@"clientSecret"] isEqualToString:clientSecret] && reason == nil,
           @"a downloaded Desktop client file yields its id and secret");
    Assert(!GDTGoogleOAuthClientFromJSONData(ClientJSON(@"web", clientID, clientSecret), &reason) &&
           [reason isEqualToString:@"notDesktop"],
           @"a web client is rejected with a hint to choose Desktop app");
    Assert(!GDTGoogleOAuthClientFromJSONData([@"not json" dataUsingEncoding:NSUTF8StringEncoding], &reason) &&
           [reason isEqualToString:@"invalid"] &&
           !GDTGoogleOAuthClientFromJSONData(ClientJSON(@"installed", clientID, @"secret\nscope=drive"), nil) &&
           !GDTGoogleOAuthClientFromJSONData(ClientJSON(@"installed", @"evil client_id=x", clientSecret), nil),
           @"malformed files and values that could smuggle rclone options are rejected");

    NSString *downloads = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"gdrive-client-downloads-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:downloads withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    NSDate *assistantOpened = [NSDate date];
    NSString *oldFile = [downloads stringByAppendingPathComponent:@"client_secret_old.apps.googleusercontent.com.json"];
    NSString *newFile = [downloads stringByAppendingPathComponent:@"client_secret_new.apps.googleusercontent.com.json"];
    NSString *otherFile = [downloads stringByAppendingPathComponent:@"report.json"];
    for (NSString *path in @[oldFile, newFile, otherFile]) {
        [ClientJSON(@"installed", clientID, clientSecret) writeToFile:path atomically:YES];
    }
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:
        [assistantOpened dateByAddingTimeInterval:-3600]} ofItemAtPath:oldFile error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:
        [assistantOpened dateByAddingTimeInterval:60]} ofItemAtPath:otherFile error:nil];
    Assert([GDTNewestGoogleOAuthClientFile(downloads, assistantOpened, NSFileManager.defaultManager)
               isEqualToString:newFile],
           @"only a client file downloaded after the assistant opened is picked up");
    [NSFileManager.defaultManager removeItemAtPath:newFile error:nil];
    Assert(GDTNewestGoogleOAuthClientFile(downloads, assistantOpened, NSFileManager.defaultManager) == nil,
           @"an old client file in Downloads is never used silently");
    [NSFileManager.defaultManager removeItemAtPath:downloads error:nil];

    NSString *healthVolume = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"gdrive-shared-client-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:healthVolume withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    NSDictionary *healthConfig = @{@"GDRIVE_BACKUP_TARGET": @"apfs",
                                   @"GDRIVE_BACKUP_VOLUME": healthVolume,
                                   @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                                   @"RCLONE_REMOTE": @"gdrive"};
    NSDictionary *(^RemoteRow)(NSString *, NSInteger) = ^NSDictionary *(NSString *section, NSInteger aboutStatus) {
        return Snapshot(healthConfig, ^BOOL(NSString *command) { (void)command; return YES; },
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{@"status": @0, @"output": @"gdrive:\n"};
                }
                if ([arguments.firstObject isEqualToString:@"about"]) {
                    return @{@"status": @(aboutStatus), @"output": @"{}"};
                }
                if ([arguments isEqualToArray:@[@"config", @"show", @"gdrive"]]) {
                    return @{@"status": @0, @"output": section};
                }
                return @{@"status": @1, @"output": @""};
            }, NSFileManager.defaultManager)[@"remote"];
    };
    NSDictionary *sharedReady = RemoteRow(@"[gdrive]\ntype = drive\nscope = drive.readonly\nclient_id = \ntoken = {\"x\":1}\n", 0);
    Assert([sharedReady[@"status"] isEqualToString:@"ready"] &&
           [sharedReady[@"detailKey"] isEqualToString:@"setupCheckRemoteSharedClient"] &&
           [sharedReady[@"action"] isEqualToString:@"useOwnGoogleClient"],
           @"a working remote on rclone's shared client stays ready but offers the own-client setup");
    NSDictionary *sharedBroken = RemoteRow(@"[gdrive]\ntype = drive\nscope = drive.readonly\n", 1);
    Assert([sharedBroken[@"status"] isEqualToString:@"failure"] &&
           [sharedBroken[@"detailKey"] isEqualToString:@"setupCheckRemoteSharedClientFailed"] &&
           [sharedBroken[@"action"] isEqualToString:@"useOwnGoogleClient"],
           @"an unreachable remote on the shared client points to the own-client setup");
    NSDictionary *ownClient = RemoteRow([NSString stringWithFormat:
        @"[gdrive]\ntype = drive\nclient_id = %@\nclient_secret = s\n", clientID], 0);
    Assert([ownClient[@"detailKey"] isEqualToString:@"setupCheckRemoteReady"] && !ownClient[@"action"] &&
           ![ownClient.description containsString:clientID],
           @"a remote with its own client is simply ready and no config value enters the snapshot");
    [NSFileManager.defaultManager removeItemAtPath:healthVolume error:nil];

    Class checkerClass = NSClassFromString(@"GDTSetupHealthChecker");
    SEL connectSelector = NSSelectorFromString(@"connectGoogleDriveForConfig:clientID:clientSecret:");
    typedef NSDictionary *(*ConnectMethod)(id, SEL, NSDictionary *, NSString *, NSString *);
    NSString *lockPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"gdrive-backup-%@.lock", NSUUID.UUID.UUIDString]];
    NSString *clientArgument = [@"client_id=" stringByAppendingString:clientID];
    NSString *secretArgument = [@"client_secret=" stringByAppendingString:clientSecret];
    // Fake rclone: records every call; `remotes` is the listremotes output.
    NSDictionary *(^Connect)(NSString *, NSInteger, NSMutableArray *, NSString *) =
        ^NSDictionary *(NSString *remotes, NSInteger signInStatus, NSMutableArray *calls, NSString *clientValue) {
            id connector = [[checkerClass alloc] init];
            GDTTestCommandRunner runner = ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                [calls addObject:[@[command] arrayByAddingObjectsFromArray:arguments]];
                if ([arguments.firstObject isEqualToString:@"listremotes"]) {
                    return @{@"status": @0, @"output": remotes};
                }
                if ([arguments isEqualToArray:@[@"config", @"dump"]]) {
                    return @{@"status": @0, @"output":
                        @"{\"gdrive\":{\"type\":\"drive\"},\"gdrive-tiger-new\":{\"type\":\"drive\",\"token\":\"{\\\"refresh_token\\\":\\\"new\\\"}\"}}"};
                }
                return @{@"status": @0, @"output": @"{}"};
            };
            [connector setValue:runner forKey:@"commandRunner"];
            [connector setValue:^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                [calls addObject:[@[@"interactive", command] arrayByAddingObjectsFromArray:arguments]];
                return @{@"status": @(signInStatus), @"output": @""};
            } forKey:@"interactiveCommandRunner"];
            [connector setValue:lockPath forKey:@"backupLockPath"];
            ConnectMethod connect = (ConnectMethod)[connector methodForSelector:connectSelector];
            return connect(connector, connectSelector, @{@"RCLONE_REMOTE": @"gdrive:"}, clientValue, clientSecret);
        };
    BOOL (^Updated)(NSArray *) = ^BOOL(NSArray *calls) {
        for (NSArray *call in calls) {
            if ([call containsObject:@"update"]) return YES;
        }
        return NO;
    };

    NSMutableArray *calls = [NSMutableArray array];
    NSDictionary *result = Connect(@"archive:\n", 0, calls, clientID);
    Assert([result[@"reason"] isEqualToString:@"connected"] &&
           [calls.lastObject isEqualToArray:@[@"interactive", @"rclone", @"config", @"create", @"gdrive",
               @"drive", clientArgument, secretArgument, @"scope=drive.readonly"]],
           @"a first connection creates the read-only remote with the user's own client");

    calls = [NSMutableArray array];
    result = Connect(@"gdrive:\n", 0, calls, clientID);
    NSArray *update = nil;
    for (NSArray *call in calls) {
        if ([call containsObject:@"update"]) update = call;
    }
    Assert([result[@"reason"] isEqualToString:@"connected"] &&
           [calls containsObject:@[@"interactive", @"rclone", @"config", @"create", @"gdrive-tiger-new",
               @"drive", clientArgument, secretArgument, @"scope=drive.readonly"]] &&
           [calls containsObject:@[@"rclone", @"about", @"gdrive-tiger-new:", @"--json"]] &&
           [update isEqualToArray:@[@"rclone", @"config", @"update", @"gdrive", clientArgument,
               secretArgument, @"scope=drive.readonly", @"token={\"refresh_token\":\"new\"}",
               @"config_refresh_token=false", @"--non-interactive"]] &&
           [calls.lastObject isEqualToArray:@[@"rclone", @"config", @"delete", @"gdrive-tiger-new"]],
           @"an existing remote switches only after a temporary remote signed in and read Drive");

    calls = [NSMutableArray array];
    result = Connect(@"gdrive:\n", 1, calls, clientID);
    Assert([result[@"reason"] isEqualToString:@"signInFailed"] && !Updated(calls) &&
           [calls.lastObject isEqualToArray:@[@"rclone", @"config", @"delete", @"gdrive-tiger-new"]],
           @"a cancelled sign-in leaves the existing remote untouched and cleans up");

    int heldLock = open(lockPath.fileSystemRepresentation, O_RDWR | O_CREAT, 0600);
    flock(heldLock, LOCK_EX);
    calls = [NSMutableArray array];
    result = Connect(@"gdrive:\n", 0, calls, clientID);
    Assert([result[@"reason"] isEqualToString:@"backupRunning"] && !Updated(calls) &&
           [calls.lastObject isEqualToArray:@[@"rclone", @"config", @"delete", @"gdrive-tiger-new"]],
           @"a running backup blocks the switch so it cannot write an old token back");
    flock(heldLock, LOCK_UN);
    close(heldLock);
    unlink(lockPath.fileSystemRepresentation);

    calls = [NSMutableArray array];
    result = Connect(@"gdrive:\n", 0, calls, @"not-a-client id");
    Assert([result[@"reason"] isEqualToString:@"invalidClient"] && calls.count == 0,
           @"an invalid client never reaches rclone");

    if (failures > 0) {
        printf("%d setup health test(s) failed.\n", failures);
        return 1;
    }
    printf("All setup health tests passed.\n");
    return 0;
}
