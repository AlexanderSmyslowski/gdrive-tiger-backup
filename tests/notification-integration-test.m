#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#import "TestApplicationSupport.h"

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

static UNUserNotificationCenter *GDTNotificationIntegrationCurrentCenter;

@interface UNUserNotificationCenter (NotificationIntegrationTesting)
+ (UNUserNotificationCenter *)gdt_notificationIntegrationCurrentCenter;
@end

@implementation UNUserNotificationCenter (NotificationIntegrationTesting)

+ (UNUserNotificationCenter *)gdt_notificationIntegrationCurrentCenter {
    return GDTNotificationIntegrationCurrentCenter;
}

@end

@interface AppDelegate (NotificationIntegrationTesting)
- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision;
- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (BOOL)isBackupSuccessDecisionCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (BOOL)isBackupSuccessDecisionSourceCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (void)processAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (NSUserDefaults *)backupNotificationDefaultsStore;
- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion;
- (void)deliverBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
                             capturedActiveIssueTimestamp:
    (NSTimeInterval)capturedActiveIssueTimestamp
                                          completion:(void (^)(BOOL delivered))completion;
- (UNUserNotificationCenter *)backupNotificationCenter;
- (void)configureBackupNotificationsForConfig:
    (NSDictionary<NSString *, NSString *> *)config;
- (void)requestBackupNotificationAuthorizationIfNeededForConfig:
    (NSDictionary<NSString *, NSString *> *)config;
- (UNMutableNotificationContent *)backupNotificationContentForDecision:
    (NSDictionary<NSString *, NSString *> *)decision;
- (BOOL)timeSensitiveBackupNotificationsEnabled;
- (void)removeExactBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                      forProfileID:(NSString *)profileID;
- (void)removeDeliveredBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removePendingBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)enumerateDeliveredBackupNotificationsWithCompletion:
    (void (^)(NSArray<UNNotification *> *notifications))completion;
- (void)enumeratePendingBackupNotificationRequestsWithCompletion:
    (void (^)(NSArray<UNNotificationRequest *> *requests))completion;
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
- (void)handleBackupNotificationActionIdentifier:(NSString *)actionIdentifier
                              categoryIdentifier:(NSString *)categoryIdentifier
                                        userInfo:(NSDictionary *)userInfo
                          notificationIdentifier:(NSString *)notificationIdentifier;
- (UNMutableNotificationContent *)unknownExternalVolumeNotificationContentForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor;
- (UNNotificationPresentationOptions)presentationOptionsForNotificationCategoryIdentifier:
    (NSString *)categoryIdentifier;
- (void)handleUnknownExternalVolumeActionIdentifier:(NSString *)actionIdentifier
                                           userInfo:(NSDictionary *)userInfo;
- (void)revalidateUnknownExternalVolumeCandidatesForUserInfo:(NSDictionary *)userInfo
                                                  completion:
    (void (^)(NSArray<NSDictionary<NSString *, id> *> *descriptors))completion;
- (void)chooseUnknownExternalVolumeFromDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors
                                         completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion;
- (void)revalidateSelectedUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                               completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion;
- (NSArray<NSString *> *)unknownExternalVolumeChoiceLabelsForDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors;
- (void)finishUnknownExternalVolumeInspectionForDiskID:(NSString *)diskID;
- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID;
- (void)rememberUnknownExternalAttachmentForDiskID:(NSString *)diskID
                                        volumeUUIDs:(NSArray<NSString *> *)volumeUUIDs;
- (void)forgetUnknownExternalAttachmentForDiskID:(NSString *)diskID;
@end

@interface TestNotificationEnvelope : NSObject
@property(nonatomic, strong) UNNotificationRequest *request;
@end

@implementation TestNotificationEnvelope
@end

@interface TestNotificationResponse : NSObject
@property(nonatomic, copy) NSString *actionIdentifier;
@property(nonatomic, strong) TestNotificationEnvelope *notification;
@end

@implementation TestNotificationResponse
@end

@interface NotificationTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic) BOOL useRealSuccessSourceValidation;
@property(nonatomic) NSInteger deliveryCalls;
@property(nonatomic) BOOL deliverySucceeds;
@property(nonatomic) BOOL testTimeSensitiveNotificationsEnabled;
@property(nonatomic) BOOL deferBackupDelivery;
@property(nonatomic, strong) NSMutableArray<void (^)(BOOL)> *deferredBackupDeliveryCompletions;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
    acceptedBackupDecisionsByIdentifier;
@property(nonatomic, copy) NSArray<NSString *> *removedNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *removedDeliveredNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *removedPendingNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *extraDeliveredNotificationIdentifiers;
@property(nonatomic, copy) NSArray<UNNotification *> *extraDeliveredBackupNotifications;
@property(nonatomic, copy) NSArray<UNNotificationRequest *> *extraPendingBackupNotificationRequests;
@property(nonatomic, copy) NSArray<UNNotificationRequest *> *pendingToDeliveredTransitionRequests;
@property(nonatomic) BOOL successDeliveredEnumerationObserved;
@property(nonatomic) BOOL deferPendingSuccessEnumeration;
@property(nonatomic, copy) void (^deferredPendingSuccessEnumeration)(
    NSArray<UNNotificationRequest *> *requests);
@end

@interface BackupRemovalSeamTestDelegate : AppDelegate
@property(nonatomic, copy) NSArray<NSString *> *removedDeliveredNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *removedPendingNotificationIdentifiers;
@end

@interface BackupCleanupRaceTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic, copy) NSArray<NSString *> *removedDeliveredNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *removedPendingNotificationIdentifiers;
@property(nonatomic, copy) void (^deferredDeliveredEnumeration)(
    NSArray<UNNotification *> *notifications);
@end

@interface BackupSuccessPreAddRaceSettings : NSObject
@property(nonatomic) UNAuthorizationStatus authorizationStatus;
@end

@interface BackupSuccessPreAddRaceCenter : NSObject
@property(nonatomic, strong) BackupSuccessPreAddRaceSettings *settings;
@property(nonatomic) BOOL deferSettings;
@property(nonatomic) BOOL deferAuthorization;
@property(nonatomic) NSInteger authorizationRequests;
@property(nonatomic) NSInteger addRequestCalls;
@property(nonatomic) BOOL addRequestRanOnMainThread;
@property(nonatomic, copy) void (^deferredSettingsCompletion)(UNNotificationSettings *settings);
@property(nonatomic, copy) void (^deferredAuthorizationCompletion)(BOOL granted, NSError *error);
@end

@interface BackupSuccessPreAddRaceTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic, strong) BackupSuccessPreAddRaceCenter *testNotificationCenter;
@property(nonatomic) BOOL useRealSuccessSourceValidation;
@end

@interface BackupNotificationAuthorizationSettings : NSObject
@property(nonatomic) UNAuthorizationStatus authorizationStatus;
@end

@interface BackupNotificationAuthorizationCenter : NSObject
@property(nonatomic, weak) id delegate;
@property(nonatomic, strong) BackupNotificationAuthorizationSettings *settings;
@property(nonatomic) NSInteger setCategoriesCalls;
@property(nonatomic) NSInteger authorizationRequests;
@property(nonatomic) NSInteger addRequestCalls;
@end

@interface BackupNotificationAuthorizationTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic, strong) BackupNotificationAuthorizationCenter *testNotificationCenter;
@end

@interface UnknownVolumeNotificationTestDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *revalidatedCandidates;
@property(nonatomic, copy) NSDictionary<NSString *, id> *chosenDescriptor;
@property(nonatomic, copy) NSDictionary<NSString *, id> *postChoiceDescriptor;
@property(nonatomic) NSInteger revalidationCalls;
@property(nonatomic) NSInteger choiceCalls;
@property(nonatomic) NSInteger selectedRevalidationCalls;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *choiceCandidates;
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

- (void)revalidateUnknownExternalVolumeCandidatesForUserInfo:(NSDictionary *)userInfo
                                                  completion:
    (void (^)(NSArray<NSDictionary<NSString *, id> *> *descriptors))completion {
    (void)userInfo;
    self.revalidationCalls++;
    self.revalidationRanOnMainThread = NSThread.isMainThread;
    completion(self.revalidatedCandidates ?: @[]);
}

- (void)chooseUnknownExternalVolumeFromDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors
                                         completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    self.choiceCalls++;
    self.choiceCandidates = descriptors;
    completion(self.chosenDescriptor);
}

- (void)revalidateSelectedUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                               completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    (void)descriptor;
    self.selectedRevalidationCalls++;
    completion(self.postChoiceDescriptor);
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
@property(nonatomic) NSInteger unavailablePresentationCalls;
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

- (void)presentUnknownExternalVolumeUnavailable {
    self.unavailablePresentationCalls++;
}

- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID {
    return self.rememberedAttachmentUUIDsByDiskID[diskID] ?: [NSSet set];
}

@end


@interface PickerUnknownVolumeNotificationTestDelegate : RestartUnknownVolumeNotificationTestDelegate
@property(nonatomic) NSInteger choiceCalls;
@property(nonatomic) NSInteger selectedCandidateIndex;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *choiceCandidates;
@property(nonatomic, copy) NSDictionary<NSString *, NSDictionary<NSString *, id> *> *
    descriptorsByPathBeforeChoiceCompletion;
@end

@implementation PickerUnknownVolumeNotificationTestDelegate

- (void)chooseUnknownExternalVolumeFromDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors
                                         completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    self.choiceCalls++;
    self.choiceCandidates = descriptors;
    if (self.descriptorsByPathBeforeChoiceCompletion) {
        self.descriptorsByPath = self.descriptorsByPathBeforeChoiceCompletion;
    }
    if (self.selectedCandidateIndex < 0 ||
        (NSUInteger)self.selectedCandidateIndex >= descriptors.count) {
        completion(nil);
        return;
    }
    completion(descriptors[(NSUInteger)self.selectedCandidateIndex]);
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

- (BOOL)timeSensitiveBackupNotificationsEnabled {
    return self.testTimeSensitiveNotificationsEnabled;
}

- (BOOL)isBackupSuccessDecisionSourceCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    if (!self.useRealSuccessSourceValidation) return YES;
    return [super isBackupSuccessDecisionSourceCurrent:decision
                          capturedActiveIssueTimestamp:capturedActiveIssueTimestamp];
}

- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion {
    self.deliveryCalls++;
    NSDictionary<NSString *, NSString *> *capturedDecision = [decision copy];
    __weak typeof(self) weakSelf = self;
    void (^finish)(BOOL) = ^(BOOL delivered) {
        typeof(self) strongSelf = weakSelf;
        if (delivered && capturedDecision[@"identifier"].length) {
            if (!strongSelf.acceptedBackupDecisionsByIdentifier) {
                strongSelf.acceptedBackupDecisionsByIdentifier =
                    [NSMutableDictionary dictionary];
            }
            strongSelf.acceptedBackupDecisionsByIdentifier[
                capturedDecision[@"identifier"]] = capturedDecision;
        }
        completion(delivered);
    };
    if (self.deferBackupDelivery) {
        if (!self.deferredBackupDeliveryCompletions) {
            self.deferredBackupDeliveryCompletions = [NSMutableArray array];
        }
        [self.deferredBackupDeliveryCompletions addObject:[finish copy]];
        return;
    }
    finish(self.deliverySucceeds);
}

- (void)deliverBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
                             capturedActiveIssueTimestamp:
    (NSTimeInterval)capturedActiveIssueTimestamp
                                          completion:(void (^)(BOOL delivered))completion {
    (void)capturedActiveIssueTimestamp;
    [self deliverBackupNotificationDecision:decision completion:completion];
}

- (void)enumerateDeliveredBackupNotificationsWithCompletion:
    (void (^)(NSArray<UNNotification *> *notifications))completion {
    self.successDeliveredEnumerationObserved = YES;
    if (self.extraDeliveredBackupNotifications) {
        completion(self.extraDeliveredBackupNotifications);
        return;
    }
    NSMutableArray<UNNotification *> *notifications = [NSMutableArray array];
    for (NSString *identifier in self.extraDeliveredNotificationIdentifiers ?: @[]) {
        UNMutableNotificationContent *content =
            [[UNMutableNotificationContent alloc] init];
        TestNotificationEnvelope *envelope = [[TestNotificationEnvelope alloc] init];
        envelope.request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                content:content
                                                                trigger:nil];
        [notifications addObject:(UNNotification *)envelope];
    }
    completion(notifications);
}

- (void)enumeratePendingBackupNotificationRequestsWithCompletion:
    (void (^)(NSArray<UNNotificationRequest *> *requests))completion {
    if (self.deferPendingSuccessEnumeration) {
        self.deferredPendingSuccessEnumeration = completion;
        return;
    }
    if (self.pendingToDeliveredTransitionRequests) {
        completion(self.successDeliveredEnumerationObserved ? @[] :
                   self.pendingToDeliveredTransitionRequests);
        return;
    }
    completion(self.extraPendingBackupNotificationRequests ?: @[]);
}

- (void)removeDeliveredBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedDeliveredNotificationIdentifiers = identifiers;
    self.removedNotificationIdentifiers = identifiers;
    [self.acceptedBackupDecisionsByIdentifier removeObjectsForKeys:identifiers];
}

- (void)removePendingBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedPendingNotificationIdentifiers = identifiers;
    self.removedNotificationIdentifiers = identifiers;
}

@end


@implementation BackupRemovalSeamTestDelegate

- (void)removeDeliveredBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedDeliveredNotificationIdentifiers = identifiers;
}

- (void)removePendingBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedPendingNotificationIdentifiers = identifiers;
}

@end

@implementation BackupCleanupRaceTestDelegate

- (NSUserDefaults *)backupNotificationDefaultsStore {
    return self.testDefaults;
}

- (void)enumerateDeliveredBackupNotificationsWithCompletion:
    (void (^)(NSArray<UNNotification *> *notifications))completion {
    self.deferredDeliveredEnumeration = completion;
}

- (void)removeDeliveredBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedDeliveredNotificationIdentifiers = identifiers;
}

- (void)removePendingBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers {
    self.removedPendingNotificationIdentifiers = identifiers;
}

@end

@implementation BackupSuccessPreAddRaceSettings
@end

@implementation BackupSuccessPreAddRaceCenter

- (void)getNotificationSettingsWithCompletionHandler:
    (void (^)(UNNotificationSettings *settings))completionHandler {
    if (self.deferSettings) {
        self.deferredSettingsCompletion = completionHandler;
        return;
    }
    completionHandler((UNNotificationSettings *)(id)self.settings);
}

- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL granted, NSError *error))completionHandler {
    (void)options;
    self.authorizationRequests++;
    if (self.deferAuthorization) {
        self.deferredAuthorizationCompletion = completionHandler;
        return;
    }
    completionHandler(YES, nil);
}

- (void)addNotificationRequest:(UNNotificationRequest *)request
          withCompletionHandler:(void (^)(NSError *error))completionHandler {
    (void)request;
    self.addRequestCalls++;
    self.addRequestRanOnMainThread = NSThread.isMainThread;
    completionHandler(nil);
}

@end

@implementation BackupSuccessPreAddRaceTestDelegate

- (NSUserDefaults *)backupNotificationDefaultsStore {
    return self.testDefaults;
}

- (UNUserNotificationCenter *)backupNotificationCenter {
    return (UNUserNotificationCenter *)(id)self.testNotificationCenter;
}

- (BOOL)isBackupSuccessDecisionSourceCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    if (!self.useRealSuccessSourceValidation) return YES;
    return [super isBackupSuccessDecisionSourceCurrent:decision
                          capturedActiveIssueTimestamp:capturedActiveIssueTimestamp];
}

@end

@implementation BackupNotificationAuthorizationSettings
@end

@implementation BackupNotificationAuthorizationCenter

- (void)setNotificationCategories:(NSSet<UNNotificationCategory *> *)categories {
    (void)categories;
    self.setCategoriesCalls++;
}

- (void)getNotificationSettingsWithCompletionHandler:
    (void (^)(UNNotificationSettings *settings))completionHandler {
    completionHandler((UNNotificationSettings *)(id)self.settings);
}

- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL granted, NSError *error))completionHandler {
    (void)options;
    self.authorizationRequests++;
    completionHandler(YES, nil);
}

- (void)addNotificationRequest:(UNNotificationRequest *)request
          withCompletionHandler:(void (^)(NSError *error))completionHandler {
    (void)request;
    self.addRequestCalls++;
    completionHandler(nil);
}

@end

@implementation BackupNotificationAuthorizationTestDelegate

- (NSUserDefaults *)backupNotificationDefaultsStore {
    return self.testDefaults;
}

- (UNUserNotificationCenter *)backupNotificationCenter {
    return (UNUserNotificationCenter *)(id)self.testNotificationCenter;
}

@end

@interface BackupActionTestDelegate : NotificationTestDelegate
@property(nonatomic) NSInteger overviewShowCalls;
@property(nonatomic) NSInteger overviewRefreshCalls;
@property(nonatomic) NSInteger backupLaunchCalls;
@end

@implementation BackupActionTestDelegate

- (void)showOverviewWindow {
    self.overviewShowCalls++;
}

- (void)refreshOverviewStatus:(id)sender {
    (void)sender;
    self.overviewRefreshCalls++;
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
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *capturedSuccessDecision;
@property(nonatomic) BOOL clearedFailuresBeforeSuccessProcessing;
@end

@implementation NotificationRefreshDelegate

- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.capturedDecision = decision;
}

- (void)processAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.capturedRetryDecision = decision;
}

- (void)clearBackupFailureNotificationsForConfig:
    (NSDictionary<NSString *, NSString *> *)config
    summary:(NSDictionary<NSString *, NSString *> *)summary
    status:(NSString *)status {
    (void)config;
    (void)summary;
    (void)status;
    self.clearedFailuresBeforeSuccessProcessing = YES;
}

- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    (void)capturedActiveIssueTimestamp;
    if (self.clearedFailuresBeforeSuccessProcessing) {
        self.capturedSuccessDecision = decision;
    }
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

static void ProcessSuccess(NotificationTestDelegate *delegate,
                           NSDictionary<NSString *, NSString *> *decision) {
    SEL selector = NSSelectorFromString(@"processBackupSuccessNotificationDecision:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*ProcessMethod)(id, SEL, NSDictionary *);
    ProcessMethod method = (ProcessMethod)[delegate methodForSelector:selector];
    method(delegate, selector, decision);
}

static void ProcessSuccessWithCapturedIssue(
    NotificationTestDelegate *delegate, NSDictionary<NSString *, NSString *> *decision,
    NSTimeInterval capturedActiveIssueTimestamp, BOOL *available) {
    SEL selector = NSSelectorFromString(
        @"processBackupSuccessNotificationDecision:capturedActiveIssueTimestamp:");
    if (![delegate respondsToSelector:selector]) {
        *available = NO;
        return;
    }
    *available = YES;
    typedef void (*ProcessMethod)(id, SEL, NSDictionary *, NSTimeInterval);
    ProcessMethod method = (ProcessMethod)[delegate methodForSelector:selector];
    method(delegate, selector, decision, capturedActiveIssueTimestamp);
}

static BOOL SuccessDecisionIsCurrent(NotificationTestDelegate *delegate,
                                     NSDictionary<NSString *, NSString *> *decision,
                                     NSTimeInterval capturedActiveIssueTimestamp,
                                     BOOL *available) {
    SEL selector = NSSelectorFromString(
        @"isBackupSuccessDecisionCurrent:capturedActiveIssueTimestamp:");
    if (![delegate respondsToSelector:selector]) {
        *available = NO;
        return NO;
    }
    *available = YES;
    typedef BOOL (*CurrentMethod)(id, SEL, NSDictionary *, NSTimeInterval);
    CurrentMethod method = (CurrentMethod)[delegate methodForSelector:selector];
    return method(delegate, selector, decision, capturedActiveIssueTimestamp);
}

static void ProcessRetry(RetryTestDelegate *delegate,
                         NSDictionary<NSString *, NSString *> *decision) {
    SEL selector = NSSelectorFromString(@"processAutomaticRetryDecision:");
    if (![delegate respondsToSelector:selector]) return;
    typedef void (*ProcessMethod)(id, SEL, NSDictionary *);
    ProcessMethod method = (ProcessMethod)[delegate methodForSelector:selector];
    method(delegate, selector, decision);
}

static void HandleBackupAction(id delegate, NSString *action,
                               NSString *category, NSDictionary *userInfo,
                               NSString *identifier) {
    SEL selector = NSSelectorFromString(
        @"handleBackupNotificationActionIdentifier:categoryIdentifier:userInfo:notificationIdentifier:");
    typedef void (*ActionMethod)(id, SEL, NSString *, NSString *,
                                 NSDictionary *, NSString *);
    ActionMethod method = [delegate respondsToSelector:selector]
        ? (ActionMethod)[delegate methodForSelector:selector] : NULL;
    if (method) method(delegate, selector, action, category, userInfo, identifier);
}

static BOOL RouteBackupResponse(AppDelegate *delegate, NSString *action,
                                NSString *category, NSDictionary *userInfo,
                                NSString *identifier) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.categoryIdentifier = category;
    content.userInfo = userInfo;
    TestNotificationEnvelope *notification = [[TestNotificationEnvelope alloc] init];
    notification.request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                 content:content
                                                                 trigger:nil];
    TestNotificationResponse *response = [[TestNotificationResponse alloc] init];
    response.actionIdentifier = action;
    response.notification = notification;
    __block BOOL completed = NO;
    UNUserNotificationCenter *unusedCenter =
        (UNUserNotificationCenter *)(id)[NSObject new];
    [delegate userNotificationCenter:unusedCenter
      didReceiveNotificationResponse:(UNNotificationResponse *)(id)response
               withCompletionHandler:^{ completed = YES; }];
    return completed;
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

static UNNotification *DeliveredBackupNotification(
    NSString *identifier, NSString *categoryIdentifier, NSDictionary *userInfo) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.categoryIdentifier = categoryIdentifier ?: @"";
    content.userInfo = userInfo ?: @{};
    TestNotificationEnvelope *envelope = [[TestNotificationEnvelope alloc] init];
    envelope.request = [UNNotificationRequest requestWithIdentifier:identifier
                                                            content:content
                                                            trigger:nil];
    return (UNNotification *)envelope;
}

