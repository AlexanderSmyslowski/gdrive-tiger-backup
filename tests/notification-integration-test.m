#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface AppDelegate (NotificationIntegrationTesting)
- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (NSUserDefaults *)backupNotificationDefaultsStore;
- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion;
- (NSString *)backupAlertStatusForConfig:(NSDictionary<NSString *, NSString *> *)config
                                  summary:(NSDictionary<NSString *, NSString *> *)summary
                                rawStatus:(NSString *)rawStatus
                                 decision:(NSDictionary<NSString *, NSString *> *)decision;
@end

@interface NotificationTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic) NSInteger deliveryCalls;
@property(nonatomic) BOOL deliverySucceeds;
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

@end

@interface NotificationRefreshDelegate : NotificationTestDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *capturedDecision;
@end

@implementation NotificationRefreshDelegate

- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.capturedDecision = decision;
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
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": @"failedHint"
        };
        Process(delegate, first);
        Process(delegate, first);
        Assert(delegate.deliveryCalls == 1,
               @"the same profile and backup run produces only one notification");

        NSMutableDictionary<NSString *, NSString *> *nextRun = [first mutableCopy];
        nextRun[@"identifier"] = @"com.commcats.gdrivebackup.office.failure.200";
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
        NSString *clearedMissed = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{@"finished_at": @"150"},
            @"success", nil) : nil;
        Assert([missedStatus isEqualToString:@"missed"] &&
               [stillMissedWhileRunning isEqualToString:@"missed"] &&
               [clearedMissed isEqualToString:@"success"],
               @"a missed-run warning stays active until a later successful backup");

        NSDictionary *failureDecision = @{
            @"identifier": @"failure.200", @"profileID": @"office",
            @"kind": @"failure", @"issueTimestamp": @"200"
        };
        NSString *failureStatus = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{}, @"failure", failureDecision) : nil;
        NSString *oldSuccessDoesNotClear = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{@"finished_at": @"199"},
            @"success", nil) : nil;
        NSString *newSuccessClears = alertStatus ? alertStatus(
            delegate, alertStatusSelector, profileConfig, @{@"finished_at": @"250"},
            @"success", nil) : nil;
        Assert([failureStatus isEqualToString:@"failure"] &&
               [oldSuccessDoesNotClear isEqualToString:@"failure"] &&
               [newSuccessClears isEqualToString:@"success"],
               @"only a success newer than the reported failure clears the red status latch");

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
