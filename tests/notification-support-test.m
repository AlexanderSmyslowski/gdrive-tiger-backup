#import <Foundation/Foundation.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSDate *Date(NSCalendar *calendar, NSInteger day, NSInteger hour, NSInteger minute) {
    NSDateComponents *parts = [[NSDateComponents alloc] init];
    parts.year = 2026;
    parts.month = 7;
    parts.day = day;
    parts.hour = hour;
    parts.minute = minute;
    return [calendar dateFromComponents:parts];
}

static NSDictionary<NSString *, NSString *> *Decision(
    Class policyClass,
    NSDictionary<NSString *, NSString *> *config,
    NSDictionary<NSString *, NSString *> *summary,
    NSString *status,
    NSDate *now,
    NSCalendar *calendar) {
    SEL selector = NSSelectorFromString(@"decisionForConfig:summary:status:now:calendar:");
    if (!policyClass || ![policyClass respondsToSelector:selector]) return nil;
    typedef NSDictionary<NSString *, NSString *> *(*DecisionMethod)(
        id, SEL, NSDictionary *, NSDictionary *, NSString *, NSDate *, NSCalendar *);
    DecisionMethod method = (DecisionMethod)[policyClass methodForSelector:selector];
    return method(policyClass, selector, config, summary, status, now, calendar);
}

static NSArray<NSString *> *ProfileFailureIdentifiers(
    Class policyClass,
    NSString *profileID,
    NSArray<NSString *> *candidates) {
    SEL selector = NSSelectorFromString(
        @"failureNotificationIdentifiersForProfileID:candidateIdentifiers:");
    if (!policyClass || ![policyClass respondsToSelector:selector]) return nil;
    typedef NSArray<NSString *> *(*FilterMethod)(id, SEL, NSString *, NSArray<NSString *> *);
    FilterMethod method = (FilterMethod)[policyClass methodForSelector:selector];
    return method(policyClass, selector, profileID, candidates);
}