static UNNotificationRequest *PendingBackupNotificationRequest(
    NSString *identifier, NSString *categoryIdentifier, NSDictionary *userInfo) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.categoryIdentifier = categoryIdentifier ?: @"";
    content.userInfo = userInfo ?: @{};
    return [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:nil];
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

        NSDictionary<NSString *, NSString *> *firstSuccess = @{
            @"identifier": @"com.commcats.gdrivebackup.office.success.200",
            @"profileID": @"office",
            @"kind": @"success",
            @"eventTimestamp": @"200",
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationRecoverySuccessBody"
        };
        NotificationTestDelegate *deferredSuccess = [[NotificationTestDelegate alloc] init];
        NSString *successSuiteName = [suiteName stringByAppendingString:@".success"];
        deferredSuccess.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:successSuiteName];
        deferredSuccess.deliverySucceeds = YES;
        deferredSuccess.deferBackupDelivery = YES;
        ProcessSuccess(deferredSuccess, firstSuccess);
        Assert(deferredSuccess.deliveryCalls == 1 &&
               [deferredSuccess.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 0 &&
               deferredSuccess.deferredBackupDeliveryCompletions.count == 1,
               @"a success is persisted only after Notification Center accepts it");
        if (deferredSuccess.deferredBackupDeliveryCompletions.count == 1) {
            void (^finishSuccess)(BOOL) =
                deferredSuccess.deferredBackupDeliveryCompletions[0];
            finishSuccess(YES);
        }
        deferredSuccess.deferBackupDelivery = NO;
        ProcessSuccess(deferredSuccess, firstSuccess);
        Assert(deferredSuccess.deliveryCalls == 1 &&
               [deferredSuccess.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 200 &&
               [[deferredSuccess.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessIdentifier"]
                       isEqualToString:firstSuccess[@"identifier"]],
               @"accepted successes are monotonic and do not redeliver during the same refresh");

        NotificationTestDelegate *restartedSuccess = [[NotificationTestDelegate alloc] init];
        restartedSuccess.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:successSuiteName];
        restartedSuccess.deliverySucceeds = YES;
        ProcessSuccess(restartedSuccess, firstSuccess);
        Assert(restartedSuccess.deliveryCalls == 0,
               @"a controller restart does not redeliver an accepted success");

        NotificationTestDelegate *dismissedRecovery = [[NotificationTestDelegate alloc] init];
        dismissedRecovery.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".dismissed-recovery"]];
        dismissedRecovery.deliverySucceeds = YES;
        [dismissedRecovery.testDefaults setDouble:100 forKey:
            @"GDTBackupNotification.office.dismissedIssueAt"];
        BOOL currentGateAvailable = NO;
        BOOL dismissedRecoveryIsCurrent = SuccessDecisionIsCurrent(
            dismissedRecovery, firstSuccess, 100, &currentGateAvailable);
        if (dismissedRecoveryIsCurrent) ProcessSuccess(dismissedRecovery, firstSuccess);
        Assert(currentGateAvailable && !dismissedRecoveryIsCurrent &&
               dismissedRecovery.deliveryCalls == 0,
               @"a dismissal after capture suppresses the stale recovery before delivery");

        NotificationTestDelegate *newerIssueRecovery = [[NotificationTestDelegate alloc] init];
        newerIssueRecovery.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".newer-issue-recovery"]];
        newerIssueRecovery.deliverySucceeds = YES;
        [newerIssueRecovery.testDefaults setDouble:300 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        BOOL newerIssueCurrent = SuccessDecisionIsCurrent(
            newerIssueRecovery, firstSuccess, 100, &currentGateAvailable);
        if (newerIssueCurrent) ProcessSuccess(newerIssueRecovery, firstSuccess);
        Assert(currentGateAvailable && !newerIssueCurrent &&
               newerIssueRecovery.deliveryCalls == 0,
               @"a newer active issue suppresses a stale recovery before delivery");

        NotificationTestDelegate *newerAcceptedIssue = [[NotificationTestDelegate alloc] init];
        newerAcceptedIssue.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".newer-accepted-issue"]];
        newerAcceptedIssue.deliverySucceeds = YES;
        [newerAcceptedIssue.testDefaults setObject:@{ @"origin": @300, @"stage": @1 }
            forKey:@"GDTBackupNotification.office.latestDeliveredIssueState"];
        NSDictionary<NSString *, NSString *> *routineSuccess = @{
            @"identifier": @"com.commcats.gdrivebackup.office.success.200",
            @"profileID": @"office",
            @"kind": @"success",
            @"eventTimestamp": @"200",
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationSuccessBody"
        };
        BOOL routineCurrent = SuccessDecisionIsCurrent(
            newerAcceptedIssue, routineSuccess, 0, &currentGateAvailable);
        if (routineCurrent) ProcessSuccess(newerAcceptedIssue, routineSuccess);
        Assert(currentGateAvailable && !routineCurrent &&
               newerAcceptedIssue.deliveryCalls == 0,
               @"a routine success cannot claim current state over a newer accepted issue");

        NotificationTestDelegate *equalAcceptedIssue = [[NotificationTestDelegate alloc] init];
        equalAcceptedIssue.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".equal-accepted-issue"]];
        equalAcceptedIssue.deliverySucceeds = YES;
        [equalAcceptedIssue.testDefaults setObject:@{ @"origin": @200, @"stage": @1 }
            forKey:@"GDTBackupNotification.office.latestDeliveredIssueState"];
        BOOL equalRecoveryCurrent = SuccessDecisionIsCurrent(
            equalAcceptedIssue, firstSuccess, 100, &currentGateAvailable);
        if (equalRecoveryCurrent) ProcessSuccess(equalAcceptedIssue, firstSuccess);
        Assert(currentGateAvailable && !equalRecoveryCurrent &&
               equalAcceptedIssue.deliveryCalls == 0,
               @"a recovery must be strictly newer than an accepted issue");

        NSTimeInterval sourceNow = floor(NSDate.date.timeIntervalSince1970);
        NSTimeInterval sourceStartedAt = sourceNow - 120;
        NSTimeInterval sourceFinishedAt = sourceNow - 60;
        NSString *sourceConfigPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:
                @"gdrive-success-source-config-%@", NSUUID.UUID.UUIDString]];
        NSString *sourceSummaryPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:
                @"gdrive-success-source-summary-%@", NSUUID.UUID.UUIDString]];
        NSString *enabledSuccessConfig =
            @"GDRIVE_BACKUP_PROFILE_ID=office\n"
             "GDRIVE_BACKUP_SCHEDULE=daily\n"
             "GDRIVE_BACKUP_NOTIFY_FAILURES=1\n"
             "GDRIVE_BACKUP_NOTIFY_SUCCESSES=1\n"
             "GDRIVE_BACKUP_PAUSED=0\n";
        NSString *disabledSuccessConfig =
            @"GDRIVE_BACKUP_PROFILE_ID=office\n"
             "GDRIVE_BACKUP_SCHEDULE=daily\n"
             "GDRIVE_BACKUP_NOTIFY_FAILURES=1\n"
             "GDRIVE_BACKUP_NOTIFY_SUCCESSES=0\n"
             "GDRIVE_BACKUP_PAUSED=0\n";
        NSString *currentSuccessSummary = [NSString stringWithFormat:
            @"protocol=1\nstatus=success\npid=321\nstarted_at=%.0f\n"
             "finished_at=%.0f\nlast_success_at=%.0f\nexit_code=0\ntrigger=schedule\n",
            sourceStartedAt, sourceFinishedAt, sourceFinishedAt];
        NSString *newerFailureSummary = [NSString stringWithFormat:
            @"protocol=1\nstatus=failure\npid=322\nstarted_at=%.0f\n"
             "finished_at=%.0f\nexit_code=1\ntrigger=schedule\nreason=test_failure\n",
            sourceNow - 30, sourceNow - 20];
        [enabledSuccessConfig writeToFile:sourceConfigPath atomically:YES
                                  encoding:NSUTF8StringEncoding error:nil];
        [currentSuccessSummary writeToFile:sourceSummaryPath atomically:YES
                                   encoding:NSUTF8StringEncoding error:nil];
        setenv("GDRIVE_BACKUP_CONFIG", sourceConfigPath.UTF8String, 1);
        setenv("GDRIVE_BACKUP_SUMMARY_STATE_FILE", sourceSummaryPath.UTF8String, 1);

        NSDictionary<NSString *, NSString *> *sourceRoutineSuccess = @{
            @"identifier": [NSString stringWithFormat:
                @"com.commcats.gdrivebackup.office.success.%.0f", sourceFinishedAt],
            @"profileID": @"office",
            @"kind": @"success",
            @"eventTimestamp": [NSString stringWithFormat:@"%.0f", sourceFinishedAt],
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationSuccessBody"
        };
        BackupSuccessPreAddRaceTestDelegate *sourceCurrent =
            [[BackupSuccessPreAddRaceTestDelegate alloc] init];
        sourceCurrent.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".success-source-current"]];
        sourceCurrent.useRealSuccessSourceValidation = YES;
        [sourceCurrent.testDefaults setDouble:sourceNow - 180 forKey:
            @"GDTBackupNotification.office.successMonitorStartedAt"];
        BOOL sourceInitiallyCurrent = [sourceCurrent
            isBackupSuccessDecisionCurrent:sourceRoutineSuccess
            capturedActiveIssueTimestamp:0];
        [disabledSuccessConfig writeToFile:sourceConfigPath atomically:YES
                                   encoding:NSUTF8StringEncoding error:nil];
        BOOL sourceCurrentAfterOptOut = [sourceCurrent
            isBackupSuccessDecisionCurrent:sourceRoutineSuccess
            capturedActiveIssueTimestamp:0];
        [enabledSuccessConfig writeToFile:sourceConfigPath atomically:YES
                                  encoding:NSUTF8StringEncoding error:nil];
        [sourceCurrent.testDefaults setDouble:sourceNow - 180 forKey:
            @"GDTBackupNotification.office.successMonitorStartedAt"];
        [newerFailureSummary writeToFile:sourceSummaryPath atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil];
        BOOL sourceCurrentAfterNewerFailure = [sourceCurrent
            isBackupSuccessDecisionCurrent:sourceRoutineSuccess
            capturedActiveIssueTimestamp:0];
        Assert(sourceInitiallyCurrent && !sourceCurrentAfterOptOut &&
               !sourceCurrentAfterNewerFailure,
               @"success delivery revalidates current preferences and durable run state");

        [enabledSuccessConfig writeToFile:sourceConfigPath atomically:YES
                                  encoding:NSUTF8StringEncoding error:nil];
        [currentSuccessSummary writeToFile:sourceSummaryPath atomically:YES
                                   encoding:NSUTF8StringEncoding error:nil];
        NotificationTestDelegate *sourceChangedAfterAcceptance =
            [[NotificationTestDelegate alloc] init];
        sourceChangedAfterAcceptance.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName stringByAppendingString:
                @".success-source-post-acceptance"]];
        sourceChangedAfterAcceptance.useRealSuccessSourceValidation = YES;
        sourceChangedAfterAcceptance.deliverySucceeds = YES;
        sourceChangedAfterAcceptance.deferBackupDelivery = YES;
        [sourceChangedAfterAcceptance.testDefaults setDouble:sourceNow - 180 forKey:
            @"GDTBackupNotification.office.successMonitorStartedAt"];
        BOOL sourcePostAcceptanceProcessorAvailable = NO;
        ProcessSuccessWithCapturedIssue(sourceChangedAfterAcceptance,
            sourceRoutineSuccess, 0, &sourcePostAcceptanceProcessorAvailable);
        void (^finishSourceChangedDelivery)(BOOL) =
            sourceChangedAfterAcceptance.deferredBackupDeliveryCompletions.firstObject;
        [newerFailureSummary writeToFile:sourceSummaryPath atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil];
        if (finishSourceChangedDelivery) finishSourceChangedDelivery(YES);
        Assert(sourcePostAcceptanceProcessorAvailable && finishSourceChangedDelivery &&
               [sourceChangedAfterAcceptance.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 0 &&
               [sourceChangedAfterAcceptance.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[sourceRoutineSuccess[@"identifier"]]] &&
               [sourceChangedAfterAcceptance.removedPendingNotificationIdentifiers
                   isEqualToArray:@[sourceRoutineSuccess[@"identifier"]]],
               @"a durable state change after acceptance retracts success without a watermark");
        unsetenv("GDRIVE_BACKUP_CONFIG");
        unsetenv("GDRIVE_BACKUP_SUMMARY_STATE_FILE");
        [NSFileManager.defaultManager trashItemAtURL:
            [NSURL fileURLWithPath:sourceConfigPath] resultingItemURL:nil error:nil];
        [NSFileManager.defaultManager trashItemAtURL:
            [NSURL fileURLWithPath:sourceSummaryPath] resultingItemURL:nil error:nil];

        NotificationTestDelegate *newIssueDuringSuccessReconciliation =
            [[NotificationTestDelegate alloc] init];
        newIssueDuringSuccessReconciliation.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName stringByAppendingString:
                @".new-issue-during-success-reconciliation"]];
        newIssueDuringSuccessReconciliation.deliverySucceeds = YES;
        newIssueDuringSuccessReconciliation.deferPendingSuccessEnumeration = YES;
        [newIssueDuringSuccessReconciliation.testDefaults setDouble:100 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        BOOL capturedSuccessProcessorAvailable = NO;
        ProcessSuccessWithCapturedIssue(newIssueDuringSuccessReconciliation,
            firstSuccess, 100, &capturedSuccessProcessorAvailable);
        void (^resumeSuccessReconciliation)(NSArray<UNNotificationRequest *> *) =
            newIssueDuringSuccessReconciliation.deferredPendingSuccessEnumeration;
        newIssueDuringSuccessReconciliation.deferPendingSuccessEnumeration = NO;
        [newIssueDuringSuccessReconciliation.testDefaults setDouble:300 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        if (resumeSuccessReconciliation) resumeSuccessReconciliation(@[]);
        Assert(capturedSuccessProcessorAvailable && resumeSuccessReconciliation &&
               newIssueDuringSuccessReconciliation.deliveryCalls == 0,
               @"a new issue during success reconciliation suppresses delivery before acceptance");

        BOOL backupNotificationCenterSeamAvailable = [AppDelegate
            instancesRespondToSelector:@selector(backupNotificationCenter)];
        __block BOOL settingsRaceCompleted = NO;
        __block BOOL settingsRaceDelivered = YES;
        __block BOOL settingsRaceCompletionRanOnMainThread = NO;
        __block BOOL undeterminedSuccessCompleted = NO;
        __block BOOL undeterminedSuccessDelivered = YES;
        __block BOOL undeterminedSuccessCompletionRanOnMainThread = NO;
        __block BOOL currentSuccessCompleted = NO;
        __block BOOL currentSuccessDelivered = NO;
        if (backupNotificationCenterSeamAvailable) {
            BackupSuccessPreAddRaceTestDelegate *settingsRace =
                [[BackupSuccessPreAddRaceTestDelegate alloc] init];
            settingsRace.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
                [suiteName stringByAppendingString:@".success-pre-add-settings"]];
            BackupSuccessPreAddRaceCenter *settingsCenter =
                [[BackupSuccessPreAddRaceCenter alloc] init];
            settingsCenter.settings = [[BackupSuccessPreAddRaceSettings alloc] init];
            settingsCenter.settings.authorizationStatus = UNAuthorizationStatusAuthorized;
            settingsCenter.deferSettings = YES;
            settingsRace.testNotificationCenter = settingsCenter;
            [settingsRace.testDefaults setDouble:100 forKey:
                @"GDTBackupNotification.office.activeIssueAt"];
            [settingsRace deliverBackupSuccessNotificationDecision:firstSuccess
                                       capturedActiveIssueTimestamp:100
                                                            completion:^(BOOL delivered) {
                settingsRaceCompleted = YES;
                settingsRaceDelivered = delivered;
                settingsRaceCompletionRanOnMainThread = NSThread.isMainThread;
            }];
            void (^finishSettings)(UNNotificationSettings *) =
                settingsCenter.deferredSettingsCompletion;
            [settingsRace.testDefaults setDouble:300 forKey:
                @"GDTBackupNotification.office.activeIssueAt"];
            if (finishSettings) {
                finishSettings((UNNotificationSettings *)(id)settingsCenter.settings);
            }

            BackupSuccessPreAddRaceTestDelegate *undeterminedSuccess =
                [[BackupSuccessPreAddRaceTestDelegate alloc] init];
            undeterminedSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
                [suiteName stringByAppendingString:@".success-undetermined-consent"]];
            BackupSuccessPreAddRaceCenter *undeterminedSuccessCenter =
                [[BackupSuccessPreAddRaceCenter alloc] init];
            undeterminedSuccessCenter.settings = [[BackupSuccessPreAddRaceSettings alloc] init];
            undeterminedSuccessCenter.settings.authorizationStatus = UNAuthorizationStatusNotDetermined;
            undeterminedSuccess.testNotificationCenter = undeterminedSuccessCenter;
            [undeterminedSuccess.testDefaults setDouble:100 forKey:
                @"GDTBackupNotification.office.activeIssueAt"];
            [undeterminedSuccess deliverBackupSuccessNotificationDecision:firstSuccess
                                               capturedActiveIssueTimestamp:100
                                                                    completion:^(BOOL delivered) {
                undeterminedSuccessCompleted = YES;
                undeterminedSuccessDelivered = delivered;
                undeterminedSuccessCompletionRanOnMainThread = NSThread.isMainThread;
            }];

            BackupSuccessPreAddRaceTestDelegate *currentSuccess =
                [[BackupSuccessPreAddRaceTestDelegate alloc] init];
            currentSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
                [suiteName stringByAppendingString:@".success-pre-add-current"]];
            BackupSuccessPreAddRaceCenter *currentCenter =
                [[BackupSuccessPreAddRaceCenter alloc] init];
            currentCenter.settings = [[BackupSuccessPreAddRaceSettings alloc] init];
            currentCenter.settings.authorizationStatus = UNAuthorizationStatusAuthorized;
            currentCenter.deferSettings = YES;
            currentSuccess.testNotificationCenter = currentCenter;
            [currentSuccess.testDefaults setDouble:100 forKey:
                @"GDTBackupNotification.office.activeIssueAt"];
            [currentSuccess deliverBackupSuccessNotificationDecision:firstSuccess
                                             capturedActiveIssueTimestamp:100
                                                                  completion:^(BOOL delivered) {
                currentSuccessCompleted = YES;
                currentSuccessDelivered = delivered;
            }];
            void (^finishCurrentSettings)(UNNotificationSettings *) =
                currentCenter.deferredSettingsCompletion;
            if (finishCurrentSettings) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                    finishCurrentSettings((UNNotificationSettings *)(id)currentCenter.settings);
                });
            }
            BOOL currentSuccessFinished = WaitForCondition(^BOOL {
                return currentSuccessCompleted;
            }, 1.0);
            Assert(settingsCenter.deferredSettingsCompletion && settingsRaceCompleted &&
                   !settingsRaceDelivered && settingsRaceCompletionRanOnMainThread &&
                   settingsCenter.addRequestCalls == 0,
                   @"a newer issue during delayed settings prevents success delivery before add");
            Assert(undeterminedSuccessCompleted && !undeterminedSuccessDelivered &&
                   undeterminedSuccessCompletionRanOnMainThread &&
                   undeterminedSuccessCenter.authorizationRequests == 0 &&
                   undeterminedSuccessCenter.addRequestCalls == 0,
                   @"success delivery fails closed until explicit notification consent");
            Assert(finishCurrentSettings && currentSuccessFinished &&
                   currentSuccessDelivered &&
                   currentCenter.addRequestCalls == 1 &&
                   currentCenter.addRequestRanOnMainThread,
                   @"a current success adds its notification on the main queue");
        }
        Assert(backupNotificationCenterSeamAvailable,
               @"success delivery exposes a deterministic notification-center seam");

        NotificationTestDelegate *newIssueDuringSuccessDelivery =
            [[NotificationTestDelegate alloc] init];
        newIssueDuringSuccessDelivery.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName stringByAppendingString:
                @".new-issue-during-success-delivery"]];
        newIssueDuringSuccessDelivery.deliverySucceeds = YES;
        newIssueDuringSuccessDelivery.deferBackupDelivery = YES;
        [newIssueDuringSuccessDelivery.testDefaults setDouble:100 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        BOOL delayedSuccessProcessorAvailable = NO;
        ProcessSuccessWithCapturedIssue(newIssueDuringSuccessDelivery,
            firstSuccess, 100, &delayedSuccessProcessorAvailable);
        void (^finishDelayedSuccessDelivery)(BOOL) =
            newIssueDuringSuccessDelivery.deferredBackupDeliveryCompletions.firstObject;
        [newIssueDuringSuccessDelivery.testDefaults setDouble:300 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        if (finishDelayedSuccessDelivery) finishDelayedSuccessDelivery(YES);
        Assert(delayedSuccessProcessorAvailable && finishDelayedSuccessDelivery &&
               newIssueDuringSuccessDelivery.deliveryCalls == 1 &&
               [newIssueDuringSuccessDelivery.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 0 &&
               [newIssueDuringSuccessDelivery.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[firstSuccess[@"identifier"]]] &&
               [newIssueDuringSuccessDelivery.removedPendingNotificationIdentifiers
                   isEqualToArray:@[firstSuccess[@"identifier"]]],
               @"a newer issue after delayed success acceptance removes the stale notice without a watermark");

        NotificationTestDelegate *newerDismissedIssue = [[NotificationTestDelegate alloc] init];
        newerDismissedIssue.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".newer-dismissed-issue"]];
        newerDismissedIssue.deliverySucceeds = YES;
        [newerDismissedIssue.testDefaults setDouble:300 forKey:
            @"GDTBackupNotification.office.dismissedIssueAt"];
        BOOL dismissedRoutineCurrent = SuccessDecisionIsCurrent(
            newerDismissedIssue, routineSuccess, 0, &currentGateAvailable);
        if (dismissedRoutineCurrent) ProcessSuccess(newerDismissedIssue, routineSuccess);
        Assert(currentGateAvailable && !dismissedRoutineCurrent &&
               newerDismissedIssue.deliveryCalls == 0,
               @"a routine success cannot overtake a newer acknowledged issue");

        NotificationTestDelegate *refusedSuccess = [[NotificationTestDelegate alloc] init];
        refusedSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".refused-success"]];
        refusedSuccess.deliverySucceeds = NO;
        ProcessSuccess(refusedSuccess, firstSuccess);
        ProcessSuccess(refusedSuccess, firstSuccess);
        Assert(refusedSuccess.deliveryCalls == 2 &&
               [refusedSuccess.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 0,
               @"a refused success remains eligible for the next refresh");

        NotificationTestDelegate *untrustedPreviousRequest =
            [[NotificationTestDelegate alloc] init];
        untrustedPreviousRequest.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".untrusted-previous-request"]];
        untrustedPreviousRequest.deliverySucceeds = YES;
        NSString *previousSuccess = @"com.commcats.gdrivebackup.office.success.100";
        [untrustedPreviousRequest.testDefaults setObject:@{
            @"timestamp": @100, @"identifier": previousSuccess
        } forKey:@"GDTBackupNotification.office.latestDeliveredSuccessState"];
        untrustedPreviousRequest.extraDeliveredBackupNotifications = @[
            DeliveredBackupNotification(previousSuccess, @"GDT_BACKUP_ALERT", @{
                @"profileID": @"office", @"eventTimestamp": @"100"
            })
        ];
        ProcessSuccess(untrustedPreviousRequest, firstSuccess);
        Assert(untrustedPreviousRequest.deliveryCalls == 1 &&
               untrustedPreviousRequest.removedNotificationIdentifiers == nil,
               @"a canonical previous ID without success metadata is never retired directly");

        for (NSString *unsafePreviousIdentifier in @[
            @"com.commcats.gdrivebackup.archive.success.100",
            @"com.commcats.gdrivebackup.office.failure.100",
            @"com.commcats.gdrivebackup.office.success.0100"
        ]) {
            NotificationTestDelegate *unsafePrevious = [[NotificationTestDelegate alloc] init];
            unsafePrevious.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
                [suiteName stringByAppendingString:
                    [NSString stringWithFormat:@".unsafe-success-%lu",
                        (unsigned long)[unsafePreviousIdentifier hash]]]];
            unsafePrevious.deliverySucceeds = YES;
            [unsafePrevious.testDefaults setDouble:100 forKey:
                @"GDTBackupNotification.office.lastDeliveredSuccessAt"];
            [unsafePrevious.testDefaults setObject:unsafePreviousIdentifier forKey:
                @"GDTBackupNotification.office.lastDeliveredSuccessIdentifier"];
            ProcessSuccess(unsafePrevious, firstSuccess);
            Assert(unsafePrevious.deliveryCalls == 1 &&
                   unsafePrevious.removedNotificationIdentifiers == nil,
                   @"a corrupt previous success identifier is never retired");
        }

        NotificationTestDelegate *restartAfterAcceptedSuccess =
            [[NotificationTestDelegate alloc] init];
        restartAfterAcceptedSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".restart-after-accepted-success"]];
        restartAfterAcceptedSuccess.deliverySucceeds = YES;
        restartAfterAcceptedSuccess.extraDeliveredBackupNotifications = @[
            DeliveredBackupNotification(firstSuccess[@"identifier"], @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"200"
            })
        ];
        ProcessSuccess(restartAfterAcceptedSuccess, firstSuccess);
        NSDictionary *reconciledAcceptedState = [restartAfterAcceptedSuccess.testDefaults
            dictionaryForKey:@"GDTBackupNotification.office.latestDeliveredSuccessState"];
        Assert(restartAfterAcceptedSuccess.deliveryCalls == 0 &&
               [reconciledAcceptedState[@"timestamp"] doubleValue] == 200 &&
               [reconciledAcceptedState[@"identifier"]
                   isEqualToString:firstSuccess[@"identifier"]],
               @"a restart reconciles accepted delivery before it can redeliver the same success");

        NotificationTestDelegate *restartWithPendingSuccess =
            [[NotificationTestDelegate alloc] init];
        restartWithPendingSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".restart-with-pending-success"]];
        restartWithPendingSuccess.deliverySucceeds = YES;
        restartWithPendingSuccess.extraPendingBackupNotificationRequests = @[
            PendingBackupNotificationRequest(firstSuccess[@"identifier"], @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"200"
            })
        ];
        ProcessSuccess(restartWithPendingSuccess, firstSuccess);
        NSDictionary *reconciledPendingState = [restartWithPendingSuccess.testDefaults
            dictionaryForKey:@"GDTBackupNotification.office.latestDeliveredSuccessState"];
        Assert(restartWithPendingSuccess.deliveryCalls == 0 &&
               [reconciledPendingState[@"identifier"]
                   isEqualToString:firstSuccess[@"identifier"]],
               @"a pending accepted success is reconciled before a restart can redeliver it");

        NotificationTestDelegate *pendingToDeliveredTransition =
            [[NotificationTestDelegate alloc] init];
        pendingToDeliveredTransition.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".pending-to-delivered-transition"]];
        pendingToDeliveredTransition.deliverySucceeds = YES;
        pendingToDeliveredTransition.pendingToDeliveredTransitionRequests = @[
            PendingBackupNotificationRequest(firstSuccess[@"identifier"], @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"200"
            })
        ];
        ProcessSuccess(pendingToDeliveredTransition, firstSuccess);
        Assert(pendingToDeliveredTransition.deliveryCalls == 0,
               @"a pending-to-delivered transition cannot lose an accepted success request");

        NotificationTestDelegate *untrustedDeliveredSuccess =
            [[NotificationTestDelegate alloc] init];
        untrustedDeliveredSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".untrusted-delivered-success"]];
        untrustedDeliveredSuccess.deliverySucceeds = YES;
        untrustedDeliveredSuccess.extraDeliveredBackupNotifications = @[
            DeliveredBackupNotification(@"com.commcats.gdrivebackup.office.success.300",
                @"GDT_BACKUP_ALERT", @{
                    @"profileID": @"office", @"eventTimestamp": @"300"
                })
        ];
        ProcessSuccess(untrustedDeliveredSuccess, firstSuccess);
        Assert(untrustedDeliveredSuccess.deliveryCalls == 1 &&
               untrustedDeliveredSuccess.removedNotificationIdentifiers == nil,
               @"a mismatched delivered category cannot suppress or retire a success notice");

        NotificationTestDelegate *restartRetirementRepair = [[NotificationTestDelegate alloc] init];
        restartRetirementRepair.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".restart-retirement-repair"]];
        restartRetirementRepair.deliverySucceeds = YES;
        NSString *retainedSuccess = @"com.commcats.gdrivebackup.office.success.300";
        NSString *orphanedSuccess = @"com.commcats.gdrivebackup.office.success.100";
        restartRetirementRepair.extraDeliveredBackupNotifications = @[
            DeliveredBackupNotification(orphanedSuccess, @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"100"
            }),
            DeliveredBackupNotification(retainedSuccess, @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"300"
            })
        ];
        restartRetirementRepair.extraPendingBackupNotificationRequests = @[
            PendingBackupNotificationRequest(orphanedSuccess, @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"100"
            })
        ];
        [restartRetirementRepair.testDefaults setObject:@{
            @"timestamp": @300, @"identifier": retainedSuccess
        } forKey:@"GDTBackupNotification.office.latestDeliveredSuccessState"];
        NSDictionary<NSString *, NSString *> *retainedDecision = @{
            @"identifier": retainedSuccess,
            @"profileID": @"office",
            @"kind": @"success",
            @"eventTimestamp": @"300",
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationSuccessBody"
        };
        ProcessSuccess(restartRetirementRepair, retainedDecision);
        Assert(restartRetirementRepair.deliveryCalls == 0 &&
               [restartRetirementRepair.removedNotificationIdentifiers
                   isEqualToArray:@[orphanedSuccess]] &&
               [restartRetirementRepair.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[orphanedSuccess]] &&
               [restartRetirementRepair.removedPendingNotificationIdentifiers
                   isEqualToArray:@[orphanedSuccess]],
               @"a restart reconciles delivered and pending retirement to one canonical success notice");

        BackupActionTestDelegate *automaticSuccess = [[BackupActionTestDelegate alloc] init];
        automaticSuccess.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".automatic-success-no-ui"]];
        automaticSuccess.deliverySucceeds = YES;
        ProcessSuccess(automaticSuccess, firstSuccess);
        Assert(automaticSuccess.deliveryCalls == 1 &&
               automaticSuccess.overviewShowCalls == 0 &&
               automaticSuccess.overviewRefreshCalls == 0 &&
               automaticSuccess.backupLaunchCalls == 0,
               @"automatic success delivery never opens or activates the overview");

        NSMutableDictionary<NSString *, NSString *> *newerSuccess = [firstSuccess mutableCopy];
        newerSuccess[@"identifier"] = @"com.commcats.gdrivebackup.office.success.300";
        newerSuccess[@"eventTimestamp"] = @"300";
        deferredSuccess.extraDeliveredBackupNotifications = @[
            DeliveredBackupNotification(firstSuccess[@"identifier"], @"GDT_BACKUP_SUCCESS", @{
                @"profileID": @"office", @"eventTimestamp": @"200"
            })
        ];
        ProcessSuccess(deferredSuccess, newerSuccess);
        Assert(deferredSuccess.deliveryCalls == 2 &&
               [deferredSuccess.removedNotificationIdentifiers
                   isEqualToArray:@[firstSuccess[@"identifier"]]] &&
               [deferredSuccess.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 300,
               @"an accepted newer success retires exactly the prior success notification");

        NotificationTestDelegate *cleanupAfterRefusal = [[NotificationTestDelegate alloc] init];
        cleanupAfterRefusal.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".success-cleanup-refusal"]];
        cleanupAfterRefusal.deliverySucceeds = NO;
        NSString *oldFailureForRefusal = @"com.commcats.gdrivebackup.office.failure.100";
        [cleanupAfterRefusal.testDefaults setObject:@[oldFailureForRefusal] forKey:
            @"GDTBackupNotification.office.deliveredFailureIdentifiers"];
        [cleanupAfterRefusal.testDefaults setDouble:100 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        [cleanupAfterRefusal clearBackupFailureNotificationsForConfig:
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"}
            summary:@{@"status": @"success", @"finished_at": @"200", @"trigger": @"schedule"}
            status:@"success"];
        ProcessSuccess(cleanupAfterRefusal, firstSuccess);
        Assert([cleanupAfterRefusal.removedNotificationIdentifiers
                   isEqualToArray:@[oldFailureForRefusal]] &&
               cleanupAfterRefusal.deliveryCalls == 1,
               @"automatic failure cleanup completes even when success delivery is refused");

        NotificationTestDelegate *cleanupAfterAcceptance = [[NotificationTestDelegate alloc] init];
        cleanupAfterAcceptance.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".success-cleanup-acceptance"]];
        cleanupAfterAcceptance.deliverySucceeds = YES;
        NSString *oldFailureForAcceptance = @"com.commcats.gdrivebackup.office.failure.100";
        [cleanupAfterAcceptance.testDefaults setObject:@[oldFailureForAcceptance] forKey:
            @"GDTBackupNotification.office.deliveredFailureIdentifiers"];
        [cleanupAfterAcceptance.testDefaults setDouble:100 forKey:
            @"GDTBackupNotification.office.activeIssueAt"];
        [cleanupAfterAcceptance clearBackupFailureNotificationsForConfig:
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"}
            summary:@{@"status": @"success", @"finished_at": @"200", @"trigger": @"schedule"}
            status:@"success"];
        ProcessSuccess(cleanupAfterAcceptance, firstSuccess);
        Assert([cleanupAfterAcceptance.removedNotificationIdentifiers
                   isEqualToArray:@[oldFailureForAcceptance]] &&
               cleanupAfterAcceptance.deliveryCalls == 1 &&
               [cleanupAfterAcceptance.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.lastDeliveredSuccessAt"] == 200,
               @"automatic failure cleanup also completes when success delivery is accepted");

        NSDictionary<NSString *, NSString *> *first = @{
            @"identifier": @"com.commcats.gdrivebackup.office.failure.100",
            @"profileID": @"office",
            @"kind": @"failure",
            @"issueTimestamp": @"100",
            @"issueOriginTimestamp": @"100",
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
        nextRun[@"issueOriginTimestamp"] = @"200";
        Process(delegate, nextRun);
        Assert(delegate.deliveryCalls == 2,
               @"a later failed run remains eligible for its own notification");

        NSMutableDictionary<NSString *, NSString *> *otherProfile = [first mutableCopy];
        otherProfile[@"profileID"] = @"archive";
        otherProfile[@"identifier"] = @"com.commcats.gdrivebackup.archive.failure.100";
        Process(delegate, otherProfile);
        Assert(delegate.deliveryCalls == 3,
               @"notification deduplication is isolated per backup profile");

        delegate.deliverySucceeds = NO;
        NSMutableDictionary<NSString *, NSString *> *notDelivered = [first mutableCopy];
        notDelivered[@"identifier"] = @"com.commcats.gdrivebackup.office.failure.300";
        notDelivered[@"issueTimestamp"] = @"300";
        notDelivered[@"issueOriginTimestamp"] = @"300";
        Process(delegate, notDelivered);
        Process(delegate, notDelivered);
        Assert(delegate.deliveryCalls == 5,
               @"a notification is marked handled only after macOS accepts it");

        Process(delegate, @{});
        Assert(delegate.deliveryCalls == 5,
               @"incomplete policy output cannot create a notification");

        BackupRemovalSeamTestDelegate *removalProbe =
            [[BackupRemovalSeamTestDelegate alloc] init];
        BOOL exactRemovalSeamsAvailable =
            [AppDelegate instancesRespondToSelector:
                @selector(removeDeliveredBackupNotificationIdentifiers:)] &&
            [AppDelegate instancesRespondToSelector:
                @selector(removePendingBackupNotificationIdentifiers:)];
        if (exactRemovalSeamsAvailable) {
            [removalProbe removeExactBackupNotificationIdentifiers:@[
                @"com.commcats.gdrivebackup.office.failure.100",
                @"com.commcats.gdrivebackup.archive.failure.100",
                @"not-a-backup-notification"
            ] forProfileID:@"office"];
        }
        NSArray<NSString *> *oneSafeRemoval =
            @[@"com.commcats.gdrivebackup.office.failure.100"];
        Assert(exactRemovalSeamsAvailable &&
               [removalProbe.removedDeliveredNotificationIdentifiers
                   isEqualToArray:oneSafeRemoval] &&
               [removalProbe.removedPendingNotificationIdentifiers
                   isEqualToArray:oneSafeRemoval],
               @"exact retirement filters identifiers and removes both delivered and pending requests");

        NotificationTestDelegate *replacement =
            [[NotificationTestDelegate alloc] init];
        replacement.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".replacement"]];
        replacement.deliverySucceeds = YES;
        NSDictionary<NSString *, NSString *> *preliminary = @{
            @"identifier": @"com.commcats.gdrivebackup.office.failure.400",
            @"profileID": @"office",
            @"kind": @"failure",
            @"issueTimestamp": @"405",
            @"issueOriginTimestamp": @"400",
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": @"backupNotificationNASRetryBody"
        };
        NSMutableDictionary *retryRunningDecision = [preliminary mutableCopy];
        retryRunningDecision[@"kind"] = @"retry-running";
        retryRunningDecision[@"revision"] = @"retry-running.430";
        retryRunningDecision[@"issueTimestamp"] = @"400";
        retryRunningDecision[@"titleKey"] = @"backupNotificationRetryRunningTitle";
        retryRunningDecision[@"bodyKey"] = @"backupNotificationRetryRunningBody";
        NSDictionary<NSString *, NSString *> *finalRetryFailure = @{
            @"identifier": @"com.commcats.gdrivebackup.office.failure.430",
            @"supersedesIdentifier":
                @"com.commcats.gdrivebackup.office.failure.400",
            @"profileID": @"office",
            @"kind": @"failure",
            @"issueTimestamp": @"435",
            @"issueOriginTimestamp": @"400",
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": @"backupNotificationRetryFailureBody"
        };
        Process(replacement, preliminary);
        Process(replacement, retryRunningDecision);
        Process(replacement, retryRunningDecision);
        Assert(replacement.deliveryCalls == 2 &&
               replacement.removedNotificationIdentifiers == nil,
               @"retry start updates one identifier once without a duplicate alert");

        NotificationTestDelegate *restarted = [[NotificationTestDelegate alloc] init];
        restarted.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName stringByAppendingString:@".replacement"]];
        restarted.deliverySucceeds = YES;
        Process(restarted, retryRunningDecision);
        Assert(restarted.deliveryCalls == 0,
               @"a controller restart does not repeat the running revision");

        NotificationTestDelegate *inFlightReplacement =
            [[NotificationTestDelegate alloc] init];
        inFlightReplacement.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".in-flight-replacement"]];
        inFlightReplacement.deliverySucceeds = YES;
        inFlightReplacement.deferBackupDelivery = YES;
        Process(inFlightReplacement, preliminary);
        Process(inFlightReplacement, retryRunningDecision);
        Process(inFlightReplacement, retryRunningDecision);
        Assert(inFlightReplacement.deliveryCalls == 1 &&
               inFlightReplacement.deferredBackupDeliveryCompletions.count == 1,
               @"a running revision waits behind one in-flight preliminary request without duplicating itself");
        void (^finishPreliminary)(BOOL) =
            inFlightReplacement.deferredBackupDeliveryCompletions[0];
        finishPreliminary(YES);
        Assert(inFlightReplacement.deliveryCalls == 2 &&
               inFlightReplacement.deferredBackupDeliveryCompletions.count == 2,
               @"accepting the preliminary request immediately submits its queued running replacement");
        Process(inFlightReplacement, retryRunningDecision);
        Assert(inFlightReplacement.deliveryCalls == 2,
               @"the same running revision is suppressed while its delivery is in flight");
        void (^finishRunning)(BOOL) =
            inFlightReplacement.deferredBackupDeliveryCompletions[1];
        finishRunning(YES);
        inFlightReplacement.deferBackupDelivery = NO;
        Process(inFlightReplacement, retryRunningDecision);
        NSDictionary *visibleReplacement =
            inFlightReplacement.acceptedBackupDecisionsByIdentifier[
                preliminary[@"identifier"]];
        Assert(inFlightReplacement.deliveryCalls == 2 &&
               [visibleReplacement[@"kind"] isEqualToString:@"retry-running"] &&
               [[inFlightReplacement.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.430"],
               @"serialized acceptance leaves the running revision visible and durable");

        NotificationTestDelegate *latchedRunningDelivery =
            [[NotificationTestDelegate alloc] init];
        latchedRunningDelivery.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".latched-running-delivery"]];
        latchedRunningDelivery.deliverySucceeds = YES;
        [latchedRunningDelivery.testDefaults setDouble:400
            forKey:@"GDTBackupNotification.office.activeIssueAt"];
        [latchedRunningDelivery.testDefaults setObject:@"failure"
            forKey:@"GDTBackupNotification.office.activeIssueKind"];
        [latchedRunningDelivery.testDefaults setObject:preliminary[@"identifier"]
            forKey:@"GDTBackupNotification.office.activeIssueIdentifier"];
        Process(latchedRunningDelivery, retryRunningDecision);
        Assert(latchedRunningDelivery.deliveryCalls == 1 &&
               [latchedRunningDelivery.testDefaults doubleForKey:
                   @"GDTBackupNotification.office.activeIssueAt"] == 400 &&
               [[latchedRunningDelivery.testDefaults stringForKey:
                   @"GDTBackupNotification.office.activeIssueKind"]
                       isEqualToString:@"failure"] &&
               [[latchedRunningDelivery.testDefaults stringForKey:
                   @"GDTBackupNotification.office.activeIssueIdentifier"]
                       isEqualToString:preliminary[@"identifier"]],
               @"delivering retry progress never changes the canonical failure latch");

        NotificationTestDelegate *successDuringDelivery =
            [[NotificationTestDelegate alloc] init];
        successDuringDelivery.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".success-during-delivery"]];
        successDuringDelivery.deliverySucceeds = YES;
        successDuringDelivery.deferBackupDelivery = YES;
        Process(successDuringDelivery, preliminary);
        Process(successDuringDelivery, retryRunningDecision);
        Assert(successDuringDelivery.deferredBackupDeliveryCompletions.count == 1,
               @"the success race captures one in-flight callback with running work queued");
        [successDuringDelivery clearBackupFailureNotificationsForConfig:
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"}
            summary:@{@"status": @"success", @"finished_at": @"500",
                      @"trigger": @"schedule-retry"}
            status:@"success"];
        void (^finishAfterSuccess)(BOOL) =
            successDuringDelivery.deferredBackupDeliveryCompletions[0];
        finishAfterSuccess(YES);
        Assert(successDuringDelivery.deliveryCalls == 1 &&
               successDuringDelivery.deferredBackupDeliveryCompletions.count == 1 &&
               successDuringDelivery.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [successDuringDelivery.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"] == nil &&
               [successDuringDelivery.testDefaults objectForKey:
                   @"GDTBackupNotification.office.deliveredFailureIdentifiers"] == nil &&
               [successDuringDelivery.testDefaults objectForKey:
                   @"GDTBackupNotification.office.latestDeliveredIssueAt"] == nil &&
               [successDuringDelivery.testDefaults objectForKey:
                   @"GDTBackupNotification.office.latestDeliveredIssueStage"] == nil &&
               [successDuringDelivery.testDefaults objectForKey:
                   @"GDTBackupNotification.office.latestDeliveredIssueState"] == nil &&
               [successDuringDelivery.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[preliminary[@"identifier"]]] &&
               [successDuringDelivery.removedPendingNotificationIdentifiers
                   isEqualToArray:@[preliminary[@"identifier"]]],
               @"a success invalidates and retires an alert accepted by a late delivery callback");

        NotificationTestDelegate *terminalSupersessionOrdering =
            [[NotificationTestDelegate alloc] init];
        terminalSupersessionOrdering.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".terminal-supersession-ordering"]];
        terminalSupersessionOrdering.deliverySucceeds = YES;
        terminalSupersessionOrdering.deferBackupDelivery = YES;
        Process(terminalSupersessionOrdering, preliminary);
        Process(terminalSupersessionOrdering, retryRunningDecision);
        Process(terminalSupersessionOrdering, finalRetryFailure);
        Process(terminalSupersessionOrdering, retryRunningDecision);
        Assert(terminalSupersessionOrdering.deliveryCalls == 1 &&
               terminalSupersessionOrdering.deferredBackupDeliveryCompletions.count == 1,
               @"one in-flight request coalesces retry lifecycle updates for its profile");
        void (^finishBeforeTerminal)(BOOL) =
            terminalSupersessionOrdering.deferredBackupDeliveryCompletions[0];
        finishBeforeTerminal(YES);
        Assert(terminalSupersessionOrdering.deliveryCalls == 2 &&
               terminalSupersessionOrdering.deferredBackupDeliveryCompletions.count == 2,
               @"the terminal retry result is the only queued request submitted next");
        void (^finishTerminal)(BOOL) =
            terminalSupersessionOrdering.deferredBackupDeliveryCompletions[1];
        finishTerminal(YES);
        Assert(terminalSupersessionOrdering.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [terminalSupersessionOrdering.acceptedBackupDecisionsByIdentifier[
                   finalRetryFailure[@"identifier"]][@"bodyKey"]
                       isEqualToString:@"backupNotificationRetryFailureBody"] &&
               [[terminalSupersessionOrdering.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:finalRetryFailure[@"identifier"]],
               @"a stale running observation cannot displace a queued terminal retry result");

        NotificationTestDelegate *staleOriginOrdering =
            [[NotificationTestDelegate alloc] init];
        staleOriginOrdering.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".stale-origin-ordering"]];
        staleOriginOrdering.deliverySucceeds = YES;
        staleOriginOrdering.deferBackupDelivery = YES;
        NSMutableDictionary<NSString *, NSString *> *newerIndependentFailure =
            [preliminary mutableCopy];
        newerIndependentFailure[@"identifier"] =
            @"com.commcats.gdrivebackup.office.failure.500";
        newerIndependentFailure[@"issueTimestamp"] = @"505";
        newerIndependentFailure[@"issueOriginTimestamp"] = @"500";
        Process(staleOriginOrdering, newerIndependentFailure);
        Process(staleOriginOrdering, preliminary);
        Assert(staleOriginOrdering.deliveryCalls == 1 &&
               staleOriginOrdering.deferredBackupDeliveryCompletions.count == 1,
               @"an older origin waits on neither a second request nor a queued rollback");
        void (^finishNewerOrigin)(BOOL) =
            staleOriginOrdering.deferredBackupDeliveryCompletions[0];
        finishNewerOrigin(YES);
        Assert(staleOriginOrdering.deliveryCalls == 1 &&
               staleOriginOrdering.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [staleOriginOrdering.acceptedBackupDecisionsByIdentifier[
                   newerIndependentFailure[@"identifier"]][@"issueOriginTimestamp"]
                       isEqualToString:@"500"],
               @"a stale origin cannot queue behind and roll back a newer in-flight issue");

        NSString *acceptedOriginKey =
            @"GDTBackupNotification.office.latestDeliveredIssueAt";
        NSString *acceptedStageKey =
            @"GDTBackupNotification.office.latestDeliveredIssueStage";
        NSString *acceptedStateKey =
            @"GDTBackupNotification.office.latestDeliveredIssueState";

        NotificationTestDelegate *acceptedTerminalOrdering =
            [[NotificationTestDelegate alloc] init];
        acceptedTerminalOrdering.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".accepted-terminal-ordering"]];
        acceptedTerminalOrdering.deliverySucceeds = YES;
        Process(acceptedTerminalOrdering, preliminary);
        Process(acceptedTerminalOrdering, finalRetryFailure);
        Process(acceptedTerminalOrdering, retryRunningDecision);
        Assert(acceptedTerminalOrdering.deliveryCalls == 2 &&
               acceptedTerminalOrdering.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [acceptedTerminalOrdering.acceptedBackupDecisionsByIdentifier[
                   finalRetryFailure[@"identifier"]][@"bodyKey"]
                       isEqualToString:@"backupNotificationRetryFailureBody"] &&
               [acceptedTerminalOrdering.testDefaults doubleForKey:
                   acceptedOriginKey] == 400 &&
               [acceptedTerminalOrdering.testDefaults integerForKey:
                   acceptedStageKey] == 3 &&
               [[acceptedTerminalOrdering.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:finalRetryFailure[@"identifier"]],
               @"an accepted terminal retry failure cannot be replaced by a later stale running observation");

        NSString *terminalRestartSuite =
            [suiteName stringByAppendingString:@".accepted-terminal-restart"];
        NotificationTestDelegate *terminalRestartSource =
            [[NotificationTestDelegate alloc] init];
        terminalRestartSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:terminalRestartSuite];
        terminalRestartSource.deliverySucceeds = YES;
        Process(terminalRestartSource, preliminary);
        Process(terminalRestartSource, finalRetryFailure);
        NotificationTestDelegate *terminalAfterRestart =
            [[NotificationTestDelegate alloc] init];
        terminalAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:terminalRestartSuite];
        terminalAfterRestart.deliverySucceeds = YES;
        terminalAfterRestart.acceptedBackupDecisionsByIdentifier =
            terminalRestartSource.acceptedBackupDecisionsByIdentifier;
        Process(terminalAfterRestart, retryRunningDecision);
        Assert(terminalAfterRestart.deliveryCalls == 0 &&
               terminalAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [terminalAfterRestart.acceptedBackupDecisionsByIdentifier[
                   finalRetryFailure[@"identifier"]][@"bodyKey"]
                       isEqualToString:@"backupNotificationRetryFailureBody"] &&
               [terminalAfterRestart.testDefaults doubleForKey:
                   acceptedOriginKey] == 400 &&
               [terminalAfterRestart.testDefaults integerForKey:
                   acceptedStageKey] == 3 &&
               [[terminalAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:finalRetryFailure[@"identifier"]],
               @"a restart preserves terminal retry ordering against a stale running observation");

        NSString *missingTerminalStateSuite =
            [suiteName stringByAppendingString:@".missing-terminal-state"];
        NotificationTestDelegate *missingTerminalStateSource =
            [[NotificationTestDelegate alloc] init];
        missingTerminalStateSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:missingTerminalStateSuite];
        missingTerminalStateSource.deliverySucceeds = YES;
        Process(missingTerminalStateSource, preliminary);
        Process(missingTerminalStateSource, finalRetryFailure);
        [missingTerminalStateSource.testDefaults removeObjectForKey:
            acceptedStateKey];
        [missingTerminalStateSource.testDefaults removeObjectForKey:
            acceptedStageKey];
        NotificationTestDelegate *missingTerminalStateAfterRestart =
            [[NotificationTestDelegate alloc] init];
        missingTerminalStateAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:missingTerminalStateSuite];
        missingTerminalStateAfterRestart.deliverySucceeds = YES;
        missingTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier =
            missingTerminalStateSource.acceptedBackupDecisionsByIdentifier;
        Process(missingTerminalStateAfterRestart, retryRunningDecision);
        NSDictionary *migratedMissingTerminalState =
            [missingTerminalStateAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(missingTerminalStateAfterRestart.deliveryCalls == 0 &&
               missingTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [missingTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier[
                   finalRetryFailure[@"identifier"]][@"bodyKey"]
                       isEqualToString:@"backupNotificationRetryFailureBody"] &&
               [[missingTerminalStateAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:finalRetryFailure[@"identifier"]] &&
               [missingTerminalStateAfterRestart.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"] == nil &&
               [migratedMissingTerminalState[@"origin"] doubleValue] == 400 &&
               [migratedMissingTerminalState[@"stage"] integerValue] == 3,
               @"a restart infers an accepted terminal stage before any stale running replay");

        NSString *incompleteTerminalStateSuite =
            [suiteName stringByAppendingString:@".incomplete-terminal-state"];
        NotificationTestDelegate *incompleteTerminalStateSource =
            [[NotificationTestDelegate alloc] init];
        incompleteTerminalStateSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:incompleteTerminalStateSuite];
        incompleteTerminalStateSource.deliverySucceeds = YES;
        incompleteTerminalStateSource.acceptedBackupDecisionsByIdentifier =
            [@{finalRetryFailure[@"identifier"]: finalRetryFailure} mutableCopy];
        [incompleteTerminalStateSource.testDefaults setDouble:400
            forKey:acceptedOriginKey];
        [incompleteTerminalStateSource.testDefaults setObject:@{@"origin": @400}
            forKey:acceptedStateKey];
        [incompleteTerminalStateSource.testDefaults
            setObject:finalRetryFailure[@"identifier"]
               forKey:@"GDTBackupNotification.office.lastDeliveredIdentifier"];
        NotificationTestDelegate *incompleteTerminalStateAfterRestart =
            [[NotificationTestDelegate alloc] init];
        incompleteTerminalStateAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:incompleteTerminalStateSuite];
        incompleteTerminalStateAfterRestart.deliverySucceeds = YES;
        incompleteTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier =
            incompleteTerminalStateSource.acceptedBackupDecisionsByIdentifier;
        Process(incompleteTerminalStateAfterRestart, retryRunningDecision);
        NSDictionary *migratedIncompleteTerminalState =
            [incompleteTerminalStateAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(incompleteTerminalStateAfterRestart.deliveryCalls == 0 &&
               incompleteTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [incompleteTerminalStateAfterRestart.acceptedBackupDecisionsByIdentifier[
                   finalRetryFailure[@"identifier"]][@"bodyKey"]
                       isEqualToString:@"backupNotificationRetryFailureBody"] &&
               [[incompleteTerminalStateAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:finalRetryFailure[@"identifier"]] &&
               [incompleteTerminalStateAfterRestart.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"] == nil &&
               [migratedIncompleteTerminalState[@"origin"] doubleValue] == 400 &&
               [migratedIncompleteTerminalState[@"stage"] integerValue] == 3,
               @"an incomplete accepted terminal state fails closed before stale running delivery");

        NSString *legacyPreliminarySuite =
            [suiteName stringByAppendingString:@".legacy-preliminary-state"];
        NotificationTestDelegate *legacyPreliminarySource =
            [[NotificationTestDelegate alloc] init];
        legacyPreliminarySource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:legacyPreliminarySuite];
        legacyPreliminarySource.deliverySucceeds = YES;
        Process(legacyPreliminarySource, preliminary);
        [legacyPreliminarySource.testDefaults removeObjectForKey:acceptedStateKey];
        [legacyPreliminarySource.testDefaults removeObjectForKey:acceptedStageKey];
        NotificationTestDelegate *legacyPreliminaryAfterRestart =
            [[NotificationTestDelegate alloc] init];
        legacyPreliminaryAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:legacyPreliminarySuite];
        legacyPreliminaryAfterRestart.deliverySucceeds = YES;
        legacyPreliminaryAfterRestart.acceptedBackupDecisionsByIdentifier =
            legacyPreliminarySource.acceptedBackupDecisionsByIdentifier;
        Process(legacyPreliminaryAfterRestart, retryRunningDecision);
        NSDictionary *migratedLegacyPreliminaryState =
            [legacyPreliminaryAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(legacyPreliminaryAfterRestart.deliveryCalls == 1 &&
               [legacyPreliminaryAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"] &&
               [[legacyPreliminaryAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:preliminary[@"identifier"]] &&
               [[legacyPreliminaryAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.430"] &&
               [migratedLegacyPreliminaryState[@"origin"] doubleValue] == 400 &&
               [migratedLegacyPreliminaryState[@"stage"] integerValue] == 2,
               @"a legacy preliminary warning still accepts its running update during migration");

        NSString *tornLegacyOriginSuite =
            [suiteName stringByAppendingString:@".torn-legacy-origin-stage"];
        NotificationTestDelegate *tornLegacyOriginSource =
            [[NotificationTestDelegate alloc] init];
        tornLegacyOriginSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:tornLegacyOriginSuite];
        tornLegacyOriginSource.deliverySucceeds = YES;
        tornLegacyOriginSource.acceptedBackupDecisionsByIdentifier =
            [@{newerIndependentFailure[@"identifier"]: newerIndependentFailure}
                mutableCopy];
        [tornLegacyOriginSource.testDefaults setObject:@{@"origin": @500}
            forKey:acceptedStateKey];
        [tornLegacyOriginSource.testDefaults setDouble:400
            forKey:acceptedOriginKey];
        [tornLegacyOriginSource.testDefaults setInteger:3
            forKey:acceptedStageKey];
        [tornLegacyOriginSource.testDefaults
            setObject:newerIndependentFailure[@"identifier"]
               forKey:@"GDTBackupNotification.office.lastDeliveredIdentifier"];
        NSMutableDictionary<NSString *, NSString *> *newerLegacyRetryRunning =
            [newerIndependentFailure mutableCopy];
        newerLegacyRetryRunning[@"kind"] = @"retry-running";
        newerLegacyRetryRunning[@"revision"] = @"retry-running.510";
        newerLegacyRetryRunning[@"titleKey"] =
            @"backupNotificationRetryRunningTitle";
        newerLegacyRetryRunning[@"bodyKey"] =
            @"backupNotificationRetryRunningBody";
        NotificationTestDelegate *tornLegacyOriginAfterRestart =
            [[NotificationTestDelegate alloc] init];
        tornLegacyOriginAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:tornLegacyOriginSuite];
        tornLegacyOriginAfterRestart.deliverySucceeds = YES;
        tornLegacyOriginAfterRestart.acceptedBackupDecisionsByIdentifier =
            tornLegacyOriginSource.acceptedBackupDecisionsByIdentifier;
        Process(tornLegacyOriginAfterRestart, newerLegacyRetryRunning);
        NSDictionary *migratedTornLegacyOriginState =
            [tornLegacyOriginAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(tornLegacyOriginAfterRestart.deliveryCalls == 1 &&
               [tornLegacyOriginAfterRestart.acceptedBackupDecisionsByIdentifier[
                   newerIndependentFailure[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"] &&
               [[tornLegacyOriginAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:newerIndependentFailure[@"identifier"]] &&
               [[tornLegacyOriginAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.510"] &&
               [migratedTornLegacyOriginState[@"origin"] doubleValue] == 500 &&
               [migratedTornLegacyOriginState[@"stage"] integerValue] == 2,
               @"an incomplete newer origin discards an unpaired older terminal stage during migration");

        NSString *legacyRunningSuite =
            [suiteName stringByAppendingString:@".legacy-running-state"];
        NotificationTestDelegate *legacyRunningSource =
            [[NotificationTestDelegate alloc] init];
        legacyRunningSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:legacyRunningSuite];
        legacyRunningSource.deliverySucceeds = YES;
        Process(legacyRunningSource, preliminary);
        Process(legacyRunningSource, retryRunningDecision);
        [legacyRunningSource.testDefaults removeObjectForKey:acceptedStateKey];
        [legacyRunningSource.testDefaults removeObjectForKey:acceptedStageKey];
        NSMutableDictionary<NSString *, NSString *> *laterRetryRunning =
            [retryRunningDecision mutableCopy];
        laterRetryRunning[@"revision"] = @"retry-running.440";
        NotificationTestDelegate *legacyRunningAfterRestart =
            [[NotificationTestDelegate alloc] init];
        legacyRunningAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:legacyRunningSuite];
        legacyRunningAfterRestart.deliverySucceeds = YES;
        legacyRunningAfterRestart.acceptedBackupDecisionsByIdentifier =
            legacyRunningSource.acceptedBackupDecisionsByIdentifier;
        Process(legacyRunningAfterRestart, preliminary);
        NSDictionary *migratedLegacyRunningState =
            [legacyRunningAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(legacyRunningAfterRestart.deliveryCalls == 0 &&
               [legacyRunningAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"] &&
               [[legacyRunningAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.430"] &&
               [migratedLegacyRunningState[@"origin"] doubleValue] == 400 &&
               [migratedLegacyRunningState[@"stage"] integerValue] == 2,
               @"a legacy running warning migrates to stage two before rejecting preliminary rollback");
        Process(legacyRunningAfterRestart, laterRetryRunning);
        NSDictionary *advancedLegacyRunningState =
            [legacyRunningAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(legacyRunningAfterRestart.deliveryCalls == 1 &&
               [legacyRunningAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"] &&
               [[legacyRunningAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.440"] &&
               [advancedLegacyRunningState[@"origin"] doubleValue] == 400 &&
               [advancedLegacyRunningState[@"stage"] integerValue] == 2,
               @"a legacy running warning rejects preliminary rollback but accepts a later running revision");

        NSString *malformedLegacyRevisionSuite =
            [suiteName stringByAppendingString:@".malformed-legacy-revision"];
        NotificationTestDelegate *malformedLegacyRevisionSource =
            [[NotificationTestDelegate alloc] init];
        malformedLegacyRevisionSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:malformedLegacyRevisionSuite];
        malformedLegacyRevisionSource.deliverySucceeds = YES;
        malformedLegacyRevisionSource.acceptedBackupDecisionsByIdentifier =
            [@{preliminary[@"identifier"]: preliminary} mutableCopy];
        [malformedLegacyRevisionSource.testDefaults setDouble:400
            forKey:acceptedOriginKey];
        [malformedLegacyRevisionSource.testDefaults
            setObject:preliminary[@"identifier"]
               forKey:@"GDTBackupNotification.office.lastDeliveredIdentifier"];
        [malformedLegacyRevisionSource.testDefaults
            setObject:@"retry-running.+430"
               forKey:@"GDTBackupNotification.office.lastDeliveredRevision"];
        NotificationTestDelegate *malformedLegacyRevisionAfterRestart =
            [[NotificationTestDelegate alloc] init];
        malformedLegacyRevisionAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:malformedLegacyRevisionSuite];
        malformedLegacyRevisionAfterRestart.deliverySucceeds = YES;
        malformedLegacyRevisionAfterRestart.acceptedBackupDecisionsByIdentifier =
            malformedLegacyRevisionSource.acceptedBackupDecisionsByIdentifier;
        Process(malformedLegacyRevisionAfterRestart, laterRetryRunning);
        NSDictionary *migratedMalformedLegacyState =
            [malformedLegacyRevisionAfterRestart.testDefaults dictionaryForKey:
                acceptedStateKey];
        Assert(malformedLegacyRevisionAfterRestart.deliveryCalls == 0 &&
               [malformedLegacyRevisionAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"failure"] &&
               [[malformedLegacyRevisionAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:preliminary[@"identifier"]] &&
               [[malformedLegacyRevisionAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.+430"] &&
               [migratedMalformedLegacyState[@"origin"] doubleValue] == 400 &&
               [migratedMalformedLegacyState[@"stage"] integerValue] == 3,
               @"a malformed legacy running revision fails closed instead of authorizing an update");

        NotificationTestDelegate *interruptedTerminalPersistence =
            [[NotificationTestDelegate alloc] init];
        interruptedTerminalPersistence.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".interrupted-terminal-persistence"]];
        interruptedTerminalPersistence.deliverySucceeds = YES;
        [interruptedTerminalPersistence.testDefaults
            setObject:finalRetryFailure[@"identifier"]
               forKey:@"GDTBackupNotification.office.lastDeliveredIdentifier"];
        [interruptedTerminalPersistence.testDefaults
            setObject:@[preliminary[@"identifier"]]
               forKey:@"GDTBackupNotification.office.deliveredFailureIdentifiers"];
        [interruptedTerminalPersistence.testDefaults setDouble:400
            forKey:acceptedOriginKey];
        [interruptedTerminalPersistence.testDefaults setInteger:2
            forKey:acceptedStageKey];
        Process(interruptedTerminalPersistence, finalRetryFailure);
        Process(interruptedTerminalPersistence, retryRunningDecision);
        Assert(interruptedTerminalPersistence.deliveryCalls == 0 &&
               [interruptedTerminalPersistence.testDefaults integerForKey:
                   acceptedStageKey] == 3 &&
               [[interruptedTerminalPersistence.testDefaults stringArrayForKey:
                   @"GDTBackupNotification.office.deliveredFailureIdentifiers"]
                       isEqualToArray:@[finalRetryFailure[@"identifier"]]] &&
               [interruptedTerminalPersistence.removedNotificationIdentifiers
                   isEqualToArray:@[preliminary[@"identifier"]]],
               @"replaying an interrupted accepted terminal update repairs its durable stage before stale running work");

        NotificationTestDelegate *acceptedNewerOriginOrdering =
            [[NotificationTestDelegate alloc] init];
        acceptedNewerOriginOrdering.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".accepted-newer-origin-ordering"]];
        acceptedNewerOriginOrdering.deliverySucceeds = YES;
        Process(acceptedNewerOriginOrdering, newerIndependentFailure);
        Process(acceptedNewerOriginOrdering, preliminary);
        Assert(acceptedNewerOriginOrdering.deliveryCalls == 1 &&
               acceptedNewerOriginOrdering.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [acceptedNewerOriginOrdering.acceptedBackupDecisionsByIdentifier[
                   newerIndependentFailure[@"identifier"]][@"issueOriginTimestamp"]
                       isEqualToString:@"500"] &&
               [acceptedNewerOriginOrdering.testDefaults doubleForKey:
                   acceptedOriginKey] == 500 &&
               [acceptedNewerOriginOrdering.testDefaults integerForKey:
                   acceptedStageKey] == 1 &&
               [[acceptedNewerOriginOrdering.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:newerIndependentFailure[@"identifier"]],
               @"an accepted newer issue origin cannot be rolled back by an older origin");

        NSString *newerOriginRestartSuite =
            [suiteName stringByAppendingString:@".accepted-newer-origin-restart"];
        NotificationTestDelegate *newerOriginRestartSource =
            [[NotificationTestDelegate alloc] init];
        newerOriginRestartSource.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:newerOriginRestartSuite];
        newerOriginRestartSource.deliverySucceeds = YES;
        Process(newerOriginRestartSource, newerIndependentFailure);
        NotificationTestDelegate *newerOriginAfterRestart =
            [[NotificationTestDelegate alloc] init];
        newerOriginAfterRestart.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:newerOriginRestartSuite];
        newerOriginAfterRestart.deliverySucceeds = YES;
        newerOriginAfterRestart.acceptedBackupDecisionsByIdentifier =
            newerOriginRestartSource.acceptedBackupDecisionsByIdentifier;
        Process(newerOriginAfterRestart, preliminary);
        Assert(newerOriginAfterRestart.deliveryCalls == 0 &&
               newerOriginAfterRestart.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]] == nil &&
               [newerOriginAfterRestart.acceptedBackupDecisionsByIdentifier[
                   newerIndependentFailure[@"identifier"]][@"issueOriginTimestamp"]
                       isEqualToString:@"500"] &&
               [newerOriginAfterRestart.testDefaults doubleForKey:
                   acceptedOriginKey] == 500 &&
               [newerOriginAfterRestart.testDefaults integerForKey:
                   acceptedStageKey] == 1 &&
               [[newerOriginAfterRestart.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"]
                       isEqualToString:newerIndependentFailure[@"identifier"]],
               @"a restart preserves a newer accepted origin against an older observation");

        NotificationTestDelegate *tornNewerOriginMirrors =
            [[NotificationTestDelegate alloc] init];
        tornNewerOriginMirrors.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName
                stringByAppendingString:@".torn-newer-origin-mirrors"]];
        tornNewerOriginMirrors.deliverySucceeds = YES;
        tornNewerOriginMirrors.acceptedBackupDecisionsByIdentifier =
            [@{newerIndependentFailure[@"identifier"]: newerIndependentFailure}
                mutableCopy];
        [tornNewerOriginMirrors.testDefaults setObject:@{
            @"origin": @500,
            @"stage": @1
        } forKey:acceptedStateKey];
        [tornNewerOriginMirrors.testDefaults setDouble:500
            forKey:acceptedOriginKey];
        [tornNewerOriginMirrors.testDefaults setInteger:3
            forKey:acceptedStageKey];
        NSMutableDictionary<NSString *, NSString *> *newerRetryRunning =
            [newerIndependentFailure mutableCopy];
        newerRetryRunning[@"kind"] = @"retry-running";
        newerRetryRunning[@"revision"] = @"retry-running.510";
        newerRetryRunning[@"titleKey"] = @"backupNotificationRetryRunningTitle";
        newerRetryRunning[@"bodyKey"] = @"backupNotificationRetryRunningBody";
        Process(tornNewerOriginMirrors, newerRetryRunning);
        NSDictionary *repairedNewerState =
            [tornNewerOriginMirrors.testDefaults dictionaryForKey:acceptedStateKey];
        Assert(tornNewerOriginMirrors.deliveryCalls == 1 &&
               [tornNewerOriginMirrors.acceptedBackupDecisionsByIdentifier[
                   newerIndependentFailure[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"] &&
               [repairedNewerState[@"origin"] doubleValue] == 500 &&
               [repairedNewerState[@"stage"] integerValue] == 2 &&
               [tornNewerOriginMirrors.testDefaults integerForKey:
                   acceptedStageKey] == 2,
               @"one accepted-state record prevents a torn newer origin from inheriting an older terminal stage");

        Process(replacement, finalRetryFailure);
        NSArray<NSString *> *remainingFailureIdentifiers =
            [replacement.testDefaults stringArrayForKey:
                @"GDTBackupNotification.office.deliveredFailureIdentifiers"];
        Assert(replacement.deliveryCalls == 3 &&
               [replacement.removedNotificationIdentifiers isEqualToArray:
                   @[@"com.commcats.gdrivebackup.office.failure.400"]] &&
               [remainingFailureIdentifiers isEqualToArray:
                   @[@"com.commcats.gdrivebackup.office.failure.430"]],
               @"an accepted final retry failure replaces its preliminary alert");

        replacement.removedNotificationIdentifiers = nil;
        Process(replacement, finalRetryFailure);
        Assert(replacement.deliveryCalls == 3 &&
               [replacement.removedNotificationIdentifiers isEqualToArray:
                   @[@"com.commcats.gdrivebackup.office.failure.400"]],
               @"a restart safely finishes an interrupted preliminary-alert cleanup");

        NotificationTestDelegate *refusedReplacement =
            [[NotificationTestDelegate alloc] init];
        refusedReplacement.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".refused-replacement"]];
        refusedReplacement.deliverySucceeds = YES;
        Process(refusedReplacement, preliminary);
        Process(refusedReplacement, retryRunningDecision);
        refusedReplacement.deliverySucceeds = NO;
        Process(refusedReplacement, finalRetryFailure);
        Process(refusedReplacement, finalRetryFailure);
        NSArray<NSString *> *refusedIdentifiers =
            [refusedReplacement.testDefaults stringArrayForKey:
                @"GDTBackupNotification.office.deliveredFailureIdentifiers"];
        Assert(refusedReplacement.removedNotificationIdentifiers == nil &&
               refusedReplacement.deliveryCalls == 4 &&
               [refusedIdentifiers isEqualToArray:
                   @[@"com.commcats.gdrivebackup.office.failure.400"]] &&
               [[refusedReplacement.testDefaults stringForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"]
                       isEqualToString:@"retry-running.430"] &&
               [refusedReplacement.testDefaults integerForKey:
                   acceptedStageKey] == 2 &&
               [refusedReplacement.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"retry-running"],
               @"a rejected replacement leaves the existing visible warning intact");

        NotificationTestDelegate *refusedRevision =
            [[NotificationTestDelegate alloc] init];
        refusedRevision.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".refused-revision"]];
        refusedRevision.deliverySucceeds = YES;
        Process(refusedRevision, preliminary);
        refusedRevision.deliverySucceeds = NO;
        Process(refusedRevision, retryRunningDecision);
        Process(refusedRevision, retryRunningDecision);
        Assert(refusedRevision.deliveryCalls == 3 &&
               [refusedRevision.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"] == nil &&
               [refusedRevision.testDefaults integerForKey:
                   acceptedStageKey] == 1 &&
               [refusedRevision.acceptedBackupDecisionsByIdentifier[
                   preliminary[@"identifier"]][@"kind"]
                       isEqualToString:@"failure"],
               @"a rejected running revision remains retryable and is never persisted");

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
        typedef UNMutableNotificationContent *(*ContentMethod)(
            id, SEL, NSDictionary *);
        ContentMethod contentMethod = nil;
        UNMutableNotificationContent *content = nil;
        if ([delegate respondsToSelector:contentSelector]) {
            contentMethod = (ContentMethod)[delegate methodForSelector:contentSelector];
            content = contentMethod(delegate, contentSelector, first);
        }
        BOOL activeLevel = NO;
        if (@available(macOS 12.0, *)) {
            activeLevel =
                content.interruptionLevel == UNNotificationInterruptionLevelActive;
        }
        Assert(content.sound != nil &&
               [content.categoryIdentifier isEqualToString:@"GDT_BACKUP_ALERT"] &&
               [content.userInfo[@"profileID"] isEqualToString:@"office"] &&
               [content.userInfo[@"issueOriginTimestamp"] isEqualToString:@"100"] &&
               activeLevel,
               @"backup alerts carry acknowledgement metadata and stay audible at an allowed level");

        delegate.testTimeSensitiveNotificationsEnabled = YES;
        UNMutableNotificationContent *entitledContent = contentMethod
            ? contentMethod(delegate, contentSelector, first) : nil;
        BOOL timeSensitiveLevel = NO;
        if (@available(macOS 12.0, *)) {
            timeSensitiveLevel =
                entitledContent.interruptionLevel ==
                    UNNotificationInterruptionLevelTimeSensitive;
        }
        Assert(timeSensitiveLevel,
               @"properly entitled builds elevate automatic backup alerts to time-sensitive");

        NSDictionary<NSString *, NSString *> *successContentDecision = @{
            @"identifier": @"com.commcats.gdrivebackup.office.success.200",
            @"profileID": @"office",
            @"kind": @"success",
            @"eventTimestamp": @"200",
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationRecoverySuccessBody"
        };
        UNMutableNotificationContent *successContent = contentMethod
            ? contentMethod(delegate, contentSelector, successContentDecision) : nil;
        BOOL normalSuccessLevel = NO;
        if (@available(macOS 12.0, *)) {
            normalSuccessLevel =
                successContent.interruptionLevel == UNNotificationInterruptionLevelActive;
        }
        Assert(successContent.sound == nil &&
               [successContent.categoryIdentifier isEqualToString:@"GDT_BACKUP_SUCCESS"] &&
               [successContent.userInfo isEqualToDictionary:@{
                   @"profileID": @"office", @"eventTimestamp": @"200"
               }] &&
               normalSuccessLevel,
               @"success confirmations are silent, normal-priority, and contain only safe metadata");

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
               (categoriesByID[@"GDT_BACKUP_ALERT"].options &
                    UNNotificationCategoryOptionCustomDismissAction) != 0 &&
               categoriesByID[@"GDT_BACKUP_SUCCESS"] != nil &&
               unknownCategory != nil &&
               unknownCategory.actions.count == 2 &&
               (unknownActionsByID[@"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP"].options &
                    UNNotificationActionOptionForeground) != 0 &&
               unknownActionsByID[@"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE"].options ==
                    UNNotificationActionOptionNone,
               @"backup alerts register dismissal while success confirmations and disk notices remain separate");

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
        UNNotificationPresentationOptions successPresentation = 0;
        if ([delegate respondsToSelector:presentationSelector]) {
            typedef UNNotificationPresentationOptions (*PresentationMethod)(
                id, SEL, NSString *);
            PresentationMethod presentationMethod =
                (PresentationMethod)[delegate methodForSelector:presentationSelector];
            unknownPresentation = presentationMethod(
                delegate, presentationSelector, @"GDT_UNKNOWN_EXTERNAL_VOLUME");
            failurePresentation = presentationMethod(
                delegate, presentationSelector, @"GDT_BACKUP_ALERT");
            successPresentation = presentationMethod(
                delegate, presentationSelector, @"GDT_BACKUP_SUCCESS");
        }
        Assert((unknownPresentation & UNNotificationPresentationOptionList) != 0 &&
               (unknownPresentation & UNNotificationPresentationOptionSound) == 0 &&
               (failurePresentation & UNNotificationPresentationOptionSound) != 0 &&
               (successPresentation & UNNotificationPresentationOptionSound) == 0,
               @"success and unknown-disk notices stay silent while backup failures remain audible");

        BOOL unknownVolumeLocalized = YES;
        for (NSString *code in SupportedLanguageCodes()) {
            for (NSString *key in @[
                @"unknownExternalVolumeTitle",
                @"unknownExternalVolumeBody",
                @"unknownExternalVolumeSetupAction",
                @"unknownExternalVolumeIgnoreAction",
                @"unknownExternalVolumeReviewSetup",
                @"unknownExternalVolumeUnavailable",
                @"unknownExternalVolumeChooseTitle",
                @"unknownExternalVolumeChooseBody",
                @"unknownExternalVolumeChooseAction",
                @"unknownExternalVolumeChoiceLabelFormat",
                @"backupNotificationRetryRunningTitle",
                @"backupNotificationRetryRunningBody"
            ]) {
                NSString *localized = T(code, key);
                if (!localized.length || [localized isEqualToString:key]) {
                    unknownVolumeLocalized = NO;
                }
            }
        }
        Assert(unknownVolumeLocalized,
               @"unknown external-volume notification and setup text is localized in every language");

        NSDictionary<NSString *, NSArray<NSString *> *> *retryRunningTranslations = @{
            @"de": @[@"Automatischer Wiederholungsversuch läuft",
                     @"GDrive wird erneut gesichert. Öffne GDrive Backup Tiger, um den Fortschritt zu sehen."],
            @"en": @[@"Automatic backup retry is running",
                     @"GDrive is being backed up again. Open GDrive Backup Tiger to view progress."],
            @"fr": @[@"Nouvelle tentative de sauvegarde automatique en cours",
                     @"Une nouvelle sauvegarde de GDrive est en cours. Ouvrez GDrive Backup Tiger pour suivre la progression."],
            @"es": @[@"Reintento automático de copia de seguridad en curso",
                     @"Se está realizando de nuevo la copia de seguridad de GDrive. Abre GDrive Backup Tiger para ver el progreso."],
            @"ja": @[@"自動バックアップを再試行中",
                     @"GDrive をもう一度バックアップしています。進行状況を確認するには GDrive Backup Tiger を開いてください。"],
            @"yue": @[@"自動備份重試進行中",
                      @"GDrive 正在再次備份。請開啟 GDrive Backup Tiger 查看進度。"],
            @"ko": @[@"자동 백업 재시도 실행 중",
                     @"GDrive를 다시 백업하고 있습니다. 진행 상황을 보려면 GDrive Backup Tiger를 여십시오."]
        };
        BOOL exactRetryRunningTranslations = YES;
        for (NSString *code in SupportedLanguageCodes()) {
            NSArray<NSString *> *expected = retryRunningTranslations[code];
            exactRetryRunningTranslations = exactRetryRunningTranslations &&
                expected.count == 2 &&
                [T(code, @"backupNotificationRetryRunningTitle") isEqualToString:expected[0]] &&
                [T(code, @"backupNotificationRetryRunningBody") isEqualToString:expected[1]];
        }
        Assert(exactRetryRunningTranslations,
               @"the retry-running alert uses the reviewed copy in every language");

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

        unknownActionDelegate.revalidatedCandidates = @[unknownDescriptor];
        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP", unknownUserInfo);
        ProcessUnknownVolumeAction(
            unknownActionDelegate, UNNotificationDefaultActionIdentifier, unknownUserInfo);
        ProcessUnknownVolumeAction(
            unknownActionDelegate, @"UNEXPECTED_ACTION", unknownUserInfo);
        Assert(unknownActionDelegate.revalidationCalls == 3 &&
               unknownActionDelegate.choiceCalls == 0 &&
               unknownActionDelegate.setupPresentationCalls == 2 &&
               unknownActionDelegate.overviewPresentationCalls == 0 &&
               unknownActionDelegate.configSaveCalls == 0 &&
               unknownActionDelegate.backupLaunchCalls == 0,
               @"one eligible target stages only after an explicit notification action and never opens a picker");

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
        Assert(remainingSiblingDelegate.setupPresentationCalls == 0 &&
               remainingSiblingDelegate.unavailablePresentationCalls == 1,
               @"a vanished originally offered UUID never silently falls back to a sibling volume");

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

        NSDictionary<NSString *, id> *duplicateNameSiblingDescriptor = @{
            @"path": @"/Volumes/TOSHIBA_4TB 1",
            @"name": @"TOSHIBA_4TB",
            @"volumeUUID": @"SIBLING-UUID",
            @"diskID": @"disk20",
            @"isLocal": @YES,
            @"isInternal": @NO,
            @"isPhysical": @YES,
            @"isSystemImage": @NO,
            @"isWritable": @YES,
            @"filesystem": @"apfs"
        };
        PickerUnknownVolumeNotificationTestDelegate *multipleCandidateDelegate =
            [[PickerUnknownVolumeNotificationTestDelegate alloc] init];
        multipleCandidateDelegate.selectedCandidateIndex = -1;
        multipleCandidateDelegate.candidateMountPaths = @[
            @"/Volumes/TOSHIBA_4TB", @"/Volumes/TOSHIBA_4TB 1"
        ];
        multipleCandidateDelegate.descriptorsByPath = @{
            @"/Volumes/TOSHIBA_4TB": matchingRestartDescriptor,
            @"/Volumes/TOSHIBA_4TB 1": duplicateNameSiblingDescriptor
        };
        NSDictionary *multipleCandidateUserInfo = @{
            @"diskID": @"disk20",
            @"volumeUUID": @"PRIVATE-UUID",
            @"attachmentVolumeUUIDs": @[@"PRIVATE-UUID", @"SIBLING-UUID"]
        };
        ProcessUnknownVolumeAction(
            multipleCandidateDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            multipleCandidateUserInfo);
        Assert(multipleCandidateDelegate.choiceCalls == 1 &&
               multipleCandidateDelegate.choiceCandidates.count == 2 &&
               multipleCandidateDelegate.setupPresentationCalls == 0 &&
               multipleCandidateDelegate.unavailablePresentationCalls == 0,
               @"multiple eligible volumes require a picker and cancellation leaves setup unchanged");

        SEL choiceLabelsSelector = NSSelectorFromString(
            @"unknownExternalVolumeChoiceLabelsForDescriptors:");
        NSArray<NSString *> *duplicateNameLabels = @[];
        if ([multipleCandidateDelegate respondsToSelector:choiceLabelsSelector]) {
            typedef NSArray<NSString *> *(*ChoiceLabelsMethod)(id, SEL, NSArray *);
            ChoiceLabelsMethod choiceLabelsMethod =
                (ChoiceLabelsMethod)[multipleCandidateDelegate
                    methodForSelector:choiceLabelsSelector];
            duplicateNameLabels = choiceLabelsMethod(
                multipleCandidateDelegate,
                choiceLabelsSelector,
                @[matchingRestartDescriptor, duplicateNameSiblingDescriptor]);
        }
        BOOL safeDuplicateLabels = duplicateNameLabels.count == 2 &&
            [duplicateNameLabels[0] containsString:@"TOSHIBA_4TB"] &&
            [duplicateNameLabels[1] containsString:@"TOSHIBA_4TB 1"];
        for (NSString *label in duplicateNameLabels) {
            safeDuplicateLabels = safeDuplicateLabels &&
                ![label containsString:@"PRIVATE-UUID"] &&
                ![label containsString:@"SIBLING-UUID"] &&
                ![label containsString:@"disk20"] &&
                ![label containsString:@"/Volumes/"];
        }
        Assert(safeDuplicateLabels,
               @"duplicate volume names are distinguished by safe mount labels without UUID or BSD identifiers");

        PickerUnknownVolumeNotificationTestDelegate *selectedCandidateDelegate =
            [[PickerUnknownVolumeNotificationTestDelegate alloc] init];
        selectedCandidateDelegate.selectedCandidateIndex = 1;
        selectedCandidateDelegate.candidateMountPaths =
            multipleCandidateDelegate.candidateMountPaths;
        selectedCandidateDelegate.descriptorsByPath =
            multipleCandidateDelegate.descriptorsByPath;
        ProcessUnknownVolumeAction(
            selectedCandidateDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            multipleCandidateUserInfo);
        Assert(selectedCandidateDelegate.choiceCalls == 1 &&
               selectedCandidateDelegate.setupPresentationCalls == 1 &&
               selectedCandidateDelegate.presentedDescriptor ==
                   duplicateNameSiblingDescriptor &&
               selectedCandidateDelegate.mountEnumerationCalls == 1 &&
               selectedCandidateDelegate.inspectedPaths.count == 3 &&
               [selectedCandidateDelegate.inspectedPaths.lastObject
                   isEqualToString:@"/Volumes/TOSHIBA_4TB 1"],
               @"an explicitly selected UUID is revalidated and only then staged");

        PickerUnknownVolumeNotificationTestDelegate *disappearedSelectionDelegate =
            [[PickerUnknownVolumeNotificationTestDelegate alloc] init];
        disappearedSelectionDelegate.selectedCandidateIndex = 0;
        disappearedSelectionDelegate.candidateMountPaths =
            multipleCandidateDelegate.candidateMountPaths;
        disappearedSelectionDelegate.descriptorsByPath =
            multipleCandidateDelegate.descriptorsByPath;
        disappearedSelectionDelegate.descriptorsByPathBeforeChoiceCompletion = @{
            @"/Volumes/TOSHIBA_4TB 1": duplicateNameSiblingDescriptor
        };
        ProcessUnknownVolumeAction(
            disappearedSelectionDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            multipleCandidateUserInfo);
        Assert(disappearedSelectionDelegate.choiceCalls == 1 &&
               disappearedSelectionDelegate.setupPresentationCalls == 0 &&
               disappearedSelectionDelegate.unavailablePresentationCalls == 1,
               @"a selected volume that disappears cannot fall through to a mounted sibling");

        NSMutableDictionary<NSString *, id> *swappedDescriptor =
            [matchingRestartDescriptor mutableCopy];
        swappedDescriptor[@"volumeUUID"] = @"REPLACEMENT-UUID";
        PickerUnknownVolumeNotificationTestDelegate *swappedSelectionDelegate =
            [[PickerUnknownVolumeNotificationTestDelegate alloc] init];
        swappedSelectionDelegate.selectedCandidateIndex = 0;
        swappedSelectionDelegate.candidateMountPaths =
            multipleCandidateDelegate.candidateMountPaths;
        swappedSelectionDelegate.descriptorsByPath =
            multipleCandidateDelegate.descriptorsByPath;
        swappedSelectionDelegate.descriptorsByPathBeforeChoiceCompletion = @{
            @"/Volumes/TOSHIBA_4TB": swappedDescriptor,
            @"/Volumes/TOSHIBA_4TB 1": duplicateNameSiblingDescriptor
        };
        ProcessUnknownVolumeAction(
            swappedSelectionDelegate,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
            multipleCandidateUserInfo);
        Assert(swappedSelectionDelegate.choiceCalls == 1 &&
               swappedSelectionDelegate.setupPresentationCalls == 0 &&
               swappedSelectionDelegate.unavailablePresentationCalls == 1,
               @"a selected mount root whose UUID changed fails closed before staging");

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
        Assert(lateSiblingActionDelegate.setupPresentationCalls == 0 &&
               lateSiblingActionDelegate.unavailablePresentationCalls == 1,
               @"an attachment marker cannot substitute a later sibling for the offered UUID");

        UnknownVolumeNotificationTestDelegate *backgroundActionDelegate =
            [[UnknownVolumeNotificationTestDelegate alloc] init];
        backgroundActionDelegate.revalidatedCandidates = @[unknownDescriptor];
        dispatch_semaphore_t backgroundActionReturned = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            ProcessUnknownVolumeAction(
                backgroundActionDelegate,
                @"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP",
                unknownUserInfo);
            // The handler only queues its main-thread work, so signal after
            // submission and let the test pump only the actual action path.
            dispatch_semaphore_signal(backgroundActionReturned);
        });
        BOOL backgroundActionSubmitted = dispatch_semaphore_wait(
            backgroundActionReturned,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))) == 0;
        BOOL backgroundActionCompleted = backgroundActionSubmitted &&
            WaitForCondition(^BOOL{
                return backgroundActionDelegate.setupPresentationCalls == 1;
            }, 2.0);
        Assert(backgroundActionSubmitted && backgroundActionCompleted &&
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

        BackupCleanupRaceTestDelegate *cleanupRace =
            [[BackupCleanupRaceTestDelegate alloc] init];
        NSString *cleanupSuiteName =
            [suiteName stringByAppendingString:@".cleanup-race"];
        cleanupRace.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:cleanupSuiteName];
        NSString *cleanupPrefix = @"GDTBackupNotification.office.";
        NSString *oldFailureID =
            @"com.commcats.gdrivebackup.office.failure.100";
        NSString *oldMissedID =
            @"com.commcats.gdrivebackup.office.missed.200";
        NSString *newFailureID =
            @"com.commcats.gdrivebackup.office.failure.600";
        [cleanupRace.testDefaults setObject:@[oldFailureID]
            forKey:[cleanupPrefix stringByAppendingString:
                @"deliveredFailureIdentifiers"]];
        [cleanupRace.testDefaults setObject:oldFailureID
            forKey:[cleanupPrefix stringByAppendingString:
                @"lastDeliveredIdentifier"]];
        [cleanupRace.testDefaults setObject:@{@"origin": @400, @"stage": @1}
            forKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueState"]];
        [cleanupRace.testDefaults setDouble:400
            forKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueAt"]];
        [cleanupRace.testDefaults setDouble:400
            forKey:[cleanupPrefix stringByAppendingString:@"activeIssueAt"]];

        [cleanupRace clearBackupFailureNotificationsForConfig:
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"}
            summary:@{@"status": @"success", @"finished_at": @"500",
                      @"trigger": @"schedule-retry"}
            status:@"success"];
        Assert(cleanupRace.deferredDeliveredEnumeration != nil &&
               cleanupRace.removedDeliveredNotificationIdentifiers == nil &&
               cleanupRace.removedPendingNotificationIdentifiers == nil,
               @"automatic-success cleanup waits for delivered-notification enumeration");

        [cleanupRace.testDefaults setObject:@[newFailureID]
            forKey:[cleanupPrefix stringByAppendingString:
                @"deliveredFailureIdentifiers"]];
        [cleanupRace.testDefaults setObject:newFailureID
            forKey:[cleanupPrefix stringByAppendingString:
                @"lastDeliveredIdentifier"]];
        [cleanupRace.testDefaults setObject:@{@"origin": @600, @"stage": @1}
            forKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueState"]];
        [cleanupRace.testDefaults setDouble:600
            forKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueAt"]];
        [cleanupRace.testDefaults setInteger:1
            forKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueStage"]];
        [cleanupRace.testDefaults setDouble:600
            forKey:[cleanupPrefix stringByAppendingString:@"activeIssueAt"]];
        [cleanupRace.testDefaults setObject:@"failure"
            forKey:[cleanupPrefix stringByAppendingString:@"activeIssueKind"]];
        [cleanupRace.testDefaults setObject:newFailureID
            forKey:[cleanupPrefix stringByAppendingString:
                @"activeIssueIdentifier"]];

        NSString *trustedOldOriginID =
            @"com.commcats.gdrivebackup.office.failure.700";
        NSString *trustedNewOriginID =
            @"com.commcats.gdrivebackup.office.failure.300";
        NSArray<UNNotification *> *deliveredDuringCleanup = @[
            DeliveredBackupNotification(oldFailureID, @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"100"}),
            DeliveredBackupNotification(oldMissedID, @"", @{}),
            DeliveredBackupNotification(newFailureID, @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"600"}),
            DeliveredBackupNotification(trustedOldOriginID, @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"400"}),
            DeliveredBackupNotification(trustedNewOriginID, @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"600"}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.office.failure.not-a-time",
                @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"100"}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.office.missed.0200", @"", @{}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.archive.failure.100",
                @"GDT_BACKUP_ALERT",
                @{@"profileID": @"archive", @"issueOriginTimestamp": @"100"}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.office.failure.250",
                @"GDT_BACKUP_ALERT",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"0400"}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.office.failure.230",
                @"GDT_BACKUP_ALERT",
                @{@"profileID": @"archive", @"issueOriginTimestamp": @"230"}),
            DeliveredBackupNotification(
                @"com.commcats.gdrivebackup.office.failure.240",
                @"GDT_UNKNOWN_EXTERNAL_VOLUME",
                @{@"profileID": @"office", @"issueOriginTimestamp": @"240"})
        ];
        cleanupRace.deferredDeliveredEnumeration(deliveredDuringCleanup);
        cleanupRace.deferredDeliveredEnumeration = nil;

        NSSet<NSString *> *expectedCleanupIDs = [NSSet setWithArray:@[
            oldFailureID, oldMissedID, trustedOldOriginID
        ]];
        Assert(cleanupRace.removedDeliveredNotificationIdentifiers.count == 3 &&
               [[NSSet setWithArray:
                   cleanupRace.removedDeliveredNotificationIdentifiers]
                       isEqualToSet:expectedCleanupIDs] &&
               cleanupRace.removedPendingNotificationIdentifiers.count == 3 &&
               [[NSSet setWithArray:
                   cleanupRace.removedPendingNotificationIdentifiers]
                       isEqualToSet:expectedCleanupIDs],
               @"a delayed success cleanup removes only canonical issue origins at or before its cutoff");
        NSDictionary *newAcceptedState = [cleanupRace.testDefaults
            dictionaryForKey:[cleanupPrefix stringByAppendingString:
                @"latestDeliveredIssueState"]];
        Assert([newAcceptedState[@"origin"] doubleValue] == 600 &&
               [cleanupRace.testDefaults doubleForKey:
                   [cleanupPrefix stringByAppendingString:@"activeIssueAt"]] == 600 &&
               [[cleanupRace.testDefaults stringForKey:
                   [cleanupPrefix stringByAppendingString:
                       @"activeIssueIdentifier"]]
                           isEqualToString:newFailureID] &&
               [[cleanupRace.testDefaults stringArrayForKey:
                   [cleanupPrefix stringByAppendingString:
                       @"deliveredFailureIdentifiers"]]
                           isEqualToArray:@[newFailureID]],
               @"a failure introduced during cleanup stays latched and deduplicated");
        [cleanupRace.testDefaults removePersistentDomainForName:cleanupSuiteName];

        delegate.extraDeliveredNotificationIdentifiers = @[
            @"com.commcats.gdrivebackup.office.missed.50"
        ];
        [delegate.testDefaults setDouble:200
            forKey:@"GDTBackupNotification.office.activeIssueAt"];
        [delegate.testDefaults setObject:@"failure"
            forKey:@"GDTBackupNotification.office.activeIssueKind"];
        [delegate.testDefaults
            setObject:@"com.commcats.gdrivebackup.office.failure.200"
               forKey:@"GDTBackupNotification.office.activeIssueIdentifier"];
        [delegate.testDefaults setDouble:150
            forKey:@"GDTBackupNotification.office.dismissedIssueAt"];
        [delegate.testDefaults setObject:@"retry-running.190"
            forKey:@"GDTBackupNotification.office.lastDeliveredRevision"];
        [delegate.testDefaults setInteger:3
            forKey:@"GDTBackupNotification.office.latestDeliveredIssueStage"];
        [delegate.testDefaults setObject:@{
            @"origin": @200,
            @"stage": @3
        } forKey:@"GDTBackupNotification.office.latestDeliveredIssueState"];
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
                   containsObject:@"com.commcats.gdrivebackup.office.missed.50"] &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredIdentifier"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.lastDeliveredRevision"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.latestDeliveredIssueStage"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.latestDeliveredIssueState"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.dismissedIssueAt"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.activeIssueAt"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.activeIssueKind"] == nil &&
               [delegate.testDefaults objectForKey:
                   @"GDTBackupNotification.office.activeIssueIdentifier"] == nil,
               @"a later automatic success removes every delivered failure alert for that profile");

        SEL alertStatusSelector = NSSelectorFromString(
            @"backupAlertStatusForConfig:summary:rawStatus:decision:");
        typedef NSString *(*AlertStatusMethod)(id, SEL, NSDictionary *, NSDictionary *,
                                               NSString *, NSDictionary *);
        AlertStatusMethod alertStatus = [delegate respondsToSelector:alertStatusSelector]
            ? (AlertStatusMethod)[delegate methodForSelector:alertStatusSelector] : NULL;
        NSDictionary *profileConfig = @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"};
        NSDictionary *missedDecision = @{
            @"identifier": @"com.commcats.gdrivebackup.office.missed.100",
            @"profileID": @"office", @"kind": @"missed",
            @"issueTimestamp": @"100", @"issueOriginTimestamp": @"100"
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
            @"identifier": @"com.commcats.gdrivebackup.office.failure.200",
            @"profileID": @"office", @"kind": @"failure",
            @"issueTimestamp": @"230", @"issueOriginTimestamp": @"200"
        };
        NSString *failureStatus = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{}, @"failure", failureDecision) : nil;
        NSDictionary *runningRetryStatusDecision = @{
            @"identifier": @"com.commcats.gdrivebackup.office.failure.200",
            @"profileID": @"office", @"kind": @"retry-running",
            @"revision": @"retry-running.240", @"issueTimestamp": @"200",
            @"issueOriginTimestamp": @"200"
        };
        NSString *retryRunningStatus = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig,
            @{@"started_at": @"240", @"trigger": @"schedule-retry",
              @"retry_origin_started_at": @"200", @"retry_attempt": @"1"},
            @"running", runningRetryStatusDecision) : nil;
        BOOL failureLatchSurvivedRetryStart =
            [delegate.testDefaults doubleForKey:
                @"GDTBackupNotification.office.activeIssueAt"] == 200 &&
            [[delegate.testDefaults stringForKey:
                @"GDTBackupNotification.office.activeIssueKind"]
                    isEqualToString:@"failure"] &&
            [[delegate.testDefaults stringForKey:
                @"GDTBackupNotification.office.activeIssueIdentifier"]
                    isEqualToString:@"com.commcats.gdrivebackup.office.failure.200"];
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
               [retryRunningStatus isEqualToString:@"retry-running"] &&
               failureLatchSurvivedRetryStart &&
               [oldSuccessDoesNotClear isEqualToString:@"failure"] &&
               [manualNewSuccessDoesNotClear isEqualToString:@"failure"] &&
               [newSuccessClears isEqualToString:@"success"],
               @"a running retry is non-red without clearing the failure latch, which only a newer automatic success clears");

        BackupActionTestDelegate *actionDelegate =
            [[BackupActionTestDelegate alloc] init];
        actionDelegate.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:
            [suiteName stringByAppendingString:@".backup-actions"]];
        actionDelegate.deliverySucceeds = YES;
        NSString *activeAtKey = @"GDTBackupNotification.office.activeIssueAt";
        NSString *activeKindKey = @"GDTBackupNotification.office.activeIssueKind";
        NSString *activeIDKey = @"GDTBackupNotification.office.activeIssueIdentifier";
        NSString *dismissedKey = @"GDTBackupNotification.office.dismissedIssueAt";
        NSString *oldID = @"com.commcats.gdrivebackup.office.failure.400";
        NSString *newID = @"com.commcats.gdrivebackup.office.failure.500";
        [actionDelegate.testDefaults setDouble:400 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:oldID forKey:activeIDKey];
        HandleBackupAction(actionDelegate, UNNotificationDismissActionIdentifier,
            @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"400"}, oldID);
        Assert([actionDelegate.testDefaults doubleForKey:dismissedKey] == 400 &&
               [actionDelegate.testDefaults objectForKey:activeAtKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeKindKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeIDKey] == nil &&
               [actionDelegate.removedNotificationIdentifiers containsObject:oldID],
               @"an explicit matching dismiss acknowledges and retires one issue");

        [actionDelegate.testDefaults setDouble:500 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:newID forKey:activeIDKey];
        actionDelegate.removedDeliveredNotificationIdentifiers = nil;
        actionDelegate.removedPendingNotificationIdentifiers = nil;
        HandleBackupAction(actionDelegate, UNNotificationDismissActionIdentifier,
            @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"400"}, oldID);
        Assert([actionDelegate.testDefaults doubleForKey:dismissedKey] == 400 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 500 &&
               [[actionDelegate.testDefaults stringForKey:activeKindKey]
                   isEqualToString:@"failure"] &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:newID] &&
               [actionDelegate.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[oldID]] &&
               [actionDelegate.removedPendingNotificationIdentifiers
                   isEqualToArray:@[oldID]],
               @"a late dismissal retires only its old issue and cannot clear a newer latch");

        [actionDelegate.testDefaults removeObjectForKey:activeAtKey];
        [actionDelegate.testDefaults removeObjectForKey:activeKindKey];
        [actionDelegate.testDefaults removeObjectForKey:activeIDKey];
        NSInteger deliveriesBeforeRefresh = actionDelegate.deliveryCalls;
        NSMutableDictionary *sameIssueFinal = [finalRetryFailure mutableCopy];
        sameIssueFinal[@"issueTimestamp"] = @"430";
        sameIssueFinal[@"issueOriginTimestamp"] = @"400";
        if (alertStatus) {
            (void)alertStatus(actionDelegate, alertStatusSelector,
                @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
                @{@"started_at": @"410", @"finished_at": @"430",
                  @"trigger": @"schedule-retry"}, @"failure", sameIssueFinal);
        }
        Assert([actionDelegate.testDefaults objectForKey:activeAtKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeKindKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeIDKey] == nil,
               @"refresh cannot relatch a human-acknowledged origin");
        Process(actionDelegate, sameIssueFinal);
        Assert(actionDelegate.deliveryCalls == deliveriesBeforeRefresh,
               @"refresh cannot resurrect a dismissed origin under a later finish time");

        NSMutableDictionary *newFailure = [finalRetryFailure mutableCopy];
        newFailure[@"identifier"] = newID;
        [newFailure removeObjectForKey:@"supersedesIdentifier"];
        newFailure[@"issueTimestamp"] = @"530";
        newFailure[@"issueOriginTimestamp"] = @"500";
        NSString *newFailureStatus = alertStatus ? alertStatus(
            actionDelegate, alertStatusSelector,
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
            @{@"started_at": @"500", @"finished_at": @"530",
              @"trigger": @"schedule"}, @"failure", newFailure) : nil;
        Process(actionDelegate, newFailure);
        Assert([newFailureStatus isEqualToString:@"failure"] &&
               actionDelegate.deliveryCalls == deliveriesBeforeRefresh + 1 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 500 &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:newID],
               @"a later independent issue still delivers and remains latched");

        NSString *statusWithNoDeliveredRequests = alertStatus ? alertStatus(
            actionDelegate, alertStatusSelector,
            @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"}, @{}, @"unknown", nil) : nil;
        Assert([statusWithNoDeliveredRequests isEqualToString:@"failure"] &&
               [actionDelegate.testDefaults doubleForKey:dismissedKey] == 400 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 500 &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:newID],
               @"an empty delivered-notification observation never counts as human acknowledgement");

        NSString *openID = @"com.commcats.gdrivebackup.office.failure.600";
        [actionDelegate.testDefaults setDouble:600 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:openID forKey:activeIDKey];
        actionDelegate.removedNotificationIdentifiers = nil;
        HandleBackupAction(actionDelegate, @"GDT_OPEN_BACKUP_OVERVIEW",
            @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"600"}, openID);
        Assert([actionDelegate.testDefaults doubleForKey:dismissedKey] == 600 &&
               [actionDelegate.testDefaults objectForKey:activeAtKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeKindKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeIDKey] == nil &&
               [actionDelegate.removedNotificationIdentifiers containsObject:openID] &&
               actionDelegate.overviewShowCalls == 1 &&
               actionDelegate.overviewRefreshCalls == 1 &&
               actionDelegate.backupLaunchCalls == 0,
               @"the explicit Open action acknowledges its issue and opens the overview without launching a backup");

        NSString *protectedID = @"com.commcats.gdrivebackup.office.failure.700";
        [actionDelegate.testDefaults setDouble:700 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:protectedID forKey:activeIDKey];
        actionDelegate.removedNotificationIdentifiers = nil;
        HandleBackupAction(actionDelegate, UNNotificationDismissActionIdentifier,
            @"GDT_UNKNOWN_EXTERNAL_VOLUME",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"700"}, protectedID);
        HandleBackupAction(actionDelegate, UNNotificationDismissActionIdentifier,
            @"GDT_BACKUP_ALERT", @{@"profileID": @"office"}, protectedID);
        HandleBackupAction(actionDelegate, UNNotificationDefaultActionIdentifier,
            @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"700"}, protectedID);
        Assert([actionDelegate.testDefaults doubleForKey:dismissedKey] == 600 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 700 &&
               [[actionDelegate.testDefaults stringForKey:activeKindKey]
                   isEqualToString:@"failure"] &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:protectedID] &&
               actionDelegate.removedNotificationIdentifiers == nil &&
               actionDelegate.overviewShowCalls == 1 &&
               actionDelegate.backupLaunchCalls == 0,
               @"unrelated, malformed, and implicit actions cannot acknowledge or clear an issue");

        NSString *routedDismissID = @"com.commcats.gdrivebackup.office.failure.800";
        [actionDelegate.testDefaults setDouble:800 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:routedDismissID forKey:activeIDKey];
        actionDelegate.removedNotificationIdentifiers = nil;
        BOOL dismissResponseCompleted = RouteBackupResponse(
            actionDelegate, UNNotificationDismissActionIdentifier, @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"800"},
            routedDismissID);
        Assert(dismissResponseCompleted &&
               [actionDelegate.testDefaults doubleForKey:dismissedKey] == 800 &&
               [actionDelegate.testDefaults objectForKey:activeAtKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeKindKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeIDKey] == nil &&
               [actionDelegate.removedDeliveredNotificationIdentifiers
                   isEqualToArray:@[routedDismissID]] &&
               [actionDelegate.removedPendingNotificationIdentifiers
                   isEqualToArray:@[routedDismissID]] &&
               actionDelegate.overviewShowCalls == 1,
               @"the notification-center delegate immediately acknowledges a routed dismiss");

        NSString *routedOpenID = @"com.commcats.gdrivebackup.office.failure.900";
        [actionDelegate.testDefaults setDouble:900 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:routedOpenID forKey:activeIDKey];
        actionDelegate.removedNotificationIdentifiers = nil;
        BOOL openResponseCompleted = RouteBackupResponse(
            actionDelegate, @"GDT_OPEN_BACKUP_OVERVIEW", @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"900"},
            routedOpenID);
        Assert(openResponseCompleted &&
               [actionDelegate.testDefaults doubleForKey:dismissedKey] == 900 &&
               [actionDelegate.testDefaults objectForKey:activeAtKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeKindKey] == nil &&
               [actionDelegate.testDefaults objectForKey:activeIDKey] == nil &&
               [actionDelegate.removedNotificationIdentifiers containsObject:routedOpenID] &&
               actionDelegate.overviewShowCalls == 2 &&
               actionDelegate.overviewRefreshCalls == 2 &&
               actionDelegate.backupLaunchCalls == 0,
               @"the notification-center delegate routes Open through acknowledgement and overview navigation");

        NSString *defaultActionID =
            @"com.commcats.gdrivebackup.office.failure.950";
        [actionDelegate.testDefaults setDouble:950 forKey:activeAtKey];
        [actionDelegate.testDefaults setObject:@"failure" forKey:activeKindKey];
        [actionDelegate.testDefaults setObject:defaultActionID forKey:activeIDKey];
        actionDelegate.removedDeliveredNotificationIdentifiers = nil;
        actionDelegate.removedPendingNotificationIdentifiers = nil;
        BOOL defaultResponseCompleted = RouteBackupResponse(
            actionDelegate, UNNotificationDefaultActionIdentifier,
            @"GDT_BACKUP_ALERT",
            @{@"profileID": @"office", @"issueOriginTimestamp": @"950"},
            defaultActionID);
        BOOL defaultNavigationCompleted = WaitForCondition(^BOOL{
            return actionDelegate.overviewShowCalls == 3 &&
                actionDelegate.overviewRefreshCalls == 3;
        }, 1.0);
        Assert(defaultResponseCompleted && defaultNavigationCompleted &&
               [actionDelegate.testDefaults doubleForKey:dismissedKey] == 900 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 950 &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:defaultActionID] &&
               actionDelegate.removedDeliveredNotificationIdentifiers == nil &&
               actionDelegate.removedPendingNotificationIdentifiers == nil,
               @"the default click opens the overview without acknowledging the persistent issue");

        BOOL legacyOpenCompleted = RouteBackupResponse(
            actionDelegate, @"GDT_OPEN_BACKUP_OVERVIEW", @"GDT_BACKUP_ALERT",
            @{}, @"com.commcats.gdrivebackup.office.failure.300");
        BOOL legacyNavigationCompleted = WaitForCondition(^BOOL{
            return actionDelegate.overviewShowCalls == 4 &&
                actionDelegate.overviewRefreshCalls == 4;
        }, 1.0);
        Assert(legacyOpenCompleted && legacyNavigationCompleted &&
               [actionDelegate.testDefaults doubleForKey:dismissedKey] == 900 &&
               [actionDelegate.testDefaults doubleForKey:activeAtKey] == 950 &&
               [[actionDelegate.testDefaults stringForKey:activeIDKey]
                   isEqualToString:defaultActionID] &&
               actionDelegate.removedDeliveredNotificationIdentifiers == nil &&
               actionDelegate.removedPendingNotificationIdentifiers == nil,
               @"a legacy Open action keeps overview navigation while refusing untrusted acknowledgement metadata");

        BackupNotificationAuthorizationTestDelegate *authorizationDelegate =
            [[BackupNotificationAuthorizationTestDelegate alloc] init];
        authorizationDelegate.testDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:[suiteName stringByAppendingString:@".authorization"]];
        BackupNotificationAuthorizationCenter *authorizationCenter =
            [[BackupNotificationAuthorizationCenter alloc] init];
        authorizationCenter.settings = [[BackupNotificationAuthorizationSettings alloc] init];
        authorizationCenter.settings.authorizationStatus = UNAuthorizationStatusNotDetermined;
        authorizationDelegate.testNotificationCenter = authorizationCenter;
        NSDictionary<NSString *, NSString *> *undeterminedFailureDecision = @{
            @"identifier": @"com.commcats.gdrivebackup.authorization.failure.100",
            @"profileID": @"authorization",
            @"kind": @"failure",
            @"issueOriginTimestamp": @"100",
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": @"backupNotificationTargetUnavailable"
        };
        __block BOOL undeterminedFailureCompleted = NO;
        __block BOOL undeterminedFailureDelivered = YES;
        Method currentCenterMethod = class_getClassMethod(
            UNUserNotificationCenter.class, @selector(currentNotificationCenter));
        Method fakeCurrentCenterMethod = class_getClassMethod(
            UNUserNotificationCenter.class,
            @selector(gdt_notificationIntegrationCurrentCenter));
        IMP originalCurrentCenterImplementation = method_getImplementation(currentCenterMethod);
        GDTNotificationIntegrationCurrentCenter =
            (UNUserNotificationCenter *)(id)authorizationCenter;
        method_setImplementation(currentCenterMethod,
            method_getImplementation(fakeCurrentCenterMethod));
        @try {
            [authorizationDelegate deliverBackupNotificationDecision:
                undeterminedFailureDecision completion:^(BOOL delivered) {
                undeterminedFailureCompleted = YES;
                undeterminedFailureDelivered = delivered;
            }];
        } @finally {
            method_setImplementation(currentCenterMethod,
                originalCurrentCenterImplementation);
            GDTNotificationIntegrationCurrentCenter = nil;
        }
        Assert(undeterminedFailureCompleted && !undeterminedFailureDelivered &&
               authorizationCenter.authorizationRequests == 0 &&
               authorizationCenter.addRequestCalls == 0,
               @"failure delivery fails closed without prompting before explicit notification consent");

        authorizationCenter.authorizationRequests = 0;
        authorizationCenter.addRequestCalls = 0;
        NSDictionary<NSString *, NSString *> *undeterminedSuccessDecision = @{
            @"identifier": @"com.commcats.gdrivebackup.authorization.success.200",
            @"profileID": @"authorization",
            @"kind": @"success",
            @"eventTimestamp": @"200",
            @"titleKey": @"backupNotificationSuccessTitle",
            @"bodyKey": @"backupNotificationSuccessBody"
        };
        __block BOOL directUndeterminedSuccessCompleted = NO;
        __block BOOL directUndeterminedSuccessDelivered = YES;
        [authorizationDelegate deliverBackupSuccessNotificationDecision:
            undeterminedSuccessDecision capturedActiveIssueTimestamp:-1
            completion:^(BOOL delivered) {
            directUndeterminedSuccessCompleted = YES;
            directUndeterminedSuccessDelivered = delivered;
        }];
        Assert(directUndeterminedSuccessCompleted && !directUndeterminedSuccessDelivered &&
               authorizationCenter.authorizationRequests == 0 &&
               authorizationCenter.addRequestCalls == 0,
               @"success delivery fails closed without prompting before explicit notification consent");

        authorizationCenter.authorizationRequests = 0;
        authorizationCenter.addRequestCalls = 0;
        NSDictionary<NSString *, NSString *> *successOnlyNotificationConfig = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"authorization",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"0",
            @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"1"
        };
        SEL explicitAuthorizationSelector = NSSelectorFromString(
            @"requestBackupNotificationAuthorizationIfNeededForConfig:");
        BOOL exposesExplicitAuthorization = [authorizationDelegate respondsToSelector:
            explicitAuthorizationSelector];
        typedef void (*RequestAuthorizationMethod)(id, SEL, NSDictionary *);
        RequestAuthorizationMethod requestAuthorization = exposesExplicitAuthorization
            ? (RequestAuthorizationMethod)[authorizationDelegate
                methodForSelector:explicitAuthorizationSelector] : NULL;
        if (requestAuthorization) {
            [authorizationDelegate configureBackupNotificationsForConfig:
                successOnlyNotificationConfig];
        }
        Assert(exposesExplicitAuthorization && authorizationCenter.setCategoriesCalls == 1 &&
               authorizationCenter.authorizationRequests == 0,
               @"controller startup configures categories without prompting for notification permission");
        if (requestAuthorization) {
            requestAuthorization(authorizationDelegate, explicitAuthorizationSelector,
                successOnlyNotificationConfig);
        }
        BOOL successOptInRequestsAuthorization =
            authorizationCenter.authorizationRequests == 1;
        authorizationCenter.authorizationRequests = 0;
        NSDictionary<NSString *, NSString *> *failureOnlyNotificationConfig = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"authorization",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"1",
            @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"0"
        };
        if (requestAuthorization) {
            requestAuthorization(authorizationDelegate, explicitAuthorizationSelector,
                failureOnlyNotificationConfig);
        }
        BOOL failureOptInRequestsAuthorization =
            authorizationCenter.authorizationRequests == 1;
        authorizationCenter.authorizationRequests = 0;
        NSDictionary<NSString *, NSString *> *manualSuccessNotificationConfig = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"authorization",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"0",
            @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"1"
        };
        if (requestAuthorization) {
            requestAuthorization(authorizationDelegate, explicitAuthorizationSelector,
                manualSuccessNotificationConfig);
        }
        Assert(exposesExplicitAuthorization && successOptInRequestsAuthorization &&
               failureOptInRequestsAuthorization &&
               authorizationCenter.authorizationRequests == 0,
               @"an explicit setup save requests notification permission for either automatic preference");

        NSApplication *testApplication =
            GDTInitializeAccessoryTestApplication();
        Assert(testApplication.activationPolicy ==
                   NSApplicationActivationPolicyAccessory,
               @"the notification integration harness stays out of the Dock");
        NSStatusItem *retryStatusItem = [NSStatusBar.systemStatusBar
            statusItemWithLength:NSSquareStatusItemLength];
        actionDelegate.statusItem = retryStatusItem;
        SEL statusPresentationSelector =
            NSSelectorFromString(@"updateStatusItemPresentationForSnapshot:");
        if ([actionDelegate respondsToSelector:statusPresentationSelector]) {
            typedef void (*StatusPresentationMethod)(id, SEL, NSDictionary *);
            StatusPresentationMethod presentStatus =
                (StatusPresentationMethod)[actionDelegate
                    methodForSelector:statusPresentationSelector];
            presentStatus(actionDelegate, statusPresentationSelector,
                @{@"alertStatus": @"retry-running", @"lastRun": @"stale failure"});
        }
        NSImage *expectedRetrySymbol = [NSImage
            imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"
              accessibilityDescription:nil];
        Assert(retryStatusItem.button.image.template &&
               [retryStatusItem.button.image.TIFFRepresentation
                   isEqualToData:expectedRetrySymbol.TIFFRepresentation] &&
               [retryStatusItem.button.accessibilityLabel
                   containsString:T(@"en", @"automaticRetryRunning")],
               @"retry-running uses a non-red running symbol and a localized spoken status");
        [NSStatusBar.systemStatusBar removeStatusItem:retryStatusItem];
        actionDelegate.statusItem = nil;

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

        NSMutableDictionary *fractionalSuccessConfig = [enabledConfig mutableCopy];
        fractionalSuccessConfig[@"GDRIVE_BACKUP_PROFILE_ID"] = @"fractional-success";
        fractionalSuccessConfig[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] = @"1";
        NSDictionary *fractionalSuccessWindow = [delegate
            notificationMonitoringConfigForConfig:fractionalSuccessConfig
                                               now:[NSDate dateWithTimeIntervalSince1970:200.4]];
        Assert([fractionalSuccessWindow[
                   @"GDRIVE_BACKUP_SUCCESS_NOTIFICATION_MONITOR_STARTED_AT"]
                   isEqualToString:@"201"],
               @"sub-second routine-success opt-in rounds up so an already finished run stays ineligible");

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

        summaryText = [NSString stringWithFormat:
            @"protocol=1\nstatus=success\npid=125\nstarted_at=%.0f\nfinished_at=%.0f\nlast_success_at=%.0f\nexit_code=0\ntrigger=schedule\n",
            current - 120, current - 60, current - 60];
        [summaryText writeToFile:summaryPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [refreshDelegate.testDefaults setDouble:current - 180
            forKey:@"GDTBackupNotification.office.activeIssueAt"];
        refreshDelegate.capturedSuccessDecision = nil;
        refreshDelegate.clearedFailuresBeforeSuccessProcessing = NO;
        [refreshDelegate refreshOverviewStatus:nil];
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!refreshDelegate.capturedSuccessDecision &&
               [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert([refreshDelegate.capturedSuccessDecision[@"kind"] isEqualToString:@"success"] &&
               [refreshDelegate.capturedSuccessDecision[@"eventTimestamp"]
                   isEqualToString:[NSString stringWithFormat:@"%.0f", current - 60]] &&
               refreshDelegate.clearedFailuresBeforeSuccessProcessing,
               @"status refresh captures the active issue, clears old failures, then processes success");
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
