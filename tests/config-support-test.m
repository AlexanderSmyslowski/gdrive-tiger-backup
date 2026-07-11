#import <Foundation/Foundation.h>

#import "../macos/GDriveBackupTiger/ConfigSupport.h"

static void AssertEqual(NSString *actual, NSString *expected, NSString *message) {
    if (![actual isEqualToString:expected]) {
        NSLog(@"FAIL: %@\nexpected: <%@>\nactual:   <%@>", message, expected, actual);
        exit(1);
    }
}

static NSString *RunBashAndReadValue(NSString *configPath, NSString *key) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", @"source \"$1\"; printf '%s' \"${!2}\"", @"config-test", configPath, key];

    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSPipe pipe];
    [task launch];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSLog(@"FAIL: generated config could not be sourced by bash");
        exit(1);
    }

    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

int main(void) {
    @autoreleasepool {
        NSString *overridePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gdrive-config-override"];
        setenv("GDRIVE_BACKUP_CONFIG", overridePath.UTF8String, 1);
        AssertEqual(GDTConfigPath(), overridePath,
                    @"the app must honor the same config override as the backup engine");
        unsetenv("GDRIVE_BACKUP_CONFIG");

        NSString *profileRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-config-profile-%@", NSUUID.UUID.UUIDString]];
        NSString *profileDirectory = [profileRoot stringByAppendingPathComponent:@"profiles"];
        [NSFileManager.defaultManager createDirectoryAtPath:profileDirectory
                                withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *legacyProfileConfig = [profileRoot stringByAppendingPathComponent:@"config"];
        NSString *activeProfileConfig = [profileDirectory stringByAppendingPathComponent:@"default.conf"];
        GDTWriteConfigUpdatesAtPath(@{@"GDRIVE_BACKUP_TARGET": @"nas"},
                                    legacyProfileConfig, nil);
        GDTWriteConfigUpdatesAtPath(@{
            @"GDRIVE_BACKUP_PROFILE_ID": @"default",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Default",
            @"GDRIVE_BACKUP_TARGET": @"apfs"
        }, activeProfileConfig, nil);
        [[NSString stringWithFormat:@"default\n"] writeToFile:
            [profileRoot stringByAppendingPathComponent:@"active-profile"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AssertEqual(GDTConfigPathForConfigDirectory(profileRoot), activeProfileConfig,
                    @"the app resolves the selected trusted profile config");
        [@"../../outside\n" writeToFile:
            [profileRoot stringByAppendingPathComponent:@"active-profile"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AssertEqual(GDTConfigPathForConfigDirectory(profileRoot), legacyProfileConfig,
                    @"an unsafe active profile pointer falls back to the legacy config");
        NSString *outsideActivePointer = [profileRoot stringByAppendingPathComponent:@"outside-active"];
        [@"default\n" writeToFile:outsideActivePointer atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        NSString *activePointer = [profileRoot stringByAppendingPathComponent:@"active-profile"];
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:activePointer]
                                    resultingItemURL:nil error:nil];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:activePointer
                                          withDestinationPath:outsideActivePointer error:nil];
        AssertEqual(GDTConfigPathForConfigDirectory(profileRoot), legacyProfileConfig,
                    @"a symlinked active profile pointer is never trusted");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:activePointer]
                                    resultingItemURL:nil error:nil];
        [@"default\n" writeToFile:activePointer atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        NSString *outsideProfiles = [profileRoot stringByAppendingPathComponent:@"outside-profiles"];
        [NSFileManager.defaultManager createDirectoryAtPath:outsideProfiles
                                withIntermediateDirectories:YES attributes:nil error:nil];
        GDTWriteConfigUpdatesAtPath(@{
            @"GDRIVE_BACKUP_PROFILE_ID": @"default",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Default"
        }, [outsideProfiles stringByAppendingPathComponent:@"default.conf"], nil);
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:profileDirectory]
                                    resultingItemURL:nil error:nil];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:profileDirectory
                                          withDestinationPath:outsideProfiles error:nil];
        AssertEqual(GDTConfigPathForConfigDirectory(profileRoot), legacyProfileConfig,
                    @"a symlinked profile directory is never trusted");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:profileRoot]
                                    resultingItemURL:nil error:nil];

        NSString *roundTripValue = @"Client's \\Archive\\2026 $(untouched)";
        NSString *quoted = GDTShellQuote(roundTripValue);
        AssertEqual(quoted,
                    @"'Client'\\''s \\Archive\\2026 $(untouched)'",
                    @"shell quoting must protect apostrophes without changing backslashes");
        AssertEqual(GDTDecodeConfigValue(quoted), roundTripValue,
                    @"the reader must reverse the writer's shell quoting");

        AssertEqual(GDTDecodeConfigValue(@"legacy\\ value\\\\path\\'s"),
                    @"legacy value\\path's",
                    @"the reader must support values emitted by bash printf %q");
        AssertEqual(GDTDecodeConfigValue(@"$'Fran\\303\\247ais/\\346\\227\\245\\346\\234\\254\\350\\252\\236'"),
                    @"Français/日本語",
                    @"ANSI-C octal escapes must be decoded as UTF-8 bytes");
        AssertEqual(GDTDecodeConfigValue(@"folder\\ "), @"folder ",
                    @"escaped trailing spaces must survive legacy printf %q decoding");
        AssertEqual(GDTDecodeConfigValue(@"$'line\\nnext'"), @"line\nnext",
                    @"the reader must support bash ANSI-C quoting");

        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *path = [directory stringByAppendingPathComponent:@"nested/config"];
        NSError *error = nil;
        NSDictionary<NSString *, NSString *> *updates = @{
            @"GDRIVE_BACKUP_NAS_SUBDIR": roundTripValue,
            @"GDRIVE_BACKUP_NAS_URL": @"smb://guest:p'a\\ss@nas.local/Backups",
            @"GDRIVE_BACKUP_RETENTION": @"1",
            @"GDRIVE_BACKUP_ENCRYPTION": @"apfs"
        };
        if (!GDTWriteConfigUpdatesAtPath(updates, path, &error)) {
            NSLog(@"FAIL: could not write config: %@", error);
            return 1;
        }

        NSDictionary<NSString *, NSString *> *readBack = GDTReadConfigDictionaryAtPath(path);
        AssertEqual(readBack[@"GDRIVE_BACKUP_NAS_SUBDIR"], roundTripValue,
                    @"written subdirectory must survive an app readback");
        AssertEqual(readBack[@"GDRIVE_BACKUP_NAS_URL"], updates[@"GDRIVE_BACKUP_NAS_URL"],
                    @"written URL must survive an app readback");
        AssertEqual(RunBashAndReadValue(path, @"GDRIVE_BACKUP_NAS_SUBDIR"), roundTripValue,
                    @"written values must retain their value when sourced by the backup script");
        AssertEqual(readBack[@"GDRIVE_BACKUP_ENCRYPTION"], @"apfs",
                    @"the encryption policy must survive an app readback");
        AssertEqual(RunBashAndReadValue(path, @"GDRIVE_BACKUP_ENCRYPTION"), @"apfs",
                    @"the encryption policy must retain its value in the backup script");
        AssertEqual(readBack[@"GDRIVE_BACKUP_RETENTION"], @"1",
                    @"the retention policy must survive an app readback");

        NSNumber *permissions = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];
        if ((permissions.unsignedShortValue & 0777) != 0600) {
            NSLog(@"FAIL: app-written config must use mode 0600");
            return 1;
        }

        NSError *invalidError = nil;
        if (GDTWriteConfigUpdatesAtPath(@{@"GDRIVE_BACKUP_NAS_SUBDIR": @"line one\nline two"},
                                        path,
                                        &invalidError) || !invalidError) {
            NSLog(@"FAIL: multiline values must be rejected before they corrupt the line-based config");
            return 1;
        }

        NSString *invalidPath = [directory stringByAppendingPathComponent:@"invalid-utf8-config"];
        const unsigned char invalidBytes[] = "RCLONE_REMOTE=gdrive\n\xff";
        NSData *invalidConfig = [NSData dataWithBytes:invalidBytes length:sizeof(invalidBytes) - 1];
        if (![invalidConfig writeToFile:invalidPath atomically:YES]) {
            NSLog(@"FAIL: could not create invalid UTF-8 fixture");
            return 1;
        }
        NSError *readError = nil;
        if (GDTWriteConfigUpdatesAtPath(@{@"GDRIVE_BACKUP_LANG": @"de"}, invalidPath, &readError) || !readError) {
            NSLog(@"FAIL: unreadable existing config must not be replaced");
            return 1;
        }
        if (![[NSData dataWithContentsOfFile:invalidPath] isEqualToData:invalidConfig]) {
            NSLog(@"FAIL: failed config update changed the unreadable source file");
            return 1;
        }

        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:directory]
                                    resultingItemURL:nil
                                               error:nil];

        NSLog(@"PASS: ConfigSupport quoting and read/write roundtrips");
    }
    return 0;
}
