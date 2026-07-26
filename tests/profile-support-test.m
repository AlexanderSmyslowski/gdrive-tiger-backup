#import <Foundation/Foundation.h>

#import "ConfigSupport.h"
#import "ProfileSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSUInteger PermissionsAtPath(NSString *path) {
    NSDictionary *attributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:path error:nil];
    return [attributes[NSFilePosixPermissions] unsignedIntegerValue] & 0777;
}

@interface GDTQuarantineFileManager : NSFileManager
@property(nonatomic, copy) NSString *quarantineRoot;
@end

@implementation GDTQuarantineFileManager
- (BOOL)trashItemAtURL:(NSURL *)url
      resultingItemURL:(NSURL **)outResultingURL
                 error:(NSError **)error {
    if (!self.quarantineRoot.length) {
        self.quarantineRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-profile-test-trash-%@",
                                       NSUUID.UUID.UUIDString]];
    }
    if (![self createDirectoryAtPath:self.quarantineRoot
          withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSURL *destination = [NSURL fileURLWithPath:[self.quarantineRoot
        stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    if (![self moveItemAtURL:url toURL:destination error:error]) {
        return NO;
    }
    if (outResultingURL) {
        *outResultingURL = destination;
    }
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-profile-test-%@", NSUUID.UUID.UUIDString]];
        NSString *legacy = [root stringByAppendingPathComponent:@"config"];
        NSError *error = nil;
        NSDictionary *legacyValues = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Privat",
            @"GDRIVE_BACKUP_NAS_URL": @"smb://user:secret@nas.local/Privat",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_ENCRYPTION": @"none",
            @"RCLONE_REMOTE": @"gdrive"
        };
        BOOL legacyWritten = GDTWriteConfigUpdatesAtPath(legacyValues, legacy, &error);
        NSData *legacyBefore = [NSData dataWithContentsOfFile:legacy];

        GDTQuarantineFileManager *fileManager = [[GDTQuarantineFileManager alloc] init];
        GDTProfileStore *store = [[GDTProfileStore alloc]
            initWithConfigDirectory:root fileManager:fileManager];
        BOOL migrated = [store migrateLegacyConfigAtPath:legacy error:&error];
        NSArray<NSDictionary<NSString *, NSString *> *> *profiles = [store profiles];
        NSString *defaultPath = [store configPathForProfileID:@"default"];
        NSDictionary *defaultConfig = GDTReadConfigDictionaryAtPath(defaultPath);
        Assert(legacyWritten && migrated && !error && profiles.count == 1 &&
               [store.activeProfileID isEqualToString:@"default"] &&
               [profiles.firstObject[@"id"] isEqualToString:@"default"],
               @"first use creates one active default profile");
        Assert([NSData dataWithContentsOfFile:legacy] &&
               [[NSData dataWithContentsOfFile:legacy] isEqualToData:legacyBefore] &&
               [defaultConfig[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"nas"] &&
               [defaultConfig[@"GDRIVE_BACKUP_NAS_URL"] isEqualToString:
                   legacyValues[@"GDRIVE_BACKUP_NAS_URL"]],
               @"legacy migration copies every value without changing the source config");
        Assert(PermissionsAtPath(defaultPath) == 0600 &&
               PermissionsAtPath([root stringByAppendingPathComponent:@"active-profile"]) == 0600,
               @"profile configuration and active selection remain owner-only");

        NSDictionary *created = [store createProfileNamed:@"Externe Platte"
                                            copyingConfig:@{
                                                @"GDRIVE_BACKUP_TARGET": @"apfs",
                                                @"GDRIVE_BACKUP_VOLUME": @"/Volumes/Backup"
                                            }
                                                    error:&error];
        NSString *createdID = created[@"id"];
        Assert(createdID.length > 0 && ![createdID isEqualToString:@"default"] &&
               [[store profiles] count] == 2 &&
               [created[@"name"] isEqualToString:@"Externe Platte"],
               @"a named profile receives a path-safe stable identifier");
        Assert([store selectProfileID:createdID error:&error] &&
               [store.activeProfileID isEqualToString:createdID] &&
               [[store activeConfigPath] isEqualToString:[store configPathForProfileID:createdID]],
               @"profile selection resolves one explicit active config");
        Assert([store renameProfileID:createdID name:@"Archiv 🔒" error:&error] &&
               [[GDTReadConfigDictionaryAtPath([store activeConfigPath])
                   objectForKey:@"GDRIVE_BACKUP_PROFILE_NAME"] isEqualToString:@"Archiv 🔒"],
               @"profile names support Unicode without becoming file names");

        NSError *invalidNameError = nil;
        NSDictionary *invalid = [store createProfileNamed:@"bad\nname"
                                            copyingConfig:@{}
                                                    error:&invalidNameError];
        Assert(!invalid && invalidNameError && [[store profiles] count] == 2,
               @"control characters cannot corrupt the profile store");
        Assert(![store selectProfileID:@"../../outside" error:nil] &&
               ![store configPathForProfileID:@"../../outside"],
               @"profile identifiers cannot traverse outside the private store");

        NSString *outside = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-profile-outside-%@", NSUUID.UUID.UUIDString]];
        [@"GDRIVE_BACKUP_PROFILE_ID='linked'\nGDRIVE_BACKUP_PROFILE_NAME='Linked'\n"
            writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *linked = [[root stringByAppendingPathComponent:@"profiles"]
            stringByAppendingPathComponent:@"linked.conf"];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:linked
                                          withDestinationPath:outside error:nil];
        BOOL linkedVisible = NO;
        for (NSDictionary *profile in [store profiles]) {
            linkedVisible = linkedVisible || [profile[@"id"] isEqualToString:@"linked"];
        }
        Assert(!linkedVisible && ![store selectProfileID:@"linked" error:nil],
               @"symbolic links are never accepted as trusted profile configs");

        NSString *activePointer = [root stringByAppendingPathComponent:@"active-profile"];
        NSString *outsidePointer = [root stringByAppendingPathComponent:@"outside-active"];
        [@"default\n" writeToFile:outsidePointer atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [fileManager trashItemAtURL:[NSURL fileURLWithPath:activePointer]
                   resultingItemURL:nil error:nil];
        [fileManager createSymbolicLinkAtPath:activePointer
                          withDestinationPath:outsidePointer error:nil];
        Assert(store.activeProfileID == nil &&
               ![store selectProfileID:@"default" error:nil],
               @"a symlinked active pointer is rejected instead of followed");
        [fileManager trashItemAtURL:[NSURL fileURLWithPath:activePointer]
                   resultingItemURL:nil error:nil];
        [store selectProfileID:createdID error:nil];

        Assert(![store deleteProfileID:createdID error:nil] &&
               [store selectProfileID:@"default" error:&error] &&
               [store deleteProfileID:createdID error:&error] &&
               [[store profiles] count] == 1 &&
               ![NSFileManager.defaultManager fileExistsAtPath:
                   [store configPathForProfileID:createdID]],
               @"an active profile cannot disappear and inactive deletion is explicit");
        Assert(![store deleteProfileID:@"default" error:nil],
               @"the final profile cannot be deleted");

        NSString *profilesDirectory = [root stringByAppendingPathComponent:@"profiles"];
        NSString *outsideProfiles = [root stringByAppendingPathComponent:@"outside-profiles"];
        [NSFileManager.defaultManager createDirectoryAtPath:outsideProfiles
                                withIntermediateDirectories:YES attributes:nil error:nil];
        GDTWriteConfigUpdatesAtPath(@{
            @"GDRIVE_BACKUP_PROFILE_ID": @"default",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Outside"
        }, [outsideProfiles stringByAppendingPathComponent:@"default.conf"], nil);
        [fileManager trashItemAtURL:[NSURL fileURLWithPath:profilesDirectory]
                   resultingItemURL:nil error:nil];
        [fileManager createSymbolicLinkAtPath:profilesDirectory
                          withDestinationPath:outsideProfiles error:nil];
        Assert(store.profiles.count == 0 && store.activeProfileID == nil,
               @"a symlinked profile directory cannot become a trusted store");

        [fileManager trashItemAtURL:[NSURL fileURLWithPath:root]
                   resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:[NSURL fileURLWithPath:outside]
                   resultingItemURL:nil error:nil];
    }

    if (failures > 0) {
        printf("%d profile support test(s) failed.\n", failures);
        return 1;
    }
    printf("All profile support tests passed.\n");
    return 0;
}
