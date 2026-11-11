#import <Cocoa/Cocoa.h>

#import "TestApplicationSupport.h"
#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface AppDelegate (RetryCountdownTesting)
- (BOOL)presentRetryCountdownForDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (void)updateRetryCountdownForConfig:(NSDictionary<NSString *, NSString *> *)config
                            summary:(NSDictionary<NSString *, NSString *> *)summary
                             status:(NSString *)status now:(NSDate *)now;
@end

@interface CountdownTestDelegate : AppDelegate
@property(nonatomic, strong) NSUserDefaults *testDefaults;
@property(nonatomic) NSInteger presentations;
@property(nonatomic) NSInteger nativeDeliveries;
@property(nonatomic) NSInteger retryLaunches;
@property(nonatomic) BOOL retryLockAvailable;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testRetryDecision;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testRetrySummary;
@property(nonatomic, copy) NSArray<NSString *> *removedIdentifiers;
@end
@implementation CountdownTestDelegate
- (NSUserDefaults *)backupNotificationDefaultsStore { return self.testDefaults; }
- (BOOL)automaticRetryLockIsAvailable { return self.retryLockAvailable; }
- (NSDictionary<NSString *, NSString *> *)currentAutomaticRetryDecision {
    return self.testRetryDecision;
}
- (NSString *)automaticRetrySummaryPathForProfileID:(NSString *)profileID {
    return [@"summary://" stringByAppendingString:profileID];
}
- (NSDictionary<NSString *, NSString *> *)automaticRetrySummaryAtPath:(NSString *)path {
    (void)path;
    return self.testRetrySummary;
}
- (NSDictionary<NSString *, NSString *> *)automaticRetryDecisionForSummary:
    (NSDictionary<NSString *, NSString *> *)summary summaryPath:(NSString *)summaryPath
    profileID:(NSString *)profileID {
    (void)summary;
    (void)summaryPath;
    (void)profileID;
    return self.testRetryDecision;
}
- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision
    completion:(void (^)(NSInteger))completion {
    (void)decision;
    (void)completion;
    self.retryLaunches++;
    return YES;
}
- (BOOL)presentRetryCountdownForDecision:(NSDictionary<NSString *, NSString *> *)decision {
    self.presentations++;
    return [super presentRetryCountdownForDecision:decision];
}
- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                              completion:(void (^)(BOOL))completion {
    (void)decision;
    self.nativeDeliveries++;
    completion(YES);
}
- (void)removeExactBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                   forProfileID:(NSString *)profileID {
    (void)profileID;
    self.removedIdentifiers = identifiers;
}
@end

static int failures;
static void Assert(BOOL condition, NSString *name) {
    printf("%s - %s\n", condition ? "ok" : "not ok", name.UTF8String);
    if (!condition) failures++;
}

