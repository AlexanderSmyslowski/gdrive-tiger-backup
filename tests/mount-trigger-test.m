#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface MountTriggerDelegate : AppDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testConfig;
@property(nonatomic) NSInteger launchCalls;
@property(nonatomic, copy) NSString *launchedTrigger;
@property(nonatomic) BOOL launchedAssumeYes;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testVolumeUUIDs;
@end

@implementation MountTriggerDelegate

- (NSDictionary<NSString *, NSString *> *)savedSetupConfig {
    return self.testConfig ?: @{};
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes {
    (void)argument;
    self.launchCalls++;
    self.launchedTrigger = trigger;
    self.launchedAssumeYes = assumeYes;
    return YES;
}

- (void)refreshOverviewStatus:(id)sender {
    (void)sender;
}

- (NSString *)volumeUUIDForPath:(NSString *)path {
    return self.testVolumeUUIDs[path];
}

@end

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSNotification *MountNotification(NSString *path) {
    return [NSNotification notificationWithName:NSWorkspaceDidMountNotification
                                         object:nil
                                       userInfo:@{NSWorkspaceVolumeURLKey: [NSURL fileURLWithPath:path]}];
}

int main(void) {
    @autoreleasepool {
        MountTriggerDelegate *delegate = [[MountTriggerDelegate alloc] init];
        delegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup"
        };

        Assert(![delegate mountedVolumePath:@"/Volumes/Camera" matchesConfig:delegate.testConfig] &&
               [delegate mountedVolumePath:@"/Volumes/GoogleDrive-Backup" matchesConfig:delegate.testConfig],
               @"mount matching accepts only the explicitly saved APFS volume");

        [delegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Camera")];
        Assert(delegate.launchCalls == 0,
               @"unrelated volume mounts never prompt or start a backup");

        [delegate workspaceVolumeDidMount:MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(delegate.launchCalls == 1 &&
               [delegate.launchedTrigger isEqualToString:@"mount"] &&
               !delegate.launchedAssumeYes,
               @"the exact saved target asks once without bypassing confirmation");

        [delegate workspaceVolumeDidMount:MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(delegate.launchCalls == 1,
               @"duplicate mount notifications are debounced");

        MountTriggerDelegate *uuidDelegate = [[MountTriggerDelegate alloc] init];
        uuidDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/NAS",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"EXPECTED-UUID"
        };
        uuidDelegate.testVolumeUUIDs = @{
            @"/Volumes/GoogleDrive-Backup": @"WRONG-UUID",
            @"/Volumes/GoogleDrive-Backup 2": @"expected-uuid"
        };
        Assert(![uuidDelegate mountedVolumePath:@"/Volumes/GoogleDrive-Backup"
                                  matchesConfig:uuidDelegate.testConfig] &&
               [uuidDelegate mountedVolumePath:@"/Volumes/GoogleDrive-Backup 2"
                                  matchesConfig:uuidDelegate.testConfig],
               @"saved UUID selects the intended volume even when macOS changes its mount suffix");
        [uuidDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(uuidDelegate.launchCalls == 0,
               @"a same-name volume with the wrong UUID cannot trigger a backup");
        [uuidDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/GoogleDrive-Backup 2")];
        Assert(uuidDelegate.launchCalls == 1 &&
               [uuidDelegate.launchedTrigger isEqualToString:@"mount"],
               @"the matching UUID triggers the retained external target beside a NAS profile");

        MountTriggerDelegate *nasDelegate = [[MountTriggerDelegate alloc] init];
        nasDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/GoogleDrive-Backup"
        };
        [nasDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(nasDelegate.launchCalls == 0,
               @"NAS schedules are never driven by local APFS mount events");

        MountTriggerDelegate *dualTargetDelegate = [[MountTriggerDelegate alloc] init];
        dualTargetDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/NAS",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup"
        };
        [dualTargetDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/NAS")];
        [dualTargetDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(dualTargetDelegate.launchCalls == 1 &&
               [dualTargetDelegate.launchedTrigger isEqualToString:@"mount"],
               @"an explicitly saved external target remains mount-aware beside a NAS schedule");
    }

    if (failures > 0) {
        printf("%d mount trigger test(s) failed.\n", failures);
        return 1;
    }
    printf("All mount trigger tests passed.\n");
    return 0;
}
