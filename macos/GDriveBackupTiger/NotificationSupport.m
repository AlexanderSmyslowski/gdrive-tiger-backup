#import "NotificationSupport.h"

static NSString *GDTSafeNotificationProfileID(NSString *value) {
    NSString *source = value.length ? value.lowercaseString : @"legacy";
    NSMutableString *safe = [NSMutableString stringWithCapacity:source.length];
    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
    for (NSUInteger index = 0; index < source.length && safe.length < 64; index++) {
        unichar character = [source characterAtIndex:index];
        unichar safeCharacter = [allowed characterIsMember:character] ? character : (unichar)'-';
        [safe appendFormat:@"%C", safeCharacter];
    }
    return safe.length ? safe : @"legacy";
}

static NSTimeInterval GDTTimestamp(NSString *value) {
    if (!value.length) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    long long timestamp = 0;
    if (![scanner scanLongLong:&timestamp] || !scanner.isAtEnd || timestamp <= 0) return 0;
    return (NSTimeInterval)timestamp;
}

static NSString *GDTSafeRetryProfileID(NSString *value) {
    return GDTSafeNotificationProfileID(value);
}

static BOOL GDTIsRetryableNASReason(NSString *reason) {
    return [@[
        @"nas_mount_unavailable",
        @"nas_mount_not_ready",
        // The shell emits this only when its read-only NAS codec preflight
        // cannot safely inspect the destination. A later retry repeats every
        // fail-closed check before any copy can start.
        @"destination_unreadable"
    ] containsObject:reason ?: @""];
}

static NSDate *GDTWatchdogDateForNow(NSDate *now, NSCalendar *calendar) {
    NSDate *watchdog = [calendar dateBySettingHour:21 minute:0 second:0 ofDate:now options:0];
    if ([watchdog compare:now] == NSOrderedDescending) {
        watchdog = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:watchdog options:0];
    }
    return watchdog;
}

@implementation GDTBackupNotificationPolicy

+ (NSArray<NSString *> *)failureNotificationIdentifiersForProfileID:(NSString *)profileID
                                                candidateIdentifiers:
                                                    (NSArray<NSString *> *)candidateIdentifiers {
    NSString *safeProfileID = GDTSafeNotificationProfileID(profileID);
    NSString *prefix = [NSString stringWithFormat:
        @"com.commcats.gdrivebackup.%@.", safeProfileID];
    NSMutableArray<NSString *> *accepted = [NSMutableArray array];
    for (id candidate in candidateIdentifiers ?: @[]) {
        if (![candidate isKindOfClass:NSString.class] ||
            ![(NSString *)candidate hasPrefix:prefix]) {
            continue;
        }
        NSString *suffix = [(NSString *)candidate substringFromIndex:prefix.length];
        NSArray<NSString *> *parts = [suffix componentsSeparatedByString:@"."];
        if (parts.count != 2 ||
            ![@[@"failure", @"missed"] containsObject:parts[0]] ||
            GDTTimestamp(parts[1]) <= 0 ||
            [accepted containsObject:candidate]) {
            continue;
        }
        [accepted addObject:candidate];
    }
    return accepted;
}