int main(void) {
    @autoreleasepool {
        GDTInitializeAccessoryTestApplication();
        NSDictionary *config = @{@"GDRIVE_BACKUP_PROFILE_ID": @"countdown-test",
            @"GDRIVE_BACKUP_TARGET": @"nas", @"GDRIVE_BACKUP_SCHEDULE": @"daily"};
        NSDictionary *summary = @{@"started_at": @"1000", @"finished_at": @"1040",
            @"trigger": @"schedule", @"reason": @"nas_mount_not_ready"};
        NSCalendar *calendar = NSCalendar.currentCalendar;
        NSDate *now = [NSDate dateWithTimeIntervalSince1970:1040];
        NSDictionary *decision = [GDTBackupNotificationPolicy decisionForConfig:config
            summary:summary status:@"failure" now:now calendar:calendar];
        Assert([decision[@"retryAt"] isEqualToString:@"2840"],
               @"retry countdown deadline is anchored to the failed run, not delivery time");
        NSDictionary *late = [GDTBackupNotificationPolicy decisionForConfig:config
            summary:summary status:@"failure" now:[now dateByAddingTimeInterval:1500] calendar:calendar];
        Assert([late[@"retryAt"] isEqualToString:@"2840"],
               @"late observation does not restart the thirty-minute wait");
        Assert([GDTAutomaticRetryPolicy decisionForConfig:config summary:summary status:@"failure"
            now:[NSDate dateWithTimeIntervalSince1970:2839]] == nil &&
            [GDTAutomaticRetryPolicy decisionForConfig:config summary:summary status:@"failure"
            now:[NSDate dateWithTimeIntervalSince1970:2840]] != nil,
               @"displaying a countdown never launches the retry early");
        for (NSDictionary *overrides in @[@{@"GDRIVE_BACKUP_TARGET": @"apfs"},
                @{@"GDRIVE_BACKUP_PAUSED": @"1"}, @{@"GDRIVE_BACKUP_SCHEDULE": @"manual"},
                @{@"GDRIVE_BACKUP_NOTIFY_FAILURES": @"0"}]) {
            NSMutableDictionary *ineligible = [config mutableCopy];
            [ineligible addEntriesFromDictionary:overrides];
            NSDictionary *result = [GDTBackupNotificationPolicy decisionForConfig:ineligible
                summary:summary status:@"failure" now:now calendar:calendar];
            Assert(result[@"retryAt"] == nil, @"ineligible configuration cannot promise a countdown");
        }
        NSMutableDictionary *invalid = [summary mutableCopy];
        invalid[@"finished_at"] = @"bad";
        Assert([GDTBackupNotificationPolicy decisionForConfig:config summary:invalid status:@"failure"
            now:now calendar:calendar][@"retryAt"] == nil,
               @"invalid completion time never fabricates a retry deadline");
        Assert([GDTBackupNotificationPolicy decisionForConfig:config summary:summary status:@"cancelled"
            now:now calendar:calendar][@"retryAt"] == nil,
               @"cancelled runs cannot promise a retry");

        Class panelClass = NSClassFromString(@"GDTRetryCountdownPanel");
        Assert(panelClass != Nil, @"retry countdown has its own native app panel");
        if (panelClass && decision[@"retryAt"]) {
            NSString *suite = [@"com.commcats.gdrivebackup.countdown-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
            CountdownTestDelegate *delegate = [[CountdownTestDelegate alloc] init];
            delegate.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
            delegate.language = @"de";
            // A previous app version may already have delivered this run's static alert.
            [delegate.testDefaults setObject:decision[@"identifier"]
                forKey:@"GDTBackupNotification.countdown-test.lastDeliveredIdentifier"];
            [delegate processBackupNotificationDecision:decision];
            [delegate processBackupNotificationDecision:decision];
            Assert(delegate.presentations == 1 && delegate.nativeDeliveries == 0,
                   @"eligible retry replaces the system alert with exactly one panel");
            Assert([delegate.removedIdentifiers containsObject:decision[@"identifier"]],
                   @"presenting the panel removes the old static notification for that run");
            id panel = [delegate valueForKey:@"retryCountdownPanel"];
            Assert(([panel styleMask] & NSWindowStyleMaskNonactivatingPanel) != 0 &&
                   ![panel hidesOnDeactivate] &&
                   ([panel collectionBehavior] & NSWindowCollectionBehaviorFullScreenNone) != 0,
                   @"passive countdown stays visible without taking focus or entering fullscreen spaces");
            SEL tick = NSSelectorFromString(@"updateForDate:");
            typedef void (*Tick)(id, SEL, NSDate *);
            Tick update = (Tick)[panel methodForSelector:tick];
            for (NSArray *example in @[@[@1040, @"30:00"], @[@1041, @"29:59"],
                                       @[@2781, @"00:59"], @[@2839.5, @"00:01"]]) {
                update(panel, tick, [NSDate dateWithTimeIntervalSince1970:[example[0] doubleValue]]);
                Assert([[[panel valueForKey:@"countdownLabel"] stringValue] isEqualToString:example[1]],
                       @"countdown derives seconds from the absolute deadline, including wake-up jumps");
            }
            update(panel, tick, [NSDate dateWithTimeIntervalSince1970:3000]);
            Assert([[[panel valueForKey:@"countdownLabel"] stringValue]
                isEqualToString:T(@"de", @"retryCountdownDue")],
                   @"zero says the retry is due instead of claiming it has started");
            delegate.testRetrySummary = summary;
            delegate.testRetryDecision = [GDTAutomaticRetryPolicy decisionForConfig:config
                summary:summary status:@"failure" now:[NSDate dateWithTimeIntervalSince1970:3000]];
            [delegate processAutomaticRetryDecision:delegate.testRetryDecision];
            [delegate updateRetryCountdownForConfig:config summary:summary status:@"failure"
                now:[NSDate dateWithTimeIntervalSince1970:3000]];
            Assert(delegate.retryLaunches == 0 && [panel isVisible] &&
                [[[panel valueForKey:@"countdownLabel"] stringValue]
                    isEqualToString:T(@"de", @"retryCountdownDue")],
                @"an occupied backup lock keeps the overdue panel truthful without consuming the retry");
            delegate.retryLockAvailable = YES;
            [delegate processAutomaticRetryDecision:delegate.testRetryDecision];
            [delegate processAutomaticRetryDecision:delegate.testRetryDecision];
            Assert(delegate.retryLaunches == 1 &&
                [[[panel valueForKey:@"countdownLabel"] stringValue]
                    isEqualToString:T(@"de", @"retryCountdownDue")],
                @"a released lock permits one launch but the panel waits for a running summary");
            NSMutableDictionary *running = [summary mutableCopy];
            running[@"trigger"] = @"schedule-retry";
            running[@"retry_attempt"] = @"1";
            running[@"started_at"] = @"2840";
            running[@"retry_origin_started_at"] = @"1000";
            [delegate updateRetryCountdownForConfig:config summary:running status:@"running"
                now:[NSDate dateWithTimeIntervalSince1970:2841]];
            Assert([[[panel valueForKey:@"countdownLabel"] stringValue]
                isEqualToString:T(@"de", @"retryCountdownRunning")],
                   @"only a matching running retry replaces the countdown with running state");
            [panel close];
            [delegate processBackupNotificationDecision:decision];
            Assert(delegate.presentations == 1 && ![panel isVisible] &&
                   ![[panel valueForKey:@"countdownTimer"] isValid],
                   @"closing dismisses the panel and timer without recreating it on the next poll");
            Assert([delegate.testDefaults stringForKey:
                @"GDTBackupNotification.countdown-test.lastAutomaticRetryIdentifier"] == nil,
                   @"closing the countdown does not consume or cancel the scheduled attempt");
            [delegate updateRetryCountdownForConfig:config summary:running status:@"success"
                now:[NSDate dateWithTimeIntervalSince1970:2842]];
            Assert([delegate valueForKey:@"retryCountdownPanel"] == nil,
                   @"terminal result retires the countdown panel");
            CountdownTestDelegate *restarted = [[CountdownTestDelegate alloc] init];
            restarted.testDefaults = delegate.testDefaults;
            [restarted processBackupNotificationDecision:decision];
            Assert(restarted.presentations == 0 && restarted.nativeDeliveries == 0,
                   @"restarting the controller does not redisplay a dismissed countdown");
            [delegate.testDefaults removeObjectForKey:
                @"GDTBackupNotification.countdown-test.lastPresentedRetryCountdownIdentifier"];
            [delegate.testDefaults setObject:@"countdown-test.automatic-retry.1000" forKey:
                @"GDTBackupNotification.countdown-test.lastAutomaticRetryIdentifier"];
            [restarted processBackupNotificationDecision:decision];
            Assert(restarted.presentations == 0,
                   @"an already consumed retry cannot resurrect a stale countdown");
            [delegate.testDefaults removeObjectForKey:
                @"GDTBackupNotification.countdown-test.lastAutomaticRetryIdentifier"];

            NSArray *clearCases = @[
                @[@{@"GDRIVE_BACKUP_PAUSED": @"1"}, @{}, @"failure", @1041],
                @[@{@"GDRIVE_BACKUP_NOTIFY_FAILURES": @"0"}, @{}, @"failure", @1041],
                @[@{@"GDRIVE_BACKUP_PROFILE_ID": @"other-profile"}, @{}, @"failure", @1041],
                @[@{@"GDRIVE_BACKUP_TARGET": @"apfs"}, @{}, @"failure", @1041],
                @[@{@"GDRIVE_BACKUP_SCHEDULE": @"hourly"}, @{}, @"failure", @1041],
                @[@{}, @{}, @"failure", @87441],
                @[@{}, @{}, @"cancelled", @1041],
                @[@{}, @{}, @"interrupted", @1041],
                @[@{}, @{@"started_at": @"2000", @"finished_at": @"2040"}, @"failure", @2041],
                @[@{}, @{@"started_at": @"2000", @"trigger": @"manual"}, @"running", @2041],
                @[@{}, @{@"started_at": @"2840", @"trigger": @"schedule-retry",
                         @"retry_origin_started_at": @"999"}, @"running", @2841]
            ];
            for (NSArray *example in clearCases) {
                [delegate presentRetryCountdownForDecision:decision];
                id activePanel = [delegate valueForKey:@"retryCountdownPanel"];
                NSMutableDictionary *changedConfig = [config mutableCopy];
                [changedConfig addEntriesFromDictionary:example[0]];
                NSMutableDictionary *changedSummary = [summary mutableCopy];
                [changedSummary addEntriesFromDictionary:example[1]];
                [delegate updateRetryCountdownForConfig:changedConfig summary:changedSummary
                    status:example[2] now:[NSDate dateWithTimeIntervalSince1970:[example[3] doubleValue]]];
                Assert([delegate valueForKey:@"retryCountdownPanel"] == nil &&
                       ![activePanel isVisible] && ![[activePanel valueForKey:@"countdownTimer"] isValid],
                       @"changed eligibility, expiry, and superseding runs retire the panel and its timer");
            }
            NSMutableDictionary *newRun = [summary mutableCopy];
            newRun[@"started_at"] = @"4000";
            newRun[@"finished_at"] = @"4040";
            NSDictionary *newDecision = [GDTBackupNotificationPolicy decisionForConfig:config
                summary:newRun status:@"failure" now:[NSDate dateWithTimeIntervalSince1970:4041]
                calendar:calendar];
            NSInteger beforeNewRun = delegate.presentations;
            [delegate processBackupNotificationDecision:newDecision];
            Assert(delegate.presentations == beforeNewRun + 1,
                   @"a new failed run receives its own countdown after an earlier dismissal");
            [[delegate valueForKey:@"retryCountdownPanel"] close];
            NSDictionary *runningSummary = @{@"started_at": @"5840", @"status": @"running",
                @"trigger": @"schedule-retry", @"retry_attempt": @"1",
                @"retry_origin_started_at": @"4000"};
            NSDictionary *runningDecision = [GDTBackupNotificationPolicy decisionForConfig:config
                summary:runningSummary status:@"running" now:[NSDate dateWithTimeIntervalSince1970:5841]
                calendar:calendar];
            [delegate processBackupNotificationDecision:runningDecision];
            Assert([runningDecision[@"kind"] isEqualToString:@"retry-running"] &&
                   delegate.nativeDeliveries == 1,
                   @"the observed running retry retains the newer notification revision pipeline");
            NSInteger runningPresentations = delegate.presentations;
            [delegate.testDefaults removeObjectForKey:
                @"GDTBackupNotification.countdown-test.lastPresentedRetryCountdownIdentifier"];
            [delegate processBackupNotificationDecision:newDecision];
            Assert(delegate.presentations == runningPresentations && delegate.nativeDeliveries == 1,
                   @"an accepted running watermark prevents a stale countdown from reopening");
            NSMutableDictionary *finalSummary = [newRun mutableCopy];
            finalSummary[@"trigger"] = @"schedule-retry";
            finalSummary[@"retry_attempt"] = @"1";
            finalSummary[@"status"] = @"failure";
            finalSummary[@"retry_origin_started_at"] = @"4000";
            finalSummary[@"started_at"] = @"5840";
            finalSummary[@"finished_at"] = @"5880";
            NSDictionary *finalDecision = [GDTBackupNotificationPolicy decisionForConfig:config
                summary:finalSummary status:@"failure" now:[NSDate dateWithTimeIntervalSince1970:5881]
                calendar:calendar];
            [delegate processBackupNotificationDecision:finalDecision];
            Assert(delegate.nativeDeliveries == 2,
                   @"the final failed retry still uses the existing system alert");
            NSInteger acceptedPresentations = delegate.presentations;
            [delegate.testDefaults removeObjectForKey:
                @"GDTBackupNotification.countdown-test.lastPresentedRetryCountdownIdentifier"];
            [delegate processBackupNotificationDecision:newDecision];
            [delegate processBackupNotificationDecision:runningDecision];
            Assert(delegate.presentations == acceptedPresentations && delegate.nativeDeliveries == 2,
                   @"a stale countdown or running update cannot regress an accepted terminal retry result");
            for (NSString *language in SupportedLanguageCodes()) {
                for (NSString *key in @[@"retryCountdownDetail", @"retryCountdownDue",
                        @"retryCountdownDueDetail", @"retryCountdownRunning", @"retryCountdownRunningDetail",
                        @"retryCountdownAccessible", @"retryCountdownCloseHint", @"retryCountdownClose"]) {
                    Assert(![T(language, key) isEqualToString:key] && T(language, key).length > 0,
                           @"countdown copy is available in every supported language");
                }
                id localizedPanel = [[panelClass alloc]
                    initWithRetryDate:[NSDate dateWithTimeIntervalSinceNow:1800] language:language];
                [localizedPanel orderFront:nil];
                NSView *content = [localizedPanel contentView];
                [content layoutSubtreeIfNeeded];
                NSStackView *stack = content.subviews.firstObject;
                BOOL fits = YES;
                for (NSView *item in stack.arrangedSubviews) {
                    NSRect rect = [item convertRect:item.bounds toView:content];
                    fits = fits && NSContainsRect(content.bounds, rect);
                    if ([item isKindOfClass:NSTextField.class]) {
                        NSTextField *label = (NSTextField *)item;
                        NSSize needed = [label.cell cellSizeForBounds:NSMakeRect(0, 0, label.frame.size.width, 1000)];
                        fits = fits && needed.height <= label.frame.size.height + 1;
                    }
                }
                Assert(fits, @"native countdown labels fit without clipping in every language");
                [localizedPanel close];
            }
            [delegate.testDefaults removePersistentDomainForName:suite];
        }
        printf("%d retry countdown test(s) failed.\n", failures);
        return failures ? 1 : 0;
    }
}
