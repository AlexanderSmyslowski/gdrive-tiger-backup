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
@property(nonatomic, copy) NSDictionary<NSString *, NSDictionary<NSString *, id> *> *testVolumeDescriptors;
@property(nonatomic) NSInteger unknownVolumeNoticeCalls;
@property(nonatomic, copy) NSDictionary<NSString *, id> *lastUnknownVolumeDescriptor;
@property(nonatomic) NSInteger setupWindowCalls;
@property(nonatomic) NSInteger overviewWindowCalls;
@property(nonatomic) NSInteger unknownVolumeNoticeRemovalCalls;
@property(nonatomic, copy) NSString *lastRemovedUnknownDiskID;
@property(nonatomic, copy) NSString *lastRemovedUnknownVolumeUUID;
@property(nonatomic, copy) NSArray<NSString *> *testMountedVolumePaths;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testDeliveredUnknownVolumeUUIDsByDiskID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSSet<NSString *> *> *
    testRememberedAttachmentUUIDsByDiskID;
@end

@interface DelayedMountTriggerDelegate : MountTriggerDelegate
@property(nonatomic, copy) NSString *pendingInspectionPath;
@property(nonatomic, copy) void (^pendingInspectionCompletion)(
    NSDictionary<NSString *, id> *descriptor);
- (void)completePendingInspectionWithDescriptor:
    (NSDictionary<NSString *, id> *)descriptor;
@end

@interface BatchDelayedMountTriggerDelegate : MountTriggerDelegate
@property(nonatomic, strong) NSMutableDictionary<NSString *,
    void (^)(NSDictionary<NSString *, id> *descriptor)> *pendingInspections;
- (void)completeInspectionAtPath:(NSString *)path
                  withDescriptor:(NSDictionary<NSString *, id> *)descriptor;
@end

@interface QueuedInspectionMountTriggerDelegate : MountTriggerDelegate
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *
    inspectionQueuesByPath;
- (void)completeNextInspectionAtPath:(NSString *)path
                      withDescriptor:(NSDictionary<NSString *, id> *)descriptor;
@end

@interface InactiveProfileStoreStub : GDTProfileStore
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *testProfiles;
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

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    completion(self.testVolumeDescriptors[path]);
}

- (NSTimeInterval)unknownExternalVolumeNotificationDelay {
    return 0.01;
}

- (NSArray<NSString *> *)mountedVolumePathsForUnknownExternalVolumeRevalidation {
    return self.testMountedVolumePaths ?: @[];
}

- (void)deliveredUnknownExternalVolumeUUIDsByDiskIDWithCompletion:
    (void (^)(NSDictionary<NSString *, NSString *> *volumeUUIDsByDiskID))completion {
    completion(self.testDeliveredUnknownVolumeUUIDsByDiskID ?: @{});
}

- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID {
    return self.testRememberedAttachmentUUIDsByDiskID[diskID] ?: [NSSet set];
}

- (void)rememberUnknownExternalAttachmentForDiskID:(NSString *)diskID
                                        volumeUUIDs:(NSArray<NSString *> *)volumeUUIDs {
    if (!self.testRememberedAttachmentUUIDsByDiskID) {
        self.testRememberedAttachmentUUIDsByDiskID =
            [NSMutableDictionary dictionary];
    }
    self.testRememberedAttachmentUUIDsByDiskID[diskID] =
        [NSSet setWithArray:volumeUUIDs ?: @[]];
}

- (void)forgetUnknownExternalAttachmentForDiskID:(NSString *)diskID {
    [self.testRememberedAttachmentUUIDsByDiskID removeObjectForKey:diskID];
}

- (void)forgetUnknownExternalAttachmentsExceptDiskIDs:
    (NSSet<NSString *> *)mountedDiskIDs {
    for (NSString *diskID in
         self.testRememberedAttachmentUUIDsByDiskID.allKeys.copy ?: @[]) {
        if (![mountedDiskIDs containsObject:diskID]) {
            [self.testRememberedAttachmentUUIDsByDiskID
                removeObjectForKey:diskID];
        }
    }
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    self.unknownVolumeNoticeCalls++;
    self.lastUnknownVolumeDescriptor = descriptor;
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                                   completion:
    (void (^)(BOOL delivered))completion {
    self.unknownVolumeNoticeCalls++;
    self.lastUnknownVolumeDescriptor = descriptor;
    completion(YES);
}

- (void)removeUnknownExternalVolumeNotificationForDiskID:(NSString *)diskID {
    self.unknownVolumeNoticeRemovalCalls++;
    self.lastRemovedUnknownDiskID = diskID;
}

- (void)removeUnknownExternalVolumeNotificationForDiskID:(NSString *)diskID
                                               volumeUUID:(NSString *)volumeUUID {
    self.unknownVolumeNoticeRemovalCalls++;
    self.lastRemovedUnknownDiskID = diskID;
    self.lastRemovedUnknownVolumeUUID = volumeUUID;
}

- (void)showSetupWindow {
    self.setupWindowCalls++;
}

- (void)showOverviewWindow {
    self.overviewWindowCalls++;
}

@end

@implementation BatchDelayedMountTriggerDelegate

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    if (!self.pendingInspections) {
        self.pendingInspections = [NSMutableDictionary dictionary];
    }
    self.pendingInspections[path] = [completion copy];
}

