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
@end

@interface NotificationTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic) NSInteger deliveryCalls;
@property(nonatomic) BOOL deliverySucceeds;
@property(nonatomic, copy) NSArray<NSString *> *removedNotificationIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *extraDeliveredNotificationIdentifiers;
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
        Assert(content.sound != nil &&
               [content.categoryIdentifier isEqualToString:@"GDT_BACKUP_ALERT"],
               @"automatic backup alerts remain audible without opening a window");

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
    }

    if (failures > 0) {
        printf("%d notification integration test(s) failed.\n", failures);
        return 1;
    }
    printf("All notification integration tests passed.\n");
    return 0;
}