int main(void) {
    @autoreleasepool {
        Class policyClass = NSClassFromString(@"GDTBackupNotificationPolicy");
        Assert(policyClass != Nil,
               @"backup notification policy is available to the controller");

        NSCalendar *calendar = [[NSCalendar alloc]
            initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:2 * 60 * 60];
        NSDate *monitorStart = Date(calendar, 20, 12, 0);
        NSDictionary<NSString *, NSString *> *daily = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"office",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"1",
            @"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT":
                [NSString stringWithFormat:@"%.0f", monitorStart.timeIntervalSince1970]
        };

        NSDate *failureStart = Date(calendar, 21, 20, 0);
        NSDate *failureEnd = Date(calendar, 21, 20, 25);
        NSDictionary<NSString *, NSString *> *failedSummary = @{
            @"protocol": @"1",
            @"status": @"failure",
            @"started_at": [NSString stringWithFormat:@"%.0f", failureStart.timeIntervalSince1970],
            @"finished_at": [NSString stringWithFormat:@"%.0f", failureEnd.timeIntervalSince1970],
            @"exit_code": @"1",
            @"trigger": @"schedule",
            @"reason": @"destination_permission_denied"
        };
        NSDictionary<NSString *, NSString *> *failure = Decision(
            policyClass, daily, failedSummary, @"failure", Date(calendar, 21, 20, 26), calendar);
        Assert([failure[@"kind"] isEqualToString:@"failure"] &&
               [failure[@"identifier"] containsString:@"office"] &&
               [failure[@"identifier"] containsString:failedSummary[@"started_at"]] &&
               [failure[@"bodyKey"] isEqualToString:@"failedPermissionHint"],
               @"a fresh scheduled failure creates one stable, reason-specific alert");

        NSMutableDictionary<NSString *, NSString *> *nasNotReady = [failedSummary mutableCopy];
        nasNotReady[@"reason"] = @"nas_mount_not_ready";
        NSDictionary<NSString *, NSString *> *retryPlanned = Decision(
            policyClass, daily, nasNotReady, @"failure", Date(calendar, 21, 20, 26), calendar);
        Assert([retryPlanned[@"kind"] isEqualToString:@"failure"] &&
               [retryPlanned[@"bodyKey"] isEqualToString:@"backupNotificationNASRetryBody"],
               @"a transient NAS readiness failure announces the later automatic retry");

        NSMutableDictionary<NSString *, NSString *> *destinationUnreadable =
            [failedSummary mutableCopy];
        destinationUnreadable[@"reason"] = @"destination_unreadable";
        NSDictionary<NSString *, NSString *> *readRetryPlanned = Decision(
            policyClass, daily, destinationUnreadable, @"failure",
            Date(calendar, 21, 20, 26), calendar);
        Assert([readRetryPlanned[@"kind"] isEqualToString:@"failure"] &&
               [readRetryPlanned[@"bodyKey"]
                   isEqualToString:@"backupNotificationNASRetryBody"],
               @"a transient NAS read failure announces the later automatic retry");

        NSMutableDictionary<NSString *, NSString *> *retryFailed = [nasNotReady mutableCopy];
        retryFailed[@"trigger"] = @"schedule-retry";
        retryFailed[@"started_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 20, 56).timeIntervalSince1970];
        retryFailed[@"finished_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 21, 1).timeIntervalSince1970];
        NSDictionary<NSString *, NSString *> *finalFailure = Decision(
            policyClass, daily, retryFailed, @"failure", Date(calendar, 21, 21, 2), calendar);
        Assert([finalFailure[@"kind"] isEqualToString:@"failure"] &&
               [finalFailure[@"identifier"] containsString:retryFailed[@"started_at"]] &&
               [finalFailure[@"bodyKey"] isEqualToString:@"backupNotificationRetryFailureBody"],
               @"a failed automatic retry creates one distinct final failure alert");

        NSMutableDictionary<NSString *, NSString *> *cancelledSummary = [failedSummary mutableCopy];
        cancelledSummary[@"status"] = @"cancelled";
        cancelledSummary[@"exit_code"] = @"143";
        Assert([Decision(policyClass, daily, cancelledSummary, @"cancelled",
                         Date(calendar, 21, 20, 26), calendar)[@"kind"]
                    isEqualToString:@"failure"],
               @"a cancelled unattended run is reported because no backup completed");

        NSMutableDictionary<NSString *, NSString *> *disabled = [daily mutableCopy];
        disabled[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] = @"0";
        Assert(Decision(policyClass, disabled, failedSummary, @"failure",
                        Date(calendar, 21, 20, 26), calendar) == nil,
               @"the setup opt-out disables all backup notifications");

        NSMutableDictionary<NSString *, NSString *> *defaultEnabled = [daily mutableCopy];
        [defaultEnabled removeObjectForKey:@"GDRIVE_BACKUP_NOTIFY_FAILURES"];
        Assert([Decision(policyClass, defaultEnabled, failedSummary, @"failure",
                         Date(calendar, 21, 20, 26), calendar)[@"kind"]
                    isEqualToString:@"failure"],
               @"existing automatic profiles receive failure alerts by default");

        NSMutableDictionary<NSString *, NSString *> *paused = [daily mutableCopy];
        paused[@"GDRIVE_BACKUP_PAUSED"] = @"1";
        Assert(Decision(policyClass, paused, @{}, @"unknown",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"paused automatic backups never raise a missed-run warning");

        NSDictionary<NSString *, NSString *> *missed = Decision(
            policyClass, daily, @{}, @"unknown", Date(calendar, 21, 21, 5), calendar);
        Assert([missed[@"kind"] isEqualToString:@"missed"] &&
               [missed[@"identifier"] containsString:@"office"] &&
               [missed[@"bodyKey"] isEqualToString:@"backupNotificationMissedBody"],
               @"the daily watchdog reports a run still missing after 21:00");

        NSDictionary<NSString *, NSString *> *successfulSummary = @{
            @"protocol": @"1",
            @"status": @"success",
            @"started_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 5).timeIntervalSince1970],
            @"finished_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 50).timeIntervalSince1970],
            @"exit_code": @"0",
            @"trigger": @"manual"
        };
        Assert(Decision(policyClass, daily, successfulSummary, @"success",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"a successful manual backup after the due time satisfies the daily watchdog");

        NSDictionary<NSString *, NSString *> *laterManualFailure = @{
            @"protocol": @"1",
            @"status": @"failure",
            @"started_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 45).timeIntervalSince1970],
            @"finished_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 50).timeIntervalSince1970],
            @"last_success_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 30).timeIntervalSince1970],
            @"exit_code": @"1",
            @"trigger": @"manual"
        };
        Assert(Decision(policyClass, daily, laterManualFailure, @"failure",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"a later manual failure cannot hide the successful daily run");

        NSDictionary<NSString *, NSString *> *runningSummary = @{
            @"protocol": @"1",
            @"status": @"running",
            @"started_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 21, 20, 40).timeIntervalSince1970],
            @"trigger": @"manual"
        };
        Assert(Decision(policyClass, daily, runningSummary, @"running",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"the watchdog waits while any backup is still running");

        Assert([Decision(policyClass, daily, failedSummary, @"failure",
                         Date(calendar, 21, 21, 5), calendar)[@"kind"]
                    isEqualToString:@"failure"],
               @"a failed scheduled run is not mislabeled as a missed run");

        NSDictionary<NSString *, NSString *> *oldFailure = @{
            @"protocol": @"1",
            @"status": @"failure",
            @"started_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 20, 20, 0).timeIntervalSince1970],
            @"finished_at": [NSString stringWithFormat:@"%.0f",
                Date(calendar, 20, 20, 25).timeIntervalSince1970],
            @"exit_code": @"1",
            @"trigger": @"schedule"
        };
        Assert([Decision(policyClass, daily, oldFailure, @"failure",
                         Date(calendar, 21, 21, 5), calendar)[@"kind"]
                    isEqualToString:@"missed"],
               @"yesterday's failure does not mask today's missing run");

        NSMutableDictionary<NSString *, NSString *> *newlyEnabled = [daily mutableCopy];
        newlyEnabled[@"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT"] =
            [NSString stringWithFormat:@"%.0f", Date(calendar, 21, 20, 30).timeIntervalSince1970];
        Assert(Decision(policyClass, newlyEnabled, @{}, @"unknown",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"a newly enabled watchdog does not warn about a due time before it existed");

        NSMutableDictionary<NSString *, NSString *> *manual = [daily mutableCopy];
        manual[@"GDRIVE_BACKUP_SCHEDULE"] = @"manual";
        Assert(Decision(policyClass, manual, failedSummary, @"failure",
                        Date(calendar, 21, 21, 5), calendar) == nil,
               @"manual-only profiles do not produce automatic-backup alerts");

        NSArray<NSString *> *profileFailures = ProfileFailureIdentifiers(
            policyClass, @"office", @[
                @"com.commcats.gdrivebackup.office.failure.100",
                @"com.commcats.gdrivebackup.office.missed.200",
                @"com.commcats.gdrivebackup.archive.failure.300",
                @"com.commcats.gdrivebackup.office.failure.not-a-time",
                @"foreign.office.failure.400"
            ]);
        Assert([profileFailures isEqualToArray:@[
                   @"com.commcats.gdrivebackup.office.failure.100",
                   @"com.commcats.gdrivebackup.office.missed.200"
               ]],
               @"notification cleanup accepts only exact safe failure IDs for one profile");
    }

    if (failures > 0) {
        printf("%d notification support test(s) failed.\n", failures);
        return 1;
    }
    printf("All notification support tests passed.\n");
    return 0;
}