+ (NSDictionary<NSString *, NSString *> * _Nullable)
    decisionForConfig:(NSDictionary<NSString *, NSString *> *)config
               summary:(NSDictionary<NSString *, NSString *> *)summary
                status:(NSString *)status
                   now:(NSDate *)now
              calendar:(NSCalendar *)calendar {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL notificationsEnabled = ![config[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"];
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    if (!notificationsEnabled || !automaticSchedule ||
        [config[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"]) {
        return nil;
    }

    NSString *profileID = GDTSafeNotificationProfileID(config[@"GDRIVE_BACKUP_PROFILE_ID"]);
    NSTimeInterval nowTimestamp = now.timeIntervalSince1970;
    NSTimeInterval monitorStartedAt = GDTTimestamp(
        config[@"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT"]);
    NSTimeInterval eventTimestamp = GDTTimestamp(summary[@"finished_at"]);
    if (eventTimestamp <= 0) eventTimestamp = GDTTimestamp(summary[@"started_at"]);
    NSString *trigger = summary[@"trigger"] ?: @"";
    BOOL retryFailure = [trigger isEqualToString:@"schedule-retry"];
    BOOL scheduledFailure = [@[@"schedule", @"schedule-retry"] containsObject:trigger] &&
        ([@[@"failure", @"interrupted", @"cancelled"] containsObject:status]);
    BOOL eventIsFresh = eventTimestamp > 0 && eventTimestamp <= nowTimestamp + 1 &&
        nowTimestamp - eventTimestamp <= 24 * 60 * 60;
    BOOL eventWasMonitored = monitorStartedAt <= 0 || eventTimestamp >= monitorStartedAt;
    if (scheduledFailure && eventIsFresh && eventWasMonitored) {
        NSString *bodyKey = @"failedHint";
        NSString *reason = summary[@"reason"] ?: @"";
        if (retryFailure) {
            bodyKey = @"backupNotificationRetryFailureBody";
        } else if (GDTIsRetryableNASReason(reason)) {
            bodyKey = @"backupNotificationNASRetryBody";
        } else if ([reason isEqualToString:@"destination_permission_denied"]) {
            bodyKey = @"failedPermissionHint";
        } else if ([reason isEqualToString:@"nas_connection_lost"]) {
            bodyKey = @"failedNASConnectionHint";
        } else if ([summary[@"exit_code"] integerValue] == 69) {
            bodyKey = @"backupNotificationTargetUnavailable";
        }
        NSTimeInterval runTimestamp = GDTTimestamp(summary[@"started_at"]);
        if (runTimestamp <= 0) runTimestamp = eventTimestamp;
        NSMutableDictionary<NSString *, NSString *> *decision = [@{
            @"identifier": [NSString stringWithFormat:
                @"com.commcats.gdrivebackup.%@.failure.%.0f", profileID, runTimestamp],
            @"kind": @"failure",
            @"profileID": profileID,
            @"issueTimestamp": [NSString stringWithFormat:@"%.0f", eventTimestamp],
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": bodyKey
        } mutableCopy];
        NSTimeInterval retryOriginTimestamp =
            GDTTimestamp(summary[@"retry_origin_started_at"]);
        if (retryFailure && retryOriginTimestamp > 0 &&
            retryOriginTimestamp < runTimestamp) {
            decision[@"supersedesIdentifier"] = [NSString stringWithFormat:
                @"com.commcats.gdrivebackup.%@.failure.%.0f",
                profileID, retryOriginTimestamp];
        }
        return decision;
    }

    if (![schedule isEqualToString:@"daily"]) return nil;

    NSDate *watchdog = GDTWatchdogDateForNow(now, calendar);
    NSDate *due = [calendar dateByAddingUnit:NSCalendarUnitHour value:-1 toDate:watchdog options:0];
    NSTimeInterval dueTimestamp = due.timeIntervalSince1970;
    // A newly enabled monitor must not report a deadline that predates the
    // user's choice; its first eligible window is the following daily run.
    if (monitorStartedAt > dueTimestamp) return nil;
    if ([status isEqualToString:@"running"]) return nil;

    NSTimeInterval finishedAt = GDTTimestamp(summary[@"finished_at"]);
    NSTimeInterval lastSuccessAt = GDTTimestamp(summary[@"last_success_at"]);
    if (lastSuccessAt <= 0 && [status isEqualToString:@"success"]) {
        lastSuccessAt = finishedAt;
    }
    if (lastSuccessAt >= dueTimestamp && lastSuccessAt <= nowTimestamp + 1) {
        return nil;
    }

    return @{
        @"identifier": [NSString stringWithFormat:
            @"com.commcats.gdrivebackup.%@.missed.%.0f", profileID, dueTimestamp],
        @"kind": @"missed",
        @"profileID": profileID,
        @"issueTimestamp": [NSString stringWithFormat:@"%.0f", dueTimestamp],
        @"titleKey": @"backupNotificationMissedTitle",
        @"bodyKey": @"backupNotificationMissedBody"
    };
}

@end

@implementation GDTAutomaticRetryPolicy

+ (NSDictionary<NSString *, NSString *> * _Nullable)
    decisionForConfig:(NSDictionary<NSString *, NSString *> *)config
               summary:(NSDictionary<NSString *, NSString *> *)summary
                status:(NSString *)status
                   now:(NSDate *)now {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"" lowercaseString];
    if (![@[@"login", @"hourly", @"daily"] containsObject:schedule] ||
        ![target isEqualToString:@"nas"] ||
        [config[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"] ||
        ![status isEqualToString:@"failure"] ||
        ![summary[@"trigger"] isEqualToString:@"schedule"]) {
        return nil;
    }

    // Exit 69 also covers permanent safety failures, so retry only the
    // explicitly fail-closed NAS outcomes above.
    NSString *reason = summary[@"reason"] ?: @"";
    if (!GDTIsRetryableNASReason(reason)) {
        return nil;
    }

    NSTimeInterval startedAt = GDTTimestamp(summary[@"started_at"]);
    NSTimeInterval finishedAt = GDTTimestamp(summary[@"finished_at"]);
    NSTimeInterval lastSuccessAt = GDTTimestamp(summary[@"last_success_at"]);
    if (startedAt <= 0 || finishedAt < startedAt || lastSuccessAt >= startedAt) {
        return nil;
    }

    static const NSTimeInterval retryDelay = 30 * 60;
    // A sleeping Mac may miss the nominal delay by several hours. The durable
    // run summary keeps one retry eligible until the next daily window, while
    // a newer run or success still supersedes it immediately.
    static const NSTimeInterval retryLifetime = 24 * 60 * 60;
    NSTimeInterval nowTimestamp = now.timeIntervalSince1970;
    if (nowTimestamp < finishedAt + retryDelay ||
        nowTimestamp > finishedAt + retryLifetime) {
        return nil;
    }

    NSString *profileID = GDTSafeRetryProfileID(config[@"GDRIVE_BACKUP_PROFILE_ID"]);
    NSString *origin = [NSString stringWithFormat:@"%.0f", startedAt];
    return @{
        @"identifier": [NSString stringWithFormat:@"%@.automatic-retry.%@", profileID, origin],
        @"profileID": profileID,
        @"originStartedAt": origin,
        @"attempt": @"1",
        @"trigger": @"schedule-retry"
    };
}

@end
