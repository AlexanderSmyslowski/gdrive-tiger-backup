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
               [failure[@"issueTimestamp"] isEqualToString:failedSummary[@"finished_at"]] &&
               [failure[@"issueOriginTimestamp"] isEqualToString:failedSummary[@"started_at"]] &&
               [failure[@"bodyKey"] isEqualToString:@"failedPermissionHint"],
               @"a fresh scheduled failure creates one stable, reason-specific alert");

        NSMutableDictionary<NSString *, NSString *> *nasNotReady = [failedSummary mutableCopy];
        nasNotReady[@"reason"] = @"nas_mount_not_ready";
        NSDictionary<NSString *, NSString *> *retryPlanned = Decision(
            policyClass, daily, nasNotReady, @"failure", Date(calendar, 21, 20, 26), calendar);
        Assert([retryPlanned[@"kind"] isEqualToString:@"failure"] &&
               [retryPlanned[@"issueOriginTimestamp"]
                   isEqualToString:failedSummary[@"started_at"]] &&
               [retryPlanned[@"bodyKey"] isEqualToString:@"backupNotificationNASRetryBody"],
               @"a transient NAS readiness failure announces the later automatic retry");

        NSMutableDictionary *retryRunningSummary = [nasNotReady mutableCopy];
        retryRunningSummary[@"status"] = @"running";
        retryRunningSummary[@"trigger"] = @"schedule-retry";
        retryRunningSummary[@"retry_origin_started_at"] = failedSummary[@"started_at"];
        retryRunningSummary[@"retry_attempt"] = @"1";
        retryRunningSummary[@"started_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 20, 56).timeIntervalSince1970];
        [retryRunningSummary removeObjectForKey:@"finished_at"];
        [retryRunningSummary removeObjectForKey:@"exit_code"];
        NSDictionary *retryRunning = Decision(
            policyClass, daily, retryRunningSummary, @"running",
            Date(calendar, 21, 20, 57), calendar);
        Assert([retryRunning[@"kind"] isEqualToString:@"retry-running"] &&
               [retryRunning[@"identifier"] isEqualToString:retryPlanned[@"identifier"]] &&
               [retryRunning[@"revision"] hasSuffix:retryRunningSummary[@"started_at"]] &&
               [retryRunning[@"issueTimestamp"]
                   isEqualToString:failedSummary[@"started_at"]] &&
               [retryRunning[@"issueOriginTimestamp"]
                   isEqualToString:failedSummary[@"started_at"]] &&
               [retryRunning[@"titleKey"]
                   isEqualToString:@"backupNotificationRetryRunningTitle"] &&
               [retryRunning[@"bodyKey"]
                   isEqualToString:@"backupNotificationRetryRunningBody"],
               @"a running retry updates the preliminary alert in place");

        NSMutableDictionary *interruptedRetrySummary =
            [retryRunningSummary mutableCopy];
        interruptedRetrySummary[@"pid"] = @"99999999";
        NSDictionary *interruptedRetry = Decision(
            policyClass, daily, interruptedRetrySummary, @"interrupted",
            Date(calendar, 21, 20, 57), calendar);
        Assert([interruptedRetry[@"kind"] isEqualToString:@"failure"] &&
               [interruptedRetry[@"issueOriginTimestamp"]
                   isEqualToString:failedSummary[@"started_at"]] &&
               [interruptedRetry[@"supersedesIdentifier"]
                   isEqualToString:retryPlanned[@"identifier"]] &&
               [interruptedRetry[@"bodyKey"]
                   isEqualToString:@"backupNotificationRetryFailureBody"],
               @"a dead retry process replaces progress with a terminal failure alert");

        NSMutableDictionary *missingAttempt = [retryRunningSummary mutableCopy];
        [missingAttempt removeObjectForKey:@"retry_attempt"];
        NSMutableDictionary *wrongAttempt = [retryRunningSummary mutableCopy];
        wrongAttempt[@"retry_attempt"] = @"2";
        NSMutableDictionary *wrongRunningStatus = [retryRunningSummary mutableCopy];
        NSMutableDictionary *wrongRunningTrigger = [retryRunningSummary mutableCopy];
        wrongRunningTrigger[@"trigger"] = @"schedule";
        NSMutableDictionary *invalidOrigin = [retryRunningSummary mutableCopy];
        invalidOrigin[@"retry_origin_started_at"] = @"not-a-time";
        NSMutableDictionary *missingStartedAt = [retryRunningSummary mutableCopy];
        [missingStartedAt removeObjectForKey:@"started_at"];
        NSMutableDictionary *invalidStartedAt = [retryRunningSummary mutableCopy];
        invalidStartedAt[@"started_at"] = @"not-a-time";
        NSMutableDictionary *nonAdvancingRetry = [retryRunningSummary mutableCopy];
        nonAdvancingRetry[@"started_at"] = failedSummary[@"started_at"];
        Assert(Decision(policyClass, daily, missingAttempt, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, wrongAttempt, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, wrongRunningStatus, @"failure",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, wrongRunningTrigger, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, invalidOrigin, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, missingStartedAt, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, invalidStartedAt, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil &&
               Decision(policyClass, daily, nonAdvancingRetry, @"running",
                        Date(calendar, 21, 20, 57), calendar) == nil,
               @"only a structurally valid first retry can replace an alert");

        NSTimeInterval originStart =
            Date(calendar, 21, 20, 0).timeIntervalSince1970;
        NSTimeInterval originFinish =
            Date(calendar, 21, 20, 5).timeIntervalSince1970;
        NSMutableDictionary *differentTimes = [failedSummary mutableCopy];
        differentTimes[@"trigger"] = @"schedule";
        differentTimes[@"started_at"] = [NSString stringWithFormat:@"%.0f", originStart];
        differentTimes[@"finished_at"] = [NSString stringWithFormat:@"%.0f", originFinish];
        NSDictionary *originalFailure = Decision(
            policyClass, daily, differentTimes, @"failure",
            Date(calendar, 21, 20, 6), calendar);
        Assert([originalFailure[@"issueTimestamp"] doubleValue] == originFinish &&
               [originalFailure[@"issueOriginTimestamp"] doubleValue] == originStart &&
               [originalFailure[@"identifier"] hasSuffix:
                   [NSString stringWithFormat:@".%.0f", originStart]],
               @"an original failure uses run start as canonical origin, not finish time");

        NSMutableDictionary *finalRetry = [differentTimes mutableCopy];
        finalRetry[@"trigger"] = @"schedule-retry";
        finalRetry[@"retry_origin_started_at"] =
            [NSString stringWithFormat:@"%.0f", originStart];
        finalRetry[@"retry_attempt"] = @"1";
        finalRetry[@"started_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 20, 40).timeIntervalSince1970];
        finalRetry[@"finished_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 20, 45).timeIntervalSince1970];
        NSDictionary *finalRetryDecision = Decision(
            policyClass, daily, finalRetry, @"failure",
            Date(calendar, 21, 20, 46), calendar);
        Assert([finalRetryDecision[@"issueOriginTimestamp"] doubleValue] == originStart,
               @"the final retry inherits the original run-start origin");

        NSMutableDictionary *missingRetryOrigin = [finalRetry mutableCopy];
        [missingRetryOrigin removeObjectForKey:@"retry_origin_started_at"];
        NSMutableDictionary *invalidRetryOrigin = [finalRetry mutableCopy];
        invalidRetryOrigin[@"retry_origin_started_at"] = @"not-a-time";
        NSMutableDictionary *nonAdvancingRetryOrigin = [finalRetry mutableCopy];
        nonAdvancingRetryOrigin[@"retry_origin_started_at"] =
            nonAdvancingRetryOrigin[@"started_at"];
        NSMutableDictionary *futureRetryOrigin = [finalRetry mutableCopy];
        futureRetryOrigin[@"retry_origin_started_at"] = futureRetryOrigin[@"finished_at"];
        NSMutableDictionary *missingFinalAttempt = [finalRetry mutableCopy];
        [missingFinalAttempt removeObjectForKey:@"retry_attempt"];
        NSMutableDictionary *wrongFinalAttempt = [finalRetry mutableCopy];
        wrongFinalAttempt[@"retry_attempt"] = @"2";
        Assert(Decision(policyClass, daily, missingRetryOrigin, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil &&
               Decision(policyClass, daily, invalidRetryOrigin, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil &&
               Decision(policyClass, daily, nonAdvancingRetryOrigin, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil &&
               Decision(policyClass, daily, futureRetryOrigin, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil &&
               Decision(policyClass, daily, missingFinalAttempt, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil &&
               Decision(policyClass, daily, wrongFinalAttempt, @"failure",
                        Date(calendar, 21, 20, 46), calendar) == nil,
               @"a malformed terminal retry cannot create a second issue origin");

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
        retryFailed[@"retry_origin_started_at"] = failedSummary[@"started_at"];
        retryFailed[@"retry_attempt"] = @"1";
        retryFailed[@"started_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 20, 56).timeIntervalSince1970];
        retryFailed[@"finished_at"] = [NSString stringWithFormat:@"%.0f",
            Date(calendar, 21, 21, 1).timeIntervalSince1970];
        NSDictionary<NSString *, NSString *> *finalFailure = Decision(
            policyClass, daily, retryFailed, @"failure", Date(calendar, 21, 21, 2), calendar);
        Assert([finalFailure[@"kind"] isEqualToString:@"failure"] &&
               [finalFailure[@"identifier"] containsString:retryFailed[@"started_at"]] &&
               [finalFailure[@"issueTimestamp"]
                   isEqualToString:retryFailed[@"finished_at"]] &&
               [finalFailure[@"issueOriginTimestamp"]
                   isEqualToString:failedSummary[@"started_at"]] &&
               [finalFailure[@"supersedesIdentifier"]
                   isEqualToString:retryPlanned[@"identifier"]] &&
               [finalFailure[@"bodyKey"] isEqualToString:@"backupNotificationRetryFailureBody"],
               @"a failed automatic retry replaces the preliminary retry alert");

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
               [missed[@"issueOriginTimestamp"] isEqualToString:missed[@"issueTimestamp"]] &&
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