- (void)completeInspectionAtPath:(NSString *)path
                  withDescriptor:(NSDictionary<NSString *, id> *)descriptor {
    void (^completion)(NSDictionary<NSString *, id> *) =
        self.pendingInspections[path];
    [self.pendingInspections removeObjectForKey:path];
    if (completion) {
        completion(descriptor);
    }
}

@end

@implementation QueuedInspectionMountTriggerDelegate

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    if (!self.inspectionQueuesByPath) {
        self.inspectionQueuesByPath = [NSMutableDictionary dictionary];
    }
    if (!self.inspectionQueuesByPath[path]) {
        self.inspectionQueuesByPath[path] = [NSMutableArray array];
    }
    [self.inspectionQueuesByPath[path] addObject:[completion copy]];
}

- (void)completeNextInspectionAtPath:(NSString *)path
                      withDescriptor:(NSDictionary<NSString *, id> *)descriptor {
    NSMutableArray *queue = self.inspectionQueuesByPath[path];
    void (^completion)(NSDictionary<NSString *, id> *) = queue.firstObject;
    if (queue.count) {
        [queue removeObjectAtIndex:0];
    }
    if (completion) {
        completion(descriptor);
    }
}

@end

@implementation DelayedMountTriggerDelegate

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    self.pendingInspectionPath = path;
    self.pendingInspectionCompletion = completion;
}

- (void)completePendingInspectionWithDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    void (^completion)(NSDictionary<NSString *, id> *) =
        self.pendingInspectionCompletion;
    self.pendingInspectionCompletion = nil;
    self.pendingInspectionPath = nil;
    if (completion) {
        completion(descriptor);
    }
}

@end

@implementation InactiveProfileStoreStub

