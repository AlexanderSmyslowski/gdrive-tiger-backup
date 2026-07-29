#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface AppDelegate (NotificationIntegrationTesting)
- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (void)processAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (NSUserDefaults *)backupNotificationDefaultsStore;
- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion;
- (UNMutableNotificationContent *)backupNotificationContentForDecision:
    (NSDictionary<NSString *, NSString *> *)decision;
- (void)clearBackupFailureNotificationsForConfig:
    (NSDictionary<NSString *, NSString *> *)config
    summary:(NSDictionary<NSString *, NSString *> *)summary
    status:(NSString *)status;
- (NSDictionary<NSString *, NSString *> *)currentAutomaticRetryDecision;
- (NSString *)backupAlertStatusForConfig:(NSDictionary<NSString *, NSString *> *)config
                                  summary:(NSDictionary<NSString *, NSString *> *)summary
                                rawStatus:(NSString *)rawStatus
                                 decision:(NSDictionary<NSString *, NSString *> *)decision;
- (NSSet<UNNotificationCategory *> *)appNotificationCategories;
- (UNMutableNotificationContent *)unknownExternalVolumeNotificationContentForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor;
- (UNNotificationPresentationOptions)presentationOptionsForNotificationCategoryIdentifier:
    (NSString *)categoryIdentifier;
- (void)handleUnknownExternalVolumeActionIdentifier:(NSString *)actionIdentifier
                                           userInfo:(NSDictionary *)userInfo;
- (void)finishUnknownExternalVolumeInspectionForDiskID:(NSString *)diskID;
- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID;
- (void)rememberUnknownExternalAttachmentForDiskID:(NSString *)diskID
                                        volumeUUIDs:(NSArray<NSString *> *)volumeUUIDs;
- (void)forgetUnknownExternalAttachmentForDiskID:(NSString *)diskID;
@end

@interface NotificationTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic) NSInteger deliveryCalls;
@property(nonatomic) BOOL deliverySucceeds;
@property(nonatomic, copy) NSArray<NSString *> *removedNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *extraDeliveredNotificationIdentifiers;
@end

@interface UnknownVolumeNotificationTestDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSDictionary<NSString *, id> *revalidatedDescriptor;
@property(nonatomic) NSInteger revalidationCalls;
@property(nonatomic) NSInteger setupPresentationCalls;
@property(nonatomic) NSInteger overviewPresentationCalls;
@property(nonatomic) NSInteger configSaveCalls;
@property(nonatomic) NSInteger backupLaunchCalls;
@property(nonatomic) BOOL revalidationRanOnMainThread;
@property(nonatomic) BOOL setupPresentationRanOnMainThread;
@property(nonatomic) NSInteger unavailablePresentationCalls;
@end

@interface AttachmentMarkerTestDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSString *testBootSessionID;
@end

@implementation AttachmentMarkerTestDelegate

- (NSString *)unknownExternalVolumeBootSessionID {
    return self.testBootSessionID ?: @"TEST-BOOT";
}

@end

@implementation UnknownVolumeNotificationTestDelegate

- (void)revalidateUnknownExternalVolumeUserInfo:(NSDictionary *)userInfo
                                      completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    (void)userInfo;
    self.revalidationCalls++;
    self.revalidationRanOnMainThread = NSThread.isMainThread;
    completion(self.revalidatedDescriptor);
}

- (void)presentSetupForUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    (void)descriptor;
    self.setupPresentationCalls++;
    self.setupPresentationRanOnMainThread = NSThread.isMainThread;
}

- (void)presentUnknownExternalVolumeUnavailable {
    self.unavailablePresentationCalls++;
}

- (void)showOverviewWindow {
    self.overviewPresentationCalls++;
}

- (BOOL)saveSetupValues {
    self.configSaveCalls++;
    return YES;
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes {
    (void)argument;
    (void)trigger;
    (void)assumeYes;
    self.backupLaunchCalls++;
    return YES;
}

@end

@interface RestartUnknownVolumeNotificationTestDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSArray<NSString *> *candidateMountPaths;
@property(nonatomic, copy) NSDictionary<NSString *, NSDictionary<NSString *, id> *> *descriptorsByPath;
@property(nonatomic, strong) NSMutableArray<NSString *> *inspectedPaths;
@property(nonatomic) NSInteger mountEnumerationCalls;
@property(nonatomic) NSInteger setupPresentationCalls;
@property(nonatomic, copy) NSDictionary<NSString *, id> *presentedDescriptor;
@property(nonatomic, copy) NSDictionary<NSString *, NSSet<NSString *> *> *
    rememberedAttachmentUUIDsByDiskID;
@end

@implementation RestartUnknownVolumeNotificationTestDelegate

- (NSArray<NSString *> *)mountedVolumePathsForUnknownExternalVolumeRevalidation {
    self.mountEnumerationCalls++;
    return self.candidateMountPaths ?: @[];
}

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    if (!self.inspectedPaths) {
        self.inspectedPaths = [NSMutableArray array];
    }
    [self.inspectedPaths addObject:path];
    completion(self.descriptorsByPath[path]);
}

- (void)presentSetupForUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    self.setupPresentationCalls++;
    self.presentedDescriptor = descriptor;
}

- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID {
    return self.rememberedAttachmentUUIDsByDiskID[diskID] ?: [NSSet set];
}

@end

@interface UnknownVolumeDeliveryTestDelegate : NotificationTestDelegate
@property(nonatomic) BOOL unknownDeliverySucceeds;
@property(nonatomic) NSInteger completionDeliveryCalls;
@property(nonatomic) NSInteger legacyDeliveryCalls;
@property(nonatomic) BOOL deferUnknownDelivery;
@property(nonatomic, copy) void (^deferredUnknownDeliveryCompletion)(BOOL delivered);
@property(nonatomic, copy) NSDictionary<NSString *, id> *lastUnknownDeliveryDescriptor;
@end