- (NSArray<NSDictionary<NSString *, NSString *> *> *)profiles {
    return self.testProfiles ?: @[];
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

static NSNotification *UnmountNotification(NSString *path) {
    return [NSNotification notificationWithName:NSWorkspaceDidUnmountNotification
                                         object:nil
                                       userInfo:@{NSWorkspaceVolumeURLKey: [NSURL fileURLWithPath:path]}];
}

static void ProcessUnmount(AppDelegate *delegate, NSNotification *notification) {
    SEL selector = NSSelectorFromString(@"workspaceVolumeDidUnmount:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*UnmountMethod)(id, SEL, NSNotification *);
    UnmountMethod method = (UnmountMethod)[delegate methodForSelector:selector];
    method(delegate, selector, notification);
}

static void PumpRunLoop(NSTimeInterval seconds) {
    [NSRunLoop.currentRunLoop
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSDictionary<NSString *, id> *DescriptorFromDiskutilInfo(
    AppDelegate *delegate,
    NSDictionary *plist,
    NSString *path) {
    SEL selector = NSSelectorFromString(
        @"externalVolumeDescriptorFromDiskutilInfo:requestedPath:");
    if (![delegate respondsToSelector:selector]) return nil;
    typedef NSDictionary<NSString *, id> *(*DescriptorMethod)(
        id, SEL, NSDictionary *, NSString *);
    DescriptorMethod method =
        (DescriptorMethod)[delegate methodForSelector:selector];
    return method(delegate, selector, plist, path);
}

int main(void) {
    @autoreleasepool {
        MountTriggerDelegate *delegate = [[MountTriggerDelegate alloc] init];
        delegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"PRIMARY-UUID"
        };
        delegate.testVolumeUUIDs = @{
            @"/Volumes/GoogleDrive-Backup": @"PRIMARY-UUID"
        };

        Assert(![delegate mountedVolumePath:@"/Volumes/Camera" matchesConfig:delegate.testConfig] &&
               [delegate mountedVolumePath:@"/Volumes/GoogleDrive-Backup" matchesConfig:delegate.testConfig],
               @"mount matching accepts only the explicitly saved APFS volume");

        NSDictionary<NSString *, id> *parsedExternal = DescriptorFromDiskutilInfo(
            delegate,
            @{
                @"MountPoint": @"/Volumes/Archive",
                @"VolumeName": @"Archive",
                @"VolumeUUID": @"archive-uuid",
                @"DeviceIdentifier": @"disk20s2s1",
                @"FilesystemType": @"apfs",
                @"Internal": @NO,
                @"VirtualOrPhysical": @"Physical",
                @"RemovableMediaOrExternalDevice": @YES,
                @"SystemImage": @NO,
                @"WritableVolume": @YES
            },
            @"/Volumes/Archive");
        NSDictionary<NSString *, id> *wrongMount = DescriptorFromDiskutilInfo(
            delegate,
            @{
                @"MountPoint": @"/Volumes/Other",
                @"VolumeUUID": @"archive-uuid",
                @"DeviceIdentifier": @"disk20s2s1"
            },
            @"/Volumes/Archive");
        Assert([parsedExternal[@"diskID"] isEqualToString:@"disk20"] &&
               [parsedExternal[@"volumeUUID"] isEqualToString:@"ARCHIVE-UUID"] &&
               [parsedExternal[@"filesystem"] isEqualToString:@"apfs"] &&
               [parsedExternal[@"isPhysical"] boolValue] &&
               [parsedExternal[@"isLocal"] boolValue] &&
               [parsedExternal[@"isWritable"] boolValue] &&
               wrongMount == nil,
               @"diskutil metadata is normalized to one physical disk and rejects a changed mount point");

        NSDictionary<NSString *, id> *realisticExternalAPFS =
            DescriptorFromDiskutilInfo(
                delegate,
                @{
                    @"MountPoint": @"/Volumes/External APFS",
                    @"VolumeName": @"External APFS",
                    @"VolumeUUID": @"external-apfs-uuid",
                    @"DeviceIdentifier": @"disk21s1",
                    @"ParentWholeDisk": @"disk21",
                    @"APFSPhysicalStores": @[
                        @{@"APFSPhysicalStore": @"disk20s2"}
                    ],
                    @"FilesystemType": @"apfs",
                    @"Internal": @NO,
                    @"RemovableMediaOrExternalDevice": @YES,
                    @"SystemImage": @NO,
                    @"WritableVolume": @YES,
                    @"WritableMedia": @YES
                },
                @"/Volumes/External APFS");
        Assert([realisticExternalAPFS[@"diskID"] isEqualToString:@"disk20"] &&
               [realisticExternalAPFS[@"isPhysical"] boolValue],
               @"real mounted APFS metadata is recognized as direct physical media without a VirtualOrPhysical key");

        NSDictionary<NSString *, id> *readOnlyExternal =
            DescriptorFromDiskutilInfo(
                delegate,
                @{
                    @"MountPoint": @"/Volumes/Read Only",
                    @"VolumeName": @"Read Only",
                    @"VolumeUUID": @"read-only-uuid",
                    @"DeviceIdentifier": @"disk22s1",
                    @"ParentWholeDisk": @"disk22",
                    @"FilesystemType": @"apfs",
                    @"Internal": @NO,
                    @"VirtualOrPhysical": @"Physical",
                    @"RemovableMediaOrExternalDevice": @YES,
                    @"SystemImage": @NO,
                    @"WritableVolume": @NO,
                    @"WritableMedia": @YES
                },
                @"/Volumes/Read Only");
        MountTriggerDelegate *readOnlyDelegate = [[MountTriggerDelegate alloc] init];
        readOnlyDelegate.language = @"en";
        readOnlyDelegate.statusField = [[NSTextField alloc] init];
        readOnlyDelegate.configuredAPFSVolumePath = @"/Volumes/Existing";
        readOnlyDelegate.configuredAPFSVolumeUUID = @"EXISTING-UUID";
        SEL presentUnknownSelector = NSSelectorFromString(
            @"presentSetupForUnknownExternalVolumeDescriptor:");
        if ([readOnlyDelegate respondsToSelector:presentUnknownSelector]) {
            typedef void (*PresentUnknownMethod)(id, SEL, NSDictionary *);
            PresentUnknownMethod presentUnknown =
                (PresentUnknownMethod)[readOnlyDelegate
                    methodForSelector:presentUnknownSelector];
            presentUnknown(readOnlyDelegate, presentUnknownSelector,
                           readOnlyExternal);
        }
        Assert(![readOnlyExternal[@"isWritable"] boolValue] &&
               [readOnlyDelegate.configuredAPFSVolumePath
                   isEqualToString:@"/Volumes/Existing"] &&
               [readOnlyDelegate.configuredAPFSVolumeUUID
                   isEqualToString:@"EXISTING-UUID"],
               @"read-only APFS volumes on writable media cannot be staged as backup targets");

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

        MountTriggerDelegate *legacyPathDelegate =
            [[MountTriggerDelegate alloc] init];
        legacyPathDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup"
        };
        legacyPathDelegate.testVolumeDescriptors = @{
            @"/Volumes/GoogleDrive-Backup": @{
                @"path": @"/Volumes/GoogleDrive-Backup",
                @"name": @"GoogleDrive-Backup",
                @"volumeUUID": @"UNBOUND-UUID",
                @"diskID": @"disk8",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            }
        };
        [legacyPathDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/GoogleDrive-Backup")];
        PumpRunLoop(0.03);
        Assert(legacyPathDelegate.launchCalls == 0 &&
               legacyPathDelegate.unknownVolumeNoticeCalls == 1,
               @"a legacy path-only target is treated as unknown until a human binds its UUID");

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
        uuidDelegate.testVolumeDescriptors = @{
            @"/Volumes/GoogleDrive-Backup": @{
                @"path": @"/Volumes/GoogleDrive-Backup",
                @"name": @"GoogleDrive-Backup",
                @"volumeUUID": @"WRONG-UUID",
                @"diskID": @"disk9",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/GoogleDrive-Backup 2": @{
                @"path": @"/Volumes/GoogleDrive-Backup 2",
                @"name": @"GoogleDrive-Backup",
                @"volumeUUID": @"EXPECTED-UUID",
                @"diskID": @"disk10",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            }
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
        PumpRunLoop(0.03);
        Assert(uuidDelegate.unknownVolumeNoticeCalls == 1,
               @"a same-name external disk with the wrong UUID is offered for explicit setup");
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
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"DUAL-TARGET-UUID"
        };
        dualTargetDelegate.testVolumeUUIDs = @{
            @"/Volumes/GoogleDrive-Backup": @"DUAL-TARGET-UUID"
        };
        [dualTargetDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/NAS")];
        [dualTargetDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/GoogleDrive-Backup")];
        Assert(dualTargetDelegate.launchCalls == 1 &&
               [dualTargetDelegate.launchedTrigger isEqualToString:@"mount"],
               @"an explicitly saved external target remains mount-aware beside a NAS schedule");

        MountTriggerDelegate *unknownDelegate = [[MountTriggerDelegate alloc] init];
        unknownDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/NAS",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"KNOWN-UUID"
        };
        unknownDelegate.testVolumeUUIDs = @{
            @"/Volumes/Archive": @"ARCHIVE-UUID",
            @"/Volumes/Archive Data": @"ARCHIVE-DATA-UUID",
            @"/Volumes/Known Backup": @"KNOWN-UUID",
            @"/Volumes/Macintosh HD": @"INTERNAL-UUID",
            @"/Volumes/Server": @"NETWORK-UUID",
            @"/Volumes/Installer": @"IMAGE-UUID"
        };
        unknownDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive": @{
                @"path": @"/Volumes/Archive",
                @"name": @"Archive",
                @"volumeUUID": @"ARCHIVE-UUID",
                @"diskID": @"disk20",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/Archive Data": @{
                @"path": @"/Volumes/Archive Data",
                @"name": @"Archive Data",
                @"volumeUUID": @"ARCHIVE-DATA-UUID",
                @"diskID": @"disk20",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/Known Backup": @{
                @"path": @"/Volumes/Known Backup",
                @"name": @"Known Backup",
                @"volumeUUID": @"KNOWN-UUID",
                @"diskID": @"disk21",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/Macintosh HD": @{
                @"path": @"/Volumes/Macintosh HD",
                @"name": @"Macintosh HD",
                @"volumeUUID": @"INTERNAL-UUID",
                @"diskID": @"disk3",
                @"isLocal": @YES,
                @"isInternal": @YES,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/Server": @{
                @"path": @"/Volumes/Server",
                @"name": @"Server",
                @"volumeUUID": @"NETWORK-UUID",
                @"diskID": @"server",
                @"isLocal": @NO,
                @"isInternal": @NO,
                @"isPhysical": @NO,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"smbfs"
            },
            @"/Volumes/Installer": @{
                @"path": @"/Volumes/Installer",
                @"name": @"Installer",
                @"volumeUUID": @"IMAGE-UUID",
                @"diskID": @"disk30",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @NO,
                @"isSystemImage": @YES,
                @"isWritable": @NO,
                @"filesystem": @"hfs"
            }
        };

        [unknownDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Archive")];
        [unknownDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Archive")];
        [unknownDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Archive Data")];
        PumpRunLoop(0.03);
        Assert(unknownDelegate.unknownVolumeNoticeCalls == 1 &&
               [unknownDelegate.lastUnknownVolumeDescriptor[@"diskID"] isEqualToString:@"disk20"] &&
               unknownDelegate.launchCalls == 0 &&
               unknownDelegate.setupWindowCalls == 0 &&
               unknownDelegate.overviewWindowCalls == 0,
               @"one attached unknown external disk gets one passive setup notice without UI or backup");

        ProcessUnmount(unknownDelegate,
                       UnmountNotification(@"/Volumes/Archive Data"));
        Assert(unknownDelegate.unknownVolumeNoticeRemovalCalls == 0,
               @"a sibling-volume unmount keeps the physical disk notice available");
        ProcessUnmount(unknownDelegate, UnmountNotification(@"/Volumes/Archive"));
        Assert(unknownDelegate.unknownVolumeNoticeRemovalCalls == 1 &&
               [unknownDelegate.lastRemovedUnknownDiskID isEqualToString:@"disk20"],
               @"the notice is removed after the unknown physical disk fully disconnects");
        [unknownDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Archive")];
        PumpRunLoop(0.03);
        Assert(unknownDelegate.unknownVolumeNoticeCalls == 2,
               @"the same unknown disk may be offered again only after it was fully disconnected");

        MountTriggerDelegate *retargetedSiblingDelegate =
            [[MountTriggerDelegate alloc] init];
        retargetedSiblingDelegate.testConfig = unknownDelegate.testConfig;
        retargetedSiblingDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"],
            @"/Volumes/Archive Data":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive Data"]
        };
        [retargetedSiblingDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive")];
        [retargetedSiblingDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive Data")];
        PumpRunLoop(0.03);
        ProcessUnmount(retargetedSiblingDelegate,
                       UnmountNotification(@"/Volumes/Archive"));
        PumpRunLoop(0.03);
        Assert(retargetedSiblingDelegate.unknownVolumeNoticeRemovalCalls == 0 &&
               retargetedSiblingDelegate.unknownVolumeNoticeCalls == 1,
               @"one physical attachment never produces a second banner when the selected sibling leaves");

        MountTriggerDelegate *lateSiblingAfterNoticeDelegate =
            [[MountTriggerDelegate alloc] init];
        lateSiblingAfterNoticeDelegate.testConfig = unknownDelegate.testConfig;
        lateSiblingAfterNoticeDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"]
        };
        [lateSiblingAfterNoticeDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive")];
        PumpRunLoop(0.03);
        lateSiblingAfterNoticeDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"],
            @"/Volumes/Archive Data":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive Data"]
        };
        [lateSiblingAfterNoticeDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive Data")];
        ProcessUnmount(lateSiblingAfterNoticeDelegate,
                       UnmountNotification(@"/Volumes/Archive"));
        Assert(lateSiblingAfterNoticeDelegate.unknownVolumeNoticeCalls == 1 &&
               [lateSiblingAfterNoticeDelegate
                    .testRememberedAttachmentUUIDsByDiskID[@"disk20"]
                    containsObject:@"ARCHIVE-DATA-UUID"],
               @"a sibling mounted after delivery extends the same attachment without a second banner");

        NSInteger noticesBeforeIgnoredMedia = unknownDelegate.unknownVolumeNoticeCalls;
        for (NSString *path in @[
            @"/Volumes/Macintosh HD", @"/Volumes/Server", @"/Volumes/Installer"
        ]) {
            [unknownDelegate workspaceVolumeDidMount:MountNotification(path)];
        }
        PumpRunLoop(0.03);
        Assert(unknownDelegate.unknownVolumeNoticeCalls == noticesBeforeIgnoredMedia &&
               unknownDelegate.launchCalls == 0,
               @"internal, network, and disk-image mounts remain silent and cannot start a backup");

        MountTriggerDelegate *knownSiblingDelegate = [[MountTriggerDelegate alloc] init];
        knownSiblingDelegate.testConfig = unknownDelegate.testConfig;
        knownSiblingDelegate.testVolumeUUIDs = @{
            @"/Volumes/Data": @"DATA-UUID",
            @"/Volumes/Known Backup": @"KNOWN-UUID"
        };
        knownSiblingDelegate.testVolumeDescriptors = @{
            @"/Volumes/Data": @{
                @"path": @"/Volumes/Data",
                @"name": @"Data",
                @"volumeUUID": @"DATA-UUID",
                @"diskID": @"disk40",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            },
            @"/Volumes/Known Backup": @{
                @"path": @"/Volumes/Known Backup",
                @"name": @"Known Backup",
                @"volumeUUID": @"KNOWN-UUID",
                @"diskID": @"disk40",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            }
        };
        [knownSiblingDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Data")];
        [knownSiblingDelegate workspaceVolumeDidMount:MountNotification(@"/Volumes/Known Backup")];
        PumpRunLoop(0.03);
        Assert(knownSiblingDelegate.unknownVolumeNoticeCalls == 0 &&
               knownSiblingDelegate.launchCalls == 1,
               @"a disk containing the configured backup volume is not mislabeled as unknown");

        MountTriggerDelegate *lateKnownSiblingDelegate =
            [[MountTriggerDelegate alloc] init];
        lateKnownSiblingDelegate.testConfig = unknownDelegate.testConfig;
        lateKnownSiblingDelegate.testVolumeUUIDs = knownSiblingDelegate.testVolumeUUIDs;
        lateKnownSiblingDelegate.testVolumeDescriptors =
            knownSiblingDelegate.testVolumeDescriptors;
        [lateKnownSiblingDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Data")];
        PumpRunLoop(0.03);
        Assert(lateKnownSiblingDelegate.unknownVolumeNoticeCalls == 1,
               @"an unknown sibling can be noticed before the configured sibling finishes mounting");
        [lateKnownSiblingDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Known Backup")];
        Assert(lateKnownSiblingDelegate.unknownVolumeNoticeRemovalCalls == 1 &&
               [lateKnownSiblingDelegate.lastRemovedUnknownDiskID
                   isEqualToString:@"disk40"],
               @"a later configured sibling retracts the physical disk's earlier false notice");

        DelayedMountTriggerDelegate *unmountedBeforeInspection =
            [[DelayedMountTriggerDelegate alloc] init];
        unmountedBeforeInspection.testConfig = unknownDelegate.testConfig;
        NSDictionary<NSString *, id> *departedDescriptor =
            unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"];
        [unmountedBeforeInspection workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive")];
        ProcessUnmount(unmountedBeforeInspection,
                       UnmountNotification(@"/Volumes/Archive"));
        [unmountedBeforeInspection
            completePendingInspectionWithDescriptor:departedDescriptor];
        PumpRunLoop(0.03);
        Assert(unmountedBeforeInspection.unknownVolumeNoticeCalls == 0,
               @"a disk disconnected before asynchronous inspection completes cannot leave a stale notice");

        BatchDelayedMountTriggerDelegate *unmountedDuringStartupBatch =
            [[BatchDelayedMountTriggerDelegate alloc] init];
        unmountedDuringStartupBatch.testConfig = unknownDelegate.testConfig;
        unmountedDuringStartupBatch.testMountedVolumePaths = @[
            @"/Volumes/Archive", @"/Volumes/Pending"
        ];
        SEL primeCacheSelector = NSSelectorFromString(
            @"primeMountedExternalVolumeCache");
        if ([unmountedDuringStartupBatch respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[unmountedDuringStartupBatch
                methodForSelector:primeCacheSelector])(
                    unmountedDuringStartupBatch, primeCacheSelector);
        }
        [unmountedDuringStartupBatch
            completeInspectionAtPath:@"/Volumes/Archive"
                      withDescriptor:departedDescriptor];
        ProcessUnmount(unmountedDuringStartupBatch,
                       UnmountNotification(@"/Volumes/Archive"));
        [unmountedDuringStartupBatch
            completeInspectionAtPath:@"/Volumes/Pending"
                      withDescriptor:nil];
        PumpRunLoop(0.03);
        Assert(unmountedDuringStartupBatch.unknownVolumeNoticeCalls == 0 &&
               unmountedDuringStartupBatch
                   .mountedExternalVolumeDescriptorsByPath[@"/Volumes/Archive"] == nil,
               @"startup reconciliation cannot resurrect a volume removed after its inspection completed");

        BatchDelayedMountTriggerDelegate *outOfOrderKnownSibling =
            [[BatchDelayedMountTriggerDelegate alloc] init];
        outOfOrderKnownSibling.testConfig = knownSiblingDelegate.testConfig;
        outOfOrderKnownSibling.testMountedVolumePaths = @[
            @"/Volumes/Data", @"/Volumes/Known Backup"
        ];
        outOfOrderKnownSibling.testDeliveredUnknownVolumeUUIDsByDiskID = @{
            @"disk40": @"DATA-UUID"
        };
        if ([outOfOrderKnownSibling respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[outOfOrderKnownSibling
                methodForSelector:primeCacheSelector])(
                    outOfOrderKnownSibling, primeCacheSelector);
        }
        [outOfOrderKnownSibling
            completeInspectionAtPath:@"/Volumes/Data"
                      withDescriptor:
                knownSiblingDelegate.testVolumeDescriptors[@"/Volumes/Data"]];
        [outOfOrderKnownSibling
            completeInspectionAtPath:@"/Volumes/Known Backup"
                      withDescriptor:
                knownSiblingDelegate
                    .testVolumeDescriptors[@"/Volumes/Known Backup"]];
        PumpRunLoop(0.03);
        Assert(outOfOrderKnownSibling.unknownVolumeNoticeCalls == 0 &&
               outOfOrderKnownSibling.unknownVolumeNoticeRemovalCalls == 1 &&
               [outOfOrderKnownSibling.knownExternalDiskIDs
                   containsObject:@"disk40"],
               @"out-of-order startup inspection lets a configured sibling suppress and retract an unknown notice");

        QueuedInspectionMountTriggerDelegate *startupMountRace =
            [[QueuedInspectionMountTriggerDelegate alloc] init];
        startupMountRace.testConfig = knownSiblingDelegate.testConfig;
        startupMountRace.testMountedVolumePaths = @[
            @"/Volumes/Data", @"/Volumes/Known Backup"
        ];
        startupMountRace.testVolumeDescriptors =
            knownSiblingDelegate.testVolumeDescriptors;
        if ([startupMountRace respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[startupMountRace
                methodForSelector:primeCacheSelector])(
                    startupMountRace, primeCacheSelector);
        }
        [startupMountRace
            completeNextInspectionAtPath:@"/Volumes/Data"
                          withDescriptor:
                knownSiblingDelegate.testVolumeDescriptors[@"/Volumes/Data"]];
        [startupMountRace workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Data")];
        [startupMountRace
            completeNextInspectionAtPath:@"/Volumes/Data"
                          withDescriptor:
                knownSiblingDelegate.testVolumeDescriptors[@"/Volumes/Data"]];
        PumpRunLoop(0.03);
        [startupMountRace
            completeNextInspectionAtPath:@"/Volumes/Known Backup"
                          withDescriptor:
                knownSiblingDelegate
                    .testVolumeDescriptors[@"/Volumes/Known Backup"]];
        Assert(startupMountRace.unknownVolumeNoticeCalls == 1 &&
               startupMountRace.unknownVolumeNoticeRemovalCalls == 1 &&
               ![startupMountRace.notifiedUnknownExternalDiskIDs
                   containsObject:@"disk40"] &&
               [startupMountRace.knownExternalDiskIDs
                   containsObject:@"disk40"],
               @"startup reconciliation retracts a concurrently delivered false unknown notice");

        QueuedInspectionMountTriggerDelegate *newDiskDuringStartup =
            [[QueuedInspectionMountTriggerDelegate alloc] init];
        NSDictionary<NSString *, id> *cameraDescriptor = @{
            @"path": @"/Volumes/Camera",
            @"name": @"Camera",
            @"volumeUUID": @"CAMERA-UUID",
            @"diskID": @"disk60",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs"
        };
        newDiskDuringStartup.testConfig = knownSiblingDelegate.testConfig;
        newDiskDuringStartup.testMountedVolumePaths =
            @[@"/Volumes/Known Backup"];
        newDiskDuringStartup.testVolumeDescriptors = @{
            @"/Volumes/Known Backup":
                knownSiblingDelegate
                    .testVolumeDescriptors[@"/Volumes/Known Backup"],
            @"/Volumes/Camera": cameraDescriptor
        };
        if ([newDiskDuringStartup respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[newDiskDuringStartup
                methodForSelector:primeCacheSelector])(
                    newDiskDuringStartup, primeCacheSelector);
        }
        [newDiskDuringStartup workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Camera")];
        [newDiskDuringStartup
            completeNextInspectionAtPath:@"/Volumes/Camera"
                          withDescriptor:cameraDescriptor];
        PumpRunLoop(0.03);
        [newDiskDuringStartup
            completeNextInspectionAtPath:@"/Volumes/Known Backup"
                          withDescriptor:
                knownSiblingDelegate
                    .testVolumeDescriptors[@"/Volumes/Known Backup"]];
        Assert([newDiskDuringStartup
                    .testRememberedAttachmentUUIDsByDiskID[@"disk60"]
                    containsObject:@"CAMERA-UUID"],
               @"startup cleanup preserves a second disk that mounted live during the startup snapshot");

        MountTriggerDelegate *restartCacheDelegate =
            [[MountTriggerDelegate alloc] init];
        restartCacheDelegate.testConfig = unknownDelegate.testConfig;
        restartCacheDelegate.testMountedVolumePaths = @[@"/Volumes/Archive"];
        restartCacheDelegate.testDeliveredUnknownVolumeUUIDsByDiskID = @{
            @"disk20": @"ARCHIVE-UUID"
        };
        restartCacheDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"]
        };
        if ([restartCacheDelegate respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[restartCacheDelegate
                methodForSelector:primeCacheSelector])(
                    restartCacheDelegate, primeCacheSelector);
        }
        PumpRunLoop(0.03);
        ProcessUnmount(restartCacheDelegate,
                       UnmountNotification(@"/Volumes/Archive"));
        Assert([restartCacheDelegate respondsToSelector:primeCacheSelector] &&
               restartCacheDelegate.unknownVolumeNoticeCalls == 0 &&
               restartCacheDelegate.unknownVolumeNoticeRemovalCalls == 1,
               @"controller restart rebuilds attachment state so unplugging removes an older passive notice");

        MountTriggerDelegate *freshStartupDelegate =
            [[MountTriggerDelegate alloc] init];
        freshStartupDelegate.testConfig = unknownDelegate.testConfig;
        freshStartupDelegate.testMountedVolumePaths = @[@"/Volumes/Archive"];
        freshStartupDelegate.testVolumeDescriptors =
            restartCacheDelegate.testVolumeDescriptors;
        if ([freshStartupDelegate respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[freshStartupDelegate
                methodForSelector:primeCacheSelector])(
                    freshStartupDelegate, primeCacheSelector);
        }
        PumpRunLoop(0.05);
        Assert(freshStartupDelegate.unknownVolumeNoticeCalls == 1 &&
               [freshStartupDelegate
                    .testRememberedAttachmentUUIDsByDiskID[@"disk20"]
                    containsObject:@"ARCHIVE-UUID"],
               @"first controller launch offers a pre-mounted unknown disk when no older notice exists");

        MountTriggerDelegate *dismissedRestartDelegate =
            [[MountTriggerDelegate alloc] init];
        dismissedRestartDelegate.testConfig = unknownDelegate.testConfig;
        dismissedRestartDelegate.testMountedVolumePaths = @[@"/Volumes/Archive"];
        dismissedRestartDelegate.testVolumeDescriptors =
            restartCacheDelegate.testVolumeDescriptors;
        dismissedRestartDelegate.testRememberedAttachmentUUIDsByDiskID =
            freshStartupDelegate.testRememberedAttachmentUUIDsByDiskID;
        if ([dismissedRestartDelegate respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[dismissedRestartDelegate
                methodForSelector:primeCacheSelector])(
                    dismissedRestartDelegate, primeCacheSelector);
        }
        PumpRunLoop(0.05);
        Assert(dismissedRestartDelegate.unknownVolumeNoticeCalls == 0,
               @"a dismissed or ignored notice stays suppressed across a controller restart");
        ProcessUnmount(dismissedRestartDelegate,
                       UnmountNotification(@"/Volumes/Archive"));
        Assert(dismissedRestartDelegate
                   .testRememberedAttachmentUUIDsByDiskID[@"disk20"] == nil,
               @"fully disconnecting the disk clears its remembered attachment marker");

        MountTriggerDelegate *reconnectedAfterDismissalDelegate =
            [[MountTriggerDelegate alloc] init];
        reconnectedAfterDismissalDelegate.testConfig = unknownDelegate.testConfig;
        reconnectedAfterDismissalDelegate.testVolumeDescriptors =
            restartCacheDelegate.testVolumeDescriptors;
        reconnectedAfterDismissalDelegate.testRememberedAttachmentUUIDsByDiskID =
            dismissedRestartDelegate.testRememberedAttachmentUUIDsByDiskID;
        [reconnectedAfterDismissalDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Archive")];
        PumpRunLoop(0.05);
        Assert(reconnectedAfterDismissalDelegate.unknownVolumeNoticeCalls == 1,
               @"reconnecting after a full disconnect makes the disk eligible once again");

        MountTriggerDelegate *restartMultiVolumeDelegate =
            [[MountTriggerDelegate alloc] init];
        restartMultiVolumeDelegate.testConfig = unknownDelegate.testConfig;
        restartMultiVolumeDelegate.testMountedVolumePaths = @[
            @"/Volumes/Archive", @"/Volumes/Archive Data"
        ];
        restartMultiVolumeDelegate.testDeliveredUnknownVolumeUUIDsByDiskID = @{
            @"disk20": @"ARCHIVE-DATA-UUID"
        };
        restartMultiVolumeDelegate.testVolumeDescriptors = @{
            @"/Volumes/Archive":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive"],
            @"/Volumes/Archive Data":
                unknownDelegate.testVolumeDescriptors[@"/Volumes/Archive Data"]
        };
        if ([restartMultiVolumeDelegate respondsToSelector:primeCacheSelector]) {
            typedef void (*PrimeCacheMethod)(id, SEL);
            ((PrimeCacheMethod)[restartMultiVolumeDelegate
                methodForSelector:primeCacheSelector])(
                    restartMultiVolumeDelegate, primeCacheSelector);
        }
        PumpRunLoop(0.03);
        ProcessUnmount(restartMultiVolumeDelegate,
                       UnmountNotification(@"/Volumes/Archive"));
        NSInteger removalsBeforeSelectedUnmount =
            restartMultiVolumeDelegate.unknownVolumeNoticeRemovalCalls;
        ProcessUnmount(restartMultiVolumeDelegate,
                       UnmountNotification(@"/Volumes/Archive Data"));
        Assert(removalsBeforeSelectedUnmount == 0 &&
               restartMultiVolumeDelegate.unknownVolumeNoticeRemovalCalls == 1,
               @"restart cache follows the exact sibling UUID stored in the delivered notice");

        NSString *inactiveConfigPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                @"gdrive-mount-trigger-inactive-profile.conf"];
        NSError *inactiveConfigError = nil;
        NSString *inactiveConfigContents =
            @"GDRIVE_BACKUP_PROFILE_ID=archive\n"
            @"GDRIVE_BACKUP_PROFILE_NAME=Archive\n"
            @"GDRIVE_BACKUP_VOLUME_UUID=INACTIVE-UUID\n";
        BOOL wroteInactiveConfig = [inactiveConfigContents
            writeToFile:inactiveConfigPath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&inactiveConfigError];
        Assert(wroteInactiveConfig && inactiveConfigError == nil,
               @"inactive-profile fixture is available");
        InactiveProfileStoreStub *profileStore =
            [[InactiveProfileStoreStub alloc]
                initWithConfigDirectory:NSTemporaryDirectory()];
        profileStore.testProfiles = @[
            @{
                @"id": @"archive",
                @"name": @"Archive",
                @"configPath": inactiveConfigPath
            }
        ];
        MountTriggerDelegate *inactiveKnownDelegate =
            [[MountTriggerDelegate alloc] init];
        inactiveKnownDelegate.profileStore = profileStore;
        inactiveKnownDelegate.testConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/NAS",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"ACTIVE-UUID"
        };
        inactiveKnownDelegate.testVolumeDescriptors = @{
            @"/Volumes/Inactive Backup": @{
                @"path": @"/Volumes/Inactive Backup",
                @"name": @"Inactive Backup",
                @"volumeUUID": @"INACTIVE-UUID",
                @"diskID": @"disk50",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            }
        };
        [inactiveKnownDelegate workspaceVolumeDidMount:
            MountNotification(@"/Volumes/Inactive Backup")];
        PumpRunLoop(0.03);
        Assert(inactiveKnownDelegate.unknownVolumeNoticeCalls == 0 &&
               inactiveKnownDelegate.launchCalls == 0,
               @"a UUID retained only by an inactive profile suppresses the unknown-disk notice");
    }

    if (failures > 0) {
        printf("%d mount trigger test(s) failed.\n", failures);
        return 1;
    }
    printf("All mount trigger tests passed.\n");
    return 0;
}