@implementation UnknownVolumeDeliveryTestDelegate

- (NSSet<NSString *> *)configuredExternalVolumeUUIDs {
    return [NSSet set];
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    (void)descriptor;
    self.legacyDeliveryCalls++;
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                                   completion:
    (void (^)(BOOL delivered))completion {
    (void)descriptor;
    self.completionDeliveryCalls++;
    self.lastUnknownDeliveryDescriptor = descriptor;
    if (self.deferUnknownDelivery) {
        self.deferredUnknownDeliveryCompletion = completion;
    } else {
        completion(self.unknownDeliverySucceeds);
    }
}

- (NSTimeInterval)unknownExternalVolumeNotificationRetryDelay {
    return 0.01;
}

- (NSTimeInterval)unknownExternalVolumeNotificationDelay {
    return 0.01;
}

- (void)removeUnknownExternalVolumeNotificationForDiskID:(NSString *)diskID
                                               volumeUUID:(NSString *)volumeUUID {
    (void)diskID;
    (void)volumeUUID;
}

@end

@implementation NotificationTestDelegate

- (NSUserDefaults *)backupNotificationDefaultsStore {
    return self.testDefaults;
}

- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion {
    (void)decision;
    self.deliveryCalls++;
    completion(self.deliverySucceeds);
}

- (void)removeBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                forProfileID:(NSString *)profileID {
    (void)profileID;
    NSMutableArray<NSString *> *all = [identifiers mutableCopy] ?: [NSMutableArray array];
    for (NSString *identifier in self.extraDeliveredNotificationIdentifiers ?: @[]) {
        if (![all containsObject:identifier]) [all addObject:identifier];
    }
    self.removedNotificationIdentifiers = all;
}

@end

@interface RetryTestDelegate : NotificationTestDelegate
@property(nonatomic) NSInteger retryLaunchCalls;
@property(nonatomic) BOOL retryLaunchSucceeds;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *lastRetryDecision;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *revalidatedRetryDecision;
@end

@implementation RetryTestDelegate

- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.retryLaunchCalls++;
    self.lastRetryDecision = decision;
    return self.retryLaunchSucceeds;
}

- (NSDictionary<NSString *, NSString *> *)currentAutomaticRetryDecision {
    return self.revalidatedRetryDecision;
}

@end

@interface NotificationRefreshDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *capturedDecision;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *capturedRetryDecision;
@end

@implementation NotificationRefreshDelegate

- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.capturedDecision = decision;
}

- (void)processAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.capturedRetryDecision = decision;
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

static void Process(NotificationTestDelegate *delegate,
                    NSDictionary<NSString *, NSString *> *decision) {
    SEL selector = NSSelectorFromString(@"processBackupNotificationDecision:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*ProcessMethod)(id, SEL, NSDictionary *);
    ProcessMethod method = (ProcessMethod)[delegate methodForSelector:selector];
    method(delegate, selector, decision);
}

static void ProcessRetry(RetryTestDelegate *delegate,
                         NSDictionary<NSString *, NSString *> *decision) {
    SEL selector = NSSelectorFromString(@"processAutomaticRetryDecision:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*ProcessMethod)(id, SEL, NSDictionary *);
    ProcessMethod method = (ProcessMethod)[delegate methodForSelector:selector];
    method(delegate, selector, decision);
}

static void ProcessUnknownVolumeAction(AppDelegate *delegate,
                                       NSString *action,
                                       NSDictionary *userInfo) {
    SEL selector = NSSelectorFromString(
        @"handleUnknownExternalVolumeActionIdentifier:userInfo:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*ActionMethod)(id, SEL, NSString *, NSDictionary *);
    ActionMethod method = (ActionMethod)[delegate methodForSelector:selector];
    method(delegate, selector, action, userInfo);
}

static void ProcessUnknownVolumeUnmount(AppDelegate *delegate,
                                        NSString *path) {
    SEL selector = NSSelectorFromString(@"workspaceVolumeDidUnmount:");
    if (![delegate respondsToSelector:selector]) return;
    NSNotification *notification = [NSNotification
        notificationWithName:NSWorkspaceDidUnmountNotification
                      object:nil
                    userInfo:@{
        NSWorkspaceVolumeURLKey: [NSURL fileURLWithPath:path]
    }];
    typedef void (*UnmountMethod)(id, SEL, NSNotification *);
    UnmountMethod method = (UnmountMethod)[delegate methodForSelector:selector];
    method(delegate, selector, notification);
}

static BOOL WaitForCondition(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop
            runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}

static void PrepareUnknownVolumeDeliveryState(
    UnknownVolumeDeliveryTestDelegate *delegate,
    NSDictionary<NSString *, id> *descriptor) {
    delegate.mountedExternalVolumeDescriptorsByPath =
        [@{descriptor[@"path"]: descriptor} mutableCopy];
    delegate.unknownExternalVolumeTimersByDiskID = [NSMutableDictionary dictionary];
    delegate.knownExternalDiskIDs = [NSMutableSet set];
    delegate.notifiedUnknownExternalDiskIDs = [NSMutableSet set];
}

int main(void) {
    @autoreleasepool {
        NotificationTestDelegate *delegate = [[NotificationTestDelegate alloc] init];
        NSString *suiteName = [@"com.commcats.gdrivebackup.notification-tests."
            stringByAppendingString:NSUUID.UUID.UUIDString];
        delegate.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        delegate.deliverySucceeds = YES;

        Assert([delegate respondsToSelector:
                    NSSelectorFromString(@"processBackupNotificationDecision:")],
               @"the persistent controller can process notification decisions");

        NSDictionary<NSString *, NSString *> *first = @{
            @"identifier": @"com.commcats.gdrivebackup.office.failure.100",
            @"profileID": @"office",
            @"kind": @"failure",
            @"issueTimestamp": @"100",
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": @"failedHint"
        };
        Process(delegate, first);
        Process(delegate, first);
        Assert(delegate.deliveryCalls == 1,
               @"the same profile and backup run produces only one notification");

        NSMutableDictionary<NSString *, NSString *> *nextRun = [first mutableCopy];
        nextRun[@"identifier"] = @"com.commcats.gdrivebackup.office.failure.200";
        nextRun[@"issueTimestamp"] = @"200";
        Process(delegate, nextRun);
        Assert(delegate.deliveryCalls == 2,
               @"a later failed run remains eligible for its own notification");

        NSMutableDictionary<NSString *, NSString *> *otherProfile = [first mutableCopy];
        otherProfile[@"profileID"] = @"archive";
        Process(delegate, otherProfile);
        Assert(delegate.deliveryCalls == 3,
               @"notification deduplication is isolated per backup profile");

        delegate.deliverySucceeds = NO;
        NSMutableDictionary<NSString *, NSString *> *notDelivered = [first mutableCopy];
        notDelivered[@"identifier"] = @"com.commcats.gdrivebackup.office.failure.300";
        Process(delegate, notDelivered);
        Process(delegate, notDelivered);
        Assert(delegate.deliveryCalls == 5,
               @"a notification is marked handled only after macOS accepts it");

        Process(delegate, @{});
        Assert(delegate.deliveryCalls == 5,
               @"incomplete policy output cannot create a notification");

        RetryTestDelegate *retryDelegate = [[RetryTestDelegate alloc] init];
        retryDelegate.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".retry"]];
        retryDelegate.retryLaunchSucceeds = YES;
        NSDictionary<NSString *, NSString *> *retryDecision = @{
            @"identifier": @"office.automatic-retry.100",
            @"profileID": @"office",
            @"originStartedAt": @"100",
            @"attempt": @"1",
            @"trigger": @"schedule-retry"
        };
        retryDelegate.revalidatedRetryDecision = retryDecision;
        ProcessRetry(retryDelegate, retryDecision);
        ProcessRetry(retryDelegate, retryDecision);
        Assert(retryDelegate.retryLaunchCalls == 1 &&
               [retryDelegate.lastRetryDecision[@"originStartedAt"] isEqualToString:@"100"],
               @"the same durable failure can launch only one automatic retry");

        retryDelegate.retryLaunchSucceeds = NO;
        NSMutableDictionary<NSString *, NSString *> *notLaunched = [retryDecision mutableCopy];
        notLaunched[@"identifier"] = @"office.automatic-retry.200";
        notLaunched[@"originStartedAt"] = @"200";
        retryDelegate.revalidatedRetryDecision = notLaunched;
        ProcessRetry(retryDelegate, notLaunched);
        ProcessRetry(retryDelegate, notLaunched);
        Assert(retryDelegate.retryLaunchCalls == 3,
               @"a failed task launch is not persisted as an executed retry");

        NSMutableDictionary<NSString *, NSString *> *stale = [retryDecision mutableCopy];
        stale[@"identifier"] = @"office.automatic-retry.300";
        stale[@"originStartedAt"] = @"300";
        retryDelegate.revalidatedRetryDecision = nil;
        ProcessRetry(retryDelegate, stale);
        Assert(retryDelegate.retryLaunchCalls == 3,
               @"a stale asynchronous retry decision is revalidated before launch");

        SEL contentSelector = NSSelectorFromString(@"backupNotificationContentForDecision:");
        UNMutableNotificationContent *content = nil;
        if ([delegate respondsToSelector:contentSelector]) {
            typedef UNMutableNotificationContent *(*ContentMethod)(id, SEL, NSDictionary *);
            ContentMethod contentMethod = (ContentMethod)[delegate methodForSelector:contentSelector];
            content = contentMethod(delegate, contentSelector, first);
        }
        BOOL timeSensitiveLevel = NO;
        if (@available(macOS 12.0, *)) {
            timeSensitiveLevel =
                content.interruptionLevel == UNNotificationInterruptionLevelTimeSensitive;
        }
        Assert(content.sound != nil &&
               [content.categoryIdentifier isEqualToString:@"GDT_BACKUP_ALERT"] &&
               timeSensitiveLevel,
               @"automatic backup alerts are time-sensitive and audible without opening a window");

        NSSet<UNNotificationCategory *> *categories = nil;
        SEL categoriesSelector = NSSelectorFromString(@"appNotificationCategories");
        if ([delegate respondsToSelector:categoriesSelector]) {
            typedef NSSet<UNNotificationCategory *> *(*CategoriesMethod)(id, SEL);
            CategoriesMethod categoriesMethod =
                (CategoriesMethod)[delegate methodForSelector:categoriesSelector];
            categories = categoriesMethod(delegate, categoriesSelector);
        }
        NSMutableDictionary<NSString *, UNNotificationCategory *> *categoriesByID =
            [NSMutableDictionary dictionary];
        for (UNNotificationCategory *category in categories ?: [NSSet set]) {
            categoriesByID[category.identifier] = category;
        }
        UNNotificationCategory *unknownCategory =
            categoriesByID[@"GDT_UNKNOWN_EXTERNAL_VOLUME"];
        NSDictionary<NSString *, UNNotificationAction *> *unknownActionsByID = @{};
        if (unknownCategory) {
            NSMutableDictionary *actions = [NSMutableDictionary dictionary];
            for (UNNotificationAction *action in unknownCategory.actions) {
                actions[action.identifier] = action;
            }
            unknownActionsByID = actions;
        }
        Assert(categoriesByID[@"GDT_BACKUP_ALERT"] != nil &&
               unknownCategory != nil &&
               unknownCategory.actions.count == 2 &&
               (unknownActionsByID[@"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP"].options &
                    UNNotificationActionOptionForeground) != 0 &&
               unknownActionsByID[@"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE"].options ==
                    UNNotificationActionOptionNone,
               @"backup alerts and passive unknown-disk actions are registered together");

        NSDictionary<NSString *, id> *unknownDescriptor = @{
            @"path": @"/Volumes/Private Customer Folder",
            @"name": @"TOSHIBA_4TB",
            @"volumeUUID": @"PRIVATE-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs",
            @"attachmentVolumeUUIDs": @[@"PRIVATE-UUID", @"SIBLING-UUID"]
        };
        UNMutableNotificationContent *unknownContent = nil;
        SEL unknownContentSelector = NSSelectorFromString(
            @"unknownExternalVolumeNotificationContentForDescriptor:");
        if ([delegate respondsToSelector:unknownContentSelector]) {
            typedef UNMutableNotificationContent *(*UnknownContentMethod)(
                id, SEL, NSDictionary *);
            UnknownContentMethod unknownContentMethod =
                (UnknownContentMethod)[delegate methodForSelector:unknownContentSelector];
            unknownContent = unknownContentMethod(
                delegate, unknownContentSelector, unknownDescriptor);
        }
        BOOL passiveLevel = NO;
        if (@available(macOS 12.0, *)) {
            passiveLevel =
                unknownContent.interruptionLevel == UNNotificationInterruptionLevelPassive;
        }
        Assert([unknownContent.categoryIdentifier
                   isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME"] &&
               unknownContent.sound == nil &&
               passiveLevel &&
               [unknownContent.body containsString:@"TOSHIBA_4TB"] &&
               ![unknownContent.body containsString:@"/Volumes/"] &&
               ![unknownContent.body containsString:@"PRIVATE-UUID"] &&
               [unknownContent.userInfo[@"diskID"] isEqualToString:@"disk20"] &&
               [unknownContent.userInfo[@"volumeUUID"] isEqualToString:@"PRIVATE-UUID"] &&
               [unknownContent.userInfo[@"attachmentVolumeUUIDs"]
                   isEqualToArray:@[@"PRIVATE-UUID", @"SIBLING-UUID"]] &&
               unknownContent.userInfo[@"path"] == nil,
               @"unknown-disk notices are passive, silent, and expose no path or UUID in their text");

        NSString *markerSuiteName =
            [suiteName stringByAppendingString:@".attachment-marker"];
        AttachmentMarkerTestDelegate *markerWriter =
            [[AttachmentMarkerTestDelegate alloc] init];
        markerWriter.testDefaults =
            [[NSUserDefaults alloc] initWithSuiteName:markerSuiteName];
        markerWriter.testBootSessionID = @"BOOT-A";
        BOOL markerAPIAvailable = [markerWriter respondsToSelector:
            NSSelectorFromString(
                @"rememberUnknownExternalAttachmentForDiskID:volumeUUIDs:")];
        if (markerAPIAvailable) {
            [markerWriter rememberUnknownExternalAttachmentForDiskID:@"disk20"
                volumeUUIDs:@[@"PRIVATE-UUID", @"SIBLING-UUID"]];
        }
        AttachmentMarkerTestDelegate *markerReader =
            [[AttachmentMarkerTestDelegate alloc] init];
        markerReader.testDefaults =
            [[NSUserDefaults alloc] initWithSuiteName:markerSuiteName];
        markerReader.testBootSessionID = @"BOOT-A";
        NSSet<NSString *> *rememberedMarker = markerAPIAvailable
            ? [markerReader rememberedUnknownExternalVolumeUUIDsForDiskID:
                @"disk20"] : [NSSet set];
        markerReader.testBootSessionID = @"BOOT-B";
        NSSet<NSString *> *markerFromAnotherBoot = markerAPIAvailable
            ? [markerReader rememberedUnknownExternalVolumeUUIDsForDiskID:
                @"disk20"] : [NSSet set];
        Assert(markerAPIAvailable &&
               [rememberedMarker isEqualToSet:
                    [NSSet setWithArray:@[@"PRIVATE-UUID", @"SIBLING-UUID"]]] &&
               markerFromAnotherBoot.count == 0,
               @"the attachment marker survives a controller restart but never crosses a system boot");
        markerReader.testBootSessionID = @"BOOT-A";
        if (markerAPIAvailable) {
            [markerReader forgetUnknownExternalAttachmentForDiskID:@"disk20"];
        }
        Assert(!markerAPIAvailable ||
               [markerReader rememberedUnknownExternalVolumeUUIDsForDiskID:
                    @"disk20"].count == 0,
               @"the attachment marker is removed after a full disconnect");

        SEL presentationSelector = NSSelectorFromString(
            @"presentationOptionsForNotificationCategoryIdentifier:");
        UNNotificationPresentationOptions unknownPresentation = 0;
        UNNotificationPresentationOptions failurePresentation = 0;
        if ([delegate respondsToSelector:presentationSelector]) {
            typedef UNNotificationPresentationOptions (*PresentationMethod)(
                id, SEL, NSString *);
            PresentationMethod presentationMethod =
                (PresentationMethod)[delegate methodForSelector:presentationSelector];
            unknownPresentation = presentationMethod(
                delegate, presentationSelector, @"GDT_UNKNOWN_EXTERNAL_VOLUME");
            failurePresentation = presentationMethod(
                delegate, presentationSelector, @"GDT_BACKUP_ALERT");
        }
        Assert((unknownPresentation & UNNotificationPresentationOptionList) != 0 &&
               (unknownPresentation & UNNotificationPresentationOptionSound) == 0 &&
               (failurePresentation & UNNotificationPresentationOptionSound) != 0,
               @"unknown-disk notices stay silent while backup failures remain audible");

        BOOL unknownVolumeLocalized = YES;
        for (NSString *code in SupportedLanguageCodes()) {
            for (NSString *key in @[
                @"unknownExternalVolumeTitle",
                @"unknownExternalVolumeBody",
                @"unknownExternalVolumeSetupAction",
                @"unknownExternalVolumeIgnoreAction",
                @"unknownExternalVolumeReviewSetup",
                @"unknownExternalVolumeUnavailable"
            ]) {
                NSString *localized = T(code, key);
                if (!localized.length || [localized isEqualToString:key]) {
                    unknownVolumeLocalized = NO;
                }
            }
        }
        Assert(unknownVolumeLocalized,
               @"unknown external-volume notification and setup text is localized in every language");

        UnknownVolumeNotificationTestDelegate *unknownActionDelegate =
            [[UnknownVolumeNotificationTestDelegate alloc] init];
        NSDictionary *unknownUserInfo = @{
            @"diskID": @"disk20",
            @"volumeUUID": @"PRIVATE-UUID"
        };
        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE", unknownUserInfo);
        Assert(unknownActionDelegate.revalidationCalls == 0 &&
               unknownActionDelegate.setupPresentationCalls == 0 &&
               unknownActionDelegate.overviewPresentationCalls == 0 &&
               unknownActionDelegate.configSaveCalls == 0 &&
               unknownActionDelegate.backupLaunchCalls == 0,
               @"Ignore dismisses the unknown disk without setup, writes, or a backup");

        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP", unknownUserInfo);
        Assert(unknownActionDelegate.revalidationCalls == 1 &&
               unknownActionDelegate.setupPresentationCalls == 0 &&
               unknownActionDelegate.unavailablePresentationCalls == 1 &&
               unknownActionDelegate.configSaveCalls == 0 &&
               unknownActionDelegate.backupLaunchCalls == 0,
               @"a stale unknown-disk setup action fails closed with visible guidance and no configuration change");

        unknownActionDelegate.revalidatedDescriptor = unknownDescriptor;
        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP", unknownUserInfo);
        ProcessUnknownVolumeAction(
            unknownActionDelegate, UNNotificationDefaultActionIdentifier, unknownUserInfo);
        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"UNEXPECTED_ACTION", unknownUserInfo);
        Assert(unknownActionDelegate.revalidationCalls == 3 &&
               unknownActionDelegate.setupPresentationCalls == 2 &&
               unknownActionDelegate.overviewPresentationCalls == 0 &&
               unknownActionDelegate.configSaveCalls == 0 &&
               unknownActionDelegate.backupLaunchCalls == 0,
               @"only an explicit setup click or notification-body click stages a revalidated disk without saving");

        RestartUnknownVolumeNotificationTestDelegate *mismatchedRestartDelegate =
            [[RestartUnknownVolumeNotificationTestDelegate alloc] init];
        mismatchedRestartDelegate.candidateMountPaths = @[@"/Volumes/Lookalike"];
        mismatchedRestartDelegate.descriptorsByPath = @{
            @"/Volumes/Lookalike": @{
                @"path": @"/Volumes/Lookalike",
                @"name": @"Lookalike",
                @"volumeUUID": @"PRIVATE-UUID",
                @"diskID": @"disk99",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            }
        };
        ProcessUnknownVolumeAction(
            mismatchedRestartDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            unknownUserInfo);
        Assert(mismatchedRestartDelegate.mountEnumerationCalls == 1 &&
               [mismatchedRestartDelegate.inspectedPaths
                   isEqualToArray:@[@"/Volumes/Lookalike"]] &&
               mismatchedRestartDelegate.setupPresentationCalls == 0,
               @"a notification action after restart enumerates mounts but rejects a reused disk ID");

        RestartUnknownVolumeNotificationTestDelegate *matchingRestartDelegate =
            [[RestartUnknownVolumeNotificationTestDelegate alloc] init];
        NSDictionary<NSString *, id> *matchingRestartDescriptor = @{
            @"path": @"/Volumes/TOSHIBA_4TB",
            @"name": @"TOSHIBA_4TB",
            @"volumeUUID": @"PRIVATE-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs"
        };
        matchingRestartDelegate.candidateMountPaths = @[
            @"/Volumes/Lookalike", @"/Volumes/TOSHIBA_4TB"
        ];
        matchingRestartDelegate.descriptorsByPath = @{
            @"/Volumes/Lookalike":
                mismatchedRestartDelegate.descriptorsByPath[@"/Volumes/Lookalike"],
            @"/Volumes/TOSHIBA_4TB": matchingRestartDescriptor
        };
        ProcessUnknownVolumeAction(
            matchingRestartDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            unknownUserInfo);
        Assert(matchingRestartDelegate.mountEnumerationCalls == 1 &&
               matchingRestartDelegate.inspectedPaths.count == 2 &&
               matchingRestartDelegate.setupPresentationCalls == 1 &&
               matchingRestartDelegate.presentedDescriptor == matchingRestartDescriptor,
               @"a notification action after restart stages only the mount whose disk ID and UUID still match");

        RestartUnknownVolumeNotificationTestDelegate *remainingSiblingDelegate =
            [[RestartUnknownVolumeNotificationTestDelegate alloc] init];
        NSDictionary<NSString *, id> *remainingSiblingDescriptor = @{
            @"path": @"/Volumes/TOSHIBA_DATA",
            @"name": @"TOSHIBA_DATA",
            @"volumeUUID": @"SIBLING-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs"
        };
        remainingSiblingDelegate.candidateMountPaths =
            @[@"/Volumes/TOSHIBA_DATA"];
        remainingSiblingDelegate.descriptorsByPath = @{
            @"/Volumes/TOSHIBA_DATA": remainingSiblingDescriptor
        };
        ProcessUnknownVolumeAction(
            remainingSiblingDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            @{
                @"diskID": @"disk20",
                @"volumeUUID": @"PRIVATE-UUID",
                @"attachmentVolumeUUIDs": @[@"PRIVATE-UUID", @"SIBLING-UUID"]
            });
        Assert(remainingSiblingDelegate.setupPresentationCalls == 1 &&
               remainingSiblingDelegate.presentedDescriptor ==
                   remainingSiblingDescriptor,
               @"one retained banner can safely stage a sibling volume after its originally selected volume leaves");

        RestartUnknownVolumeNotificationTestDelegate *mixedSiblingDelegate =
            [[RestartUnknownVolumeNotificationTestDelegate alloc] init];
        NSDictionary<NSString *, id> *unsupportedSiblingDescriptor = @{
            @"path": @"/Volumes/TOSHIBA_SHARE",
            @"name": @"TOSHIBA_SHARE",
            @"volumeUUID": @"SHARE-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"exfat"
        };
        mixedSiblingDelegate.candidateMountPaths = @[
            @"/Volumes/TOSHIBA_SHARE", @"/Volumes/TOSHIBA_4TB"
        ];
        mixedSiblingDelegate.descriptorsByPath = @{
            @"/Volumes/TOSHIBA_SHARE": unsupportedSiblingDescriptor,
            @"/Volumes/TOSHIBA_4TB": matchingRestartDescriptor
        };
        ProcessUnknownVolumeAction(
            mixedSiblingDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            @{
                @"diskID": @"disk20",
                @"volumeUUID": @"PRIVATE-UUID",
                @"attachmentVolumeUUIDs": @[@"PRIVATE-UUID", @"SHARE-UUID"]
            });
        Assert(mixedSiblingDelegate.presentedDescriptor ==
                   matchingRestartDescriptor,
               @"setup action deterministically prefers the originally offered writable APFS volume");

        RestartUnknownVolumeNotificationTestDelegate *lateSiblingActionDelegate =
            [[RestartUnknownVolumeNotificationTestDelegate alloc] init];
        lateSiblingActionDelegate.candidateMountPaths =
            @[@"/Volumes/TOSHIBA_DATA"];
        lateSiblingActionDelegate.descriptorsByPath = @{
            @"/Volumes/TOSHIBA_DATA": remainingSiblingDescriptor
        };
        lateSiblingActionDelegate.rememberedAttachmentUUIDsByDiskID = @{
            @"disk20": [NSSet setWithArray:
                @[@"PRIVATE-UUID", @"SIBLING-UUID"]]
        };
        ProcessUnknownVolumeAction(
            lateSiblingActionDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            unknownUserInfo);
        Assert(lateSiblingActionDelegate.presentedDescriptor ==
                   remainingSiblingDescriptor,
               @"a sibling mounted after delivery remains eligible through the attachment marker");

        UnknownVolumeNotificationTestDelegate *backgroundActionDelegate =
            [[UnknownVolumeNotificationTestDelegate alloc] init];
        backgroundActionDelegate.revalidatedDescriptor = unknownDescriptor;
        __block BOOL backgroundActionReturned = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            ProcessUnknownVolumeAction(
                backgroundActionDelegate,
                @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
                unknownUserInfo);
            dispatch_async(dispatch_get_main_queue(), ^{
                backgroundActionReturned = YES;
            });
        });
        BOOL backgroundActionCompleted = WaitForCondition(^BOOL{
            return backgroundActionReturned &&
                backgroundActionDelegate.setupPresentationCalls == 1;
        }, 2.0);
        Assert(backgroundActionCompleted &&
               backgroundActionDelegate.revalidationCalls == 1 &&
               backgroundActionDelegate.revalidationRanOnMainThread &&
               backgroundActionDelegate.setupPresentationRanOnMainThread,
               @"unknown-volume notification actions revalidate and present setup only on the main thread");

        UnknownVolumeDeliveryTestDelegate *refusedUnknownDelivery =
            [[UnknownVolumeDeliveryTestDelegate alloc] init];
        PrepareUnknownVolumeDeliveryState(refusedUnknownDelivery, unknownDescriptor);
        refusedUnknownDelivery.unknownDeliverySucceeds = NO;
        [refusedUnknownDelivery
            finishUnknownExternalVolumeInspectionForDiskID:@"disk20"];
        BOOL unknownDeliveryRetried = WaitForCondition(^BOOL{
            return refusedUnknownDelivery.completionDeliveryCalls == 2;
        }, 1.0);
        Assert(unknownDeliveryRetried &&
               refusedUnknownDelivery.legacyDeliveryCalls == 0 &&
               ![refusedUnknownDelivery.notifiedUnknownExternalDiskIDs
                   containsObject:@"disk20"],
               @"a failed unknown-disk notification delivery receives one bounded retry without being latched");
        [refusedUnknownDelivery processMountedVolumeDescriptor:unknownDescriptor];
        [NSRunLoop.currentRunLoop
            runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
        Assert(refusedUnknownDelivery.completionDeliveryCalls == 2,
               @"duplicate mount events cannot bypass the two-attempt delivery cap");
        ProcessUnknownVolumeUnmount(
            refusedUnknownDelivery, @"/Volumes/Private Customer Folder");
        [refusedUnknownDelivery processMountedVolumeDescriptor:unknownDescriptor];
        BOOL reconnectedDeliveryRetried = WaitForCondition(^BOOL{
            return refusedUnknownDelivery.completionDeliveryCalls == 4;
        }, 1.0);
        Assert(reconnectedDeliveryRetried,
               @"a full disconnect resets the delivery cap for the next attachment");

        UnknownVolumeDeliveryTestDelegate *acceptedUnknownDelivery =
            [[UnknownVolumeDeliveryTestDelegate alloc] init];
        PrepareUnknownVolumeDeliveryState(acceptedUnknownDelivery, unknownDescriptor);
        acceptedUnknownDelivery.unknownDeliverySucceeds = YES;
        [acceptedUnknownDelivery
            finishUnknownExternalVolumeInspectionForDiskID:@"disk20"];
        [acceptedUnknownDelivery
            finishUnknownExternalVolumeInspectionForDiskID:@"disk20"];
        Assert(acceptedUnknownDelivery.completionDeliveryCalls == 1 &&
               acceptedUnknownDelivery.legacyDeliveryCalls == 0 &&
               [acceptedUnknownDelivery.notifiedUnknownExternalDiskIDs
                   containsObject:@"disk20"],
               @"an unknown disk is marked notified only after macOS accepts the notice");

        UnknownVolumeDeliveryTestDelegate *reusedDiskIDDelivery =
            [[UnknownVolumeDeliveryTestDelegate alloc] init];
        PrepareUnknownVolumeDeliveryState(reusedDiskIDDelivery, unknownDescriptor);
        reusedDiskIDDelivery.unknownDeliverySucceeds = YES;
        reusedDiskIDDelivery.deferUnknownDelivery = YES;
        [reusedDiskIDDelivery
            finishUnknownExternalVolumeInspectionForDiskID:@"disk20"];
        NSDictionary<NSString *, id> *replacementDescriptor = @{
            @"path": @"/Volumes/Replacement",
            @"name": @"Replacement",
            @"volumeUUID": @"REPLACEMENT-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs"
        };
        reusedDiskIDDelivery.mountedExternalVolumeDescriptorsByPath =
            [@{replacementDescriptor[@"path"]: replacementDescriptor} mutableCopy];
        void (^staleCompletion)(BOOL) =
            reusedDiskIDDelivery.deferredUnknownDeliveryCompletion;
        reusedDiskIDDelivery.deferredUnknownDeliveryCompletion = nil;
        reusedDiskIDDelivery.deferUnknownDelivery = NO;
        staleCompletion(YES);
        BOOL replacementWasRetried = WaitForCondition(^BOOL{
            return reusedDiskIDDelivery.completionDeliveryCalls == 2;
        }, 1.0);
        Assert(replacementWasRetried &&
               [reusedDiskIDDelivery.lastUnknownDeliveryDescriptor[@"volumeUUID"]
                   isEqualToString:@"REPLACEMENT-UUID"] &&
               [reusedDiskIDDelivery.notifiedUnknownExternalDiskIDs
                   containsObject:@"disk20"],
               @"a delayed delivery cannot latch a different disk that reused the same disk identifier");

        delegate.extraDeliveredNotificationIdentifiers = @[
            @"com.commcats.gdrivebackup.office.missed.50"
        ];
        [delegate.testDefaults setDouble:200
            forKey:@"GDTBackupNotification.office.activeIssueAt"];
        SEL clearSelector = NSSelectorFromString(
            @"clearBackupFailureNotificationsForConfig:summary:status:");
        if ([delegate respondsToSelector:clearSelector]) {
            typedef void (*ClearMethod)(id, SEL, NSDictionary *, NSDictionary *, NSString *);
            ClearMethod clearMethod = (ClearMethod)[delegate methodForSelector:clearSelector];
            clearMethod(delegate, clearSelector,
                        @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
                        @{@"status": @"success", @"finished_at": @"400",
                          @"trigger": @"manual"},
                        @"success");
            Assert(delegate.removedNotificationIdentifiers == nil,
                   @"a manual success leaves the persistent automatic-failure alert visible");
            clearMethod(delegate, clearSelector,
                        @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
                        @{@"status": @"success", @"finished_at": @"199",
                          @"trigger": @"schedule"},
                        @"success");
            Assert(delegate.removedNotificationIdentifiers == nil,
                   @"an automatic success older than the current issue cannot clear its alert");
            clearMethod(delegate, clearSelector,
                        @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
                        @{@"status": @"success", @"finished_at": @"400",
                          @"trigger": @"schedule-retry"},
                        @"success");
        }
        Assert(delegate.removedNotificationIdentifiers.count == 3 &&
               [delegate.removedNotificationIdentifiers
                   containsObject:@"com.commcats.gdrivebackup.office.failure.100"] &&
               [delegate.removedNotificationIdentifiers
                   containsObject:@"com.commcats.gdrivebackup.office.failure.200"] &&
               [delegate.removedNotificationIdentifiers
                   containsObject:@"com.commcats.gdrivebackup.office.missed.50"],
               @"a later automatic success removes every delivered failure alert for that profile");

        SEL alertStatusSelector = NSSelectorFromString(
            @"backupAlertStatusForConfig:summary:rawStatus:decision:");
        typedef NSString *(*AlertStatusMethod)(id, SEL, NSDictionary *, NSDictionary *,
                                               NSString *, NSDictionary *);
        AlertStatusMethod alertStatus = [delegate respondsToSelector:alertStatusSelector]
            ? (AlertStatusMethod)[delegate methodForSelector:alertStatusSelector] : NULL;
        NSDictionary *profileConfig = @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"};
        NSDictionary *missedDecision = @{
            @"identifier": @"missed.100", @"profileID": @"office",
            @"kind": @"missed", @"issueTimestamp": @"100"
        };
        NSString *missedStatus = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{}, @"unknown", missedDecision) : nil;
        NSString *stillMissedWhileRunning = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{}, @"running", nil) : nil;
        NSString *manualDoesNotClearMissed = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"finished_at": @"150", @"trigger": @"manual"},
            @"success", nil) : nil;
        NSString *clearedMissed = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"finished_at": @"150", @"trigger": @"schedule"},
            @"success", nil) : nil;
        Assert([missedStatus isEqualToString:@"missed"] &&
               [stillMissedWhileRunning isEqualToString:@"missed"] &&
               [manualDoesNotClearMissed isEqualToString:@"missed"] &&
               [clearedMissed isEqualToString:@"success"],
               @"a missed-run warning stays active until a later automatic success");

        NSDictionary *failureDecision = @{
            @"identifier": @"failure.200", @"profileID": @"office",
            @"kind": @"failure", @"issueTimestamp": @"200"
        };
        NSString *failureStatus = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{}, @"failure", failureDecision) : nil;
        NSString *oldSuccessDoesNotClear = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"finished_at": @"199", @"trigger": @"schedule"},
            @"success", nil) : nil;
        NSString *manualNewSuccessDoesNotClear = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"finished_at": @"250", @"trigger": @"manual"},
            @"success", nil) : nil;
        NSString *newSuccessClears = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"finished_at": @"250", @"trigger": @"schedule-retry"},
            @"success", nil) : nil;
        Assert([failureStatus isEqualToString:@"failure"] &&
               [oldSuccessDoesNotClear isEqualToString:@"failure"] &&
               [manualNewSuccessDoesNotClear isEqualToString:@"failure"] &&
               [newSuccessClears isEqualToString:@"success"],
               @"only a newer automatic success clears the red status latch");

        NSDictionary *enabledConfig = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"reactivate",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"1"
        };
        NSDictionary *firstMonitoringWindow = [delegate
            notificationMonitoringConfigForConfig:enabledConfig
                                               now:[NSDate dateWithTimeIntervalSince1970:100]];
        NSMutableDictionary *disabledConfig = [enabledConfig mutableCopy];
        disabledConfig[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] = @"0";
        [delegate notificationMonitoringConfigForConfig:disabledConfig
                                                    now:[NSDate dateWithTimeIntervalSince1970:150]];
        NSDictionary *reactivatedWindow = [delegate
            notificationMonitoringConfigForConfig:enabledConfig
                                               now:[NSDate dateWithTimeIntervalSince1970:200]];
        Assert([firstMonitoringWindow[@"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT"]
                   isEqualToString:@"100"] &&
               [reactivatedWindow[@"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT"]
                   isEqualToString:@"200"],
               @"re-enabling notifications starts a fresh window without retroactive warnings");

        NSString *configPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-notification-config-%@", NSUUID.UUID.UUIDString]];
        NSString *summaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-notification-summary-%@", NSUUID.UUID.UUIDString]];
        [@"GDRIVE_BACKUP_PROFILE_ID=office\nGDRIVE_BACKUP_SCHEDULE=daily\nGDRIVE_BACKUP_NOTIFY_FAILURES=1\nGDRIVE_BACKUP_TARGET=nas\n"
            writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSTimeInterval current = NSDate.date.timeIntervalSince1970;
        NSString *summaryText = [NSString stringWithFormat:
            @"protocol=1\nstatus=failure\npid=123\nstarted_at=%.0f\nfinished_at=%.0f\nexit_code=1\ntrigger=schedule\nreason=nas_connection_lost\n",
            current - 120, current - 60];
        [summaryText writeToFile:summaryPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        setenv("GDRIVE_BACKUP_CONFIG", configPath.UTF8String, 1);
        setenv("GDRIVE_BACKUP_SUMMARY_STATE_FILE", summaryPath.UTF8String, 1);

        NotificationRefreshDelegate *refreshDelegate = [[NotificationRefreshDelegate alloc] init];
        refreshDelegate.language = @"en";
        refreshDelegate.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".refresh"]];
        [refreshDelegate.testDefaults setDouble:current - 24 * 60 * 60
            forKey:@"GDTBackupNotification.office.monitorStartedAt"];
        [refreshDelegate refreshOverviewStatus:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!refreshDelegate.capturedDecision && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert([refreshDelegate.capturedDecision[@"kind"] isEqualToString:@"failure"] &&
               [refreshDelegate.capturedDecision[@"bodyKey"]
                   isEqualToString:@"failedNASConnectionHint"],
               @"each status refresh evaluates the current run for a failure notification");

        summaryText = [NSString stringWithFormat:
            @"protocol=1\nstatus=failure\npid=124\nstarted_at=%.0f\nfinished_at=%.0f\nexit_code=69\ntrigger=schedule\ntarget=nas\nreason=nas_mount_not_ready\n",
            current - 2000, current - 1900];
        [summaryText writeToFile:summaryPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [refreshDelegate refreshOverviewStatus:nil];
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!refreshDelegate.capturedRetryDecision &&
               [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert([refreshDelegate.capturedRetryDecision[@"attempt"] isEqualToString:@"1"] &&
               [refreshDelegate.capturedRetryDecision[@"trigger"]
                   isEqualToString:@"schedule-retry"],
               @"status refresh launches the bounded retry policy for an overdue transient failure");
        [refreshDelegate.overviewRefreshTimer invalidate];
        unsetenv("GDRIVE_BACKUP_CONFIG");
        unsetenv("GDRIVE_BACKUP_SUMMARY_STATE_FILE");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:configPath]
                                    resultingItemURL:nil error:nil];
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:summaryPath]
                                    resultingItemURL:nil error:nil];

        [delegate.testDefaults removePersistentDomainForName:suiteName];
        [markerWriter.testDefaults
            removePersistentDomainForName:markerSuiteName];
    }

    if (failures > 0) {
        printf("%d notification integration test(s) failed.\n", failures);
        return 1;
    }
    printf("All notification integration tests passed.\n");
    return 0;
}
