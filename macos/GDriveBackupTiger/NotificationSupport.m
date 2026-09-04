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

static NSTimeInterval GDTCanonicalTimestamp(id value) {
    if (![value isKindOfClass:NSString.class]) return 0;
    NSTimeInterval timestamp = GDTTimestamp(value);
    if (timestamp <= 0) return 0;
    NSString *canonical = [NSString stringWithFormat:@"%.0f", timestamp];
    return [(NSString *)value isEqualToString:canonical] ? timestamp : 0;
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
            GDTCanonicalTimestamp(parts[1]) <= 0 ||
            [accepted containsObject:candidate]) {
            continue;
        }
        [accepted addObject:candidate];
    }
    return accepted;
}

+ (NSArray<NSString *> *)successNotificationIdentifiersForProfileID:(NSString *)profileID
                                                candidateIdentifiers:
                                                    (NSArray<NSString *> *)candidateIdentifiers {
    NSString *safeProfileID = GDTSafeNotificationProfileID(profileID);
    NSString *prefix = [NSString stringWithFormat:
        @"com.commcats.gdrivebackup.%@.success.", safeProfileID];
    NSMutableArray<NSString *> *accepted = [NSMutableArray array];
    for (id candidate in candidateIdentifiers ?: @[]) {
        if (![candidate isKindOfClass:NSString.class] ||
            ![(NSString *)candidate hasPrefix:prefix]) {
            continue;
        }
        NSString *timestampValue =
            [(NSString *)candidate substringFromIndex:prefix.length];
        if (GDTCanonicalTimestamp(timestampValue) <= 0 ||
            [accepted containsObject:candidate]) {
            continue;
        }
        [accepted addObject:candidate];
    }
    return accepted;
}

+ (NSArray<NSString *> *)failureNotificationIdentifiersForProfileID:(NSString *)profileID
                                 throughIssueOriginTimestamp:(NSTimeInterval)cutoff
                                      candidateNotifications:
                                          (NSArray<NSDictionary<NSString *, id> *> *)candidates {
    if (cutoff <= 0) return @[];
    NSString *safeProfileID = GDTSafeNotificationProfileID(profileID);
    NSMutableArray<NSString *> *accepted = [NSMutableArray array];
    for (id value in candidates ?: @[]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary<NSString *, id> *candidate = value;
        NSString *identifier = [candidate[@"identifier"] isKindOfClass:NSString.class]
            ? candidate[@"identifier"] : @"";
        NSArray<NSString *> *safeIdentifiers =
            [self failureNotificationIdentifiersForProfileID:safeProfileID
                                         candidateIdentifiers:identifier.length
                                             ? @[identifier] : @[]];
        if (safeIdentifiers.count != 1) continue;

        NSArray<NSString *> *identifierParts =
            [identifier componentsSeparatedByString:@"."];
        NSTimeInterval issueOrigin =
            GDTCanonicalTimestamp(identifierParts.lastObject);
        BOOL hasNotificationMetadata =
            candidate[@"categoryIdentifier"] != nil || candidate[@"userInfo"] != nil;
        if (hasNotificationMetadata) {
            NSString *category =
                [candidate[@"categoryIdentifier"] isKindOfClass:NSString.class]
                    ? candidate[@"categoryIdentifier"] : @"";
            NSDictionary *userInfo = [candidate[@"userInfo"]
                isKindOfClass:NSDictionary.class] ? candidate[@"userInfo"] : nil;
            NSString *metadataProfileID =
                [userInfo[@"profileID"] isKindOfClass:NSString.class]
                    ? userInfo[@"profileID"] : @"";
            NSTimeInterval metadataOrigin =
                GDTCanonicalTimestamp(userInfo[@"issueOriginTimestamp"]);
            // A delivered request with partial or conflicting metadata is not
            // legacy. Falling back to its identifier could retire another issue.
            if (![category isEqualToString:@"GDT_BACKUP_ALERT"] ||
                ![metadataProfileID isEqualToString:safeProfileID] ||
                metadataOrigin <= 0) {
                continue;
            }
            issueOrigin = metadataOrigin;
        }
        if (issueOrigin <= cutoff && ![accepted containsObject:identifier]) {
            [accepted addObject:identifier];
        }
    }
    return accepted;
}

+ (NSDictionary<NSString *, NSString *> * _Nullable)
    successDecisionForConfig:(NSDictionary<NSString *, NSString *> *)config
                     summary:(NSDictionary<NSString *, NSString *> *)summary
                      status:(NSString *)status
        activeIssueTimestamp:(NSTimeInterval)activeIssueTimestamp
                         now:(NSDate *)now {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    BOOL recoveryNotificationsEnabled =
        ![config[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"];
    BOOL routineNotificationsEnabled =
        [config[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"1"];
    if (!automaticSchedule || [config[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"] ||
        ![status isEqualToString:@"success"] ||
        ![summary[@"status"] isEqualToString:@"success"] ||
        ![summary[@"exit_code"] isEqualToString:@"0"]) {
        return nil;
    }

    NSTimeInterval startedAt = GDTCanonicalTimestamp(summary[@"started_at"]);
    NSTimeInterval finishedAt = GDTCanonicalTimestamp(summary[@"finished_at"]);
    NSTimeInterval lastSuccessAt = GDTCanonicalTimestamp(summary[@"last_success_at"]);
    if (startedAt <= 0 || finishedAt < startedAt || lastSuccessAt < startedAt ||
        finishedAt > now.timeIntervalSince1970 ||
        now.timeIntervalSince1970 - finishedAt > 24 * 60 * 60) {
        return nil;
    }

    NSString *trigger = summary[@"trigger"] ?: @"";
    BOOL retry = [trigger isEqualToString:@"schedule-retry"];
    if (![trigger isEqualToString:@"schedule"] && !retry) return nil;
    if (retry) {
        NSTimeInterval retryOrigin =
            GDTCanonicalTimestamp(summary[@"retry_origin_started_at"]);
        if (![summary[@"retry_attempt"] isEqualToString:@"1"] ||
            retryOrigin <= 0 || retryOrigin >= startedAt) {
            return nil;
        }
    }

    BOOL recovery = recoveryNotificationsEnabled && activeIssueTimestamp > 0 &&
        activeIssueTimestamp < finishedAt;
    NSTimeInterval successMonitorStartedAt =
        GDTCanonicalTimestamp(config[@"GDRIVE_BACKUP_SUCCESS_NOTIFICATION_MONITOR_STARTED_AT"]);
    BOOL routine = routineNotificationsEnabled && successMonitorStartedAt > 0 &&
        successMonitorStartedAt < finishedAt;
    if (!recovery && !routine) return nil;

    NSString *profileID = GDTSafeNotificationProfileID(config[@"GDRIVE_BACKUP_PROFILE_ID"]);
    NSString *eventTimestamp = [NSString stringWithFormat:@"%.0f", finishedAt];
    NSString *bodyKey = recovery
        ? (retry ? @"backupNotificationRetrySuccessBody" : @"backupNotificationRecoverySuccessBody")
        : @"backupNotificationSuccessBody";
    return @{
        @"identifier": [NSString stringWithFormat:
            @"com.commcats.gdrivebackup.%@.success.%@", profileID, eventTimestamp],
        @"kind": @"success",
        @"profileID": profileID,
        @"eventTimestamp": eventTimestamp,
        @"titleKey": @"backupNotificationSuccessTitle",
        @"bodyKey": bodyKey
    };
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
    BOOL retryRunning = [status isEqualToString:@"running"] &&
        [trigger isEqualToString:@"schedule-retry"];
    NSTimeInterval retryOrigin = GDTTimestamp(summary[@"retry_origin_started_at"]);
    NSTimeInterval retryStarted = GDTTimestamp(summary[@"started_at"]);
    if (retryRunning && retryOrigin > 0 && retryStarted > retryOrigin &&
        [summary[@"status"] isEqualToString:@"running"] &&
        [summary[@"retry_attempt"] isEqualToString:@"1"]) {
        NSString *origin = [NSString stringWithFormat:@"%.0f", retryOrigin];
        return @{
            @"identifier": [NSString stringWithFormat:
                @"com.commcats.gdrivebackup.%@.failure.%@", profileID, origin],
            @"revision": [NSString stringWithFormat:@"retry-running.%.0f", retryStarted],
            @"kind": @"retry-running",
            @"profileID": profileID,
            @"issueTimestamp": origin,
            @"issueOriginTimestamp": origin,
            @"titleKey": @"backupNotificationRetryRunningTitle",
            @"bodyKey": @"backupNotificationRetryRunningBody"
        };
    }

    BOOL retryFailure = [trigger isEqualToString:@"schedule-retry"];
    BOOL scheduledFailure = [@[@"schedule", @"schedule-retry"] containsObject:trigger] &&
        ([@[@"failure", @"interrupted", @"cancelled"] containsObject:status]);
    NSTimeInterval retryFinished = GDTTimestamp(summary[@"finished_at"]);
    BOOL interruptedRunningRetry = [status isEqualToString:@"interrupted"] &&
        [summary[@"status"] isEqualToString:@"running"] &&
        ![summary[@"finished_at"] length] && ![summary[@"exit_code"] length];
    if (retryFailure &&
        ((![summary[@"status"] isEqualToString:status] &&
          !interruptedRunningRetry) ||
         ![summary[@"retry_attempt"] isEqualToString:@"1"] ||
         retryOrigin <= 0 || retryStarted <= retryOrigin ||
         (!interruptedRunningRetry && retryFinished < retryStarted))) {
        return nil;
    }
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
        NSTimeInterval retryOriginTimestamp =
            GDTTimestamp(summary[@"retry_origin_started_at"]);
        NSTimeInterval issueOriginTimestamp =
            retryFailure && retryOriginTimestamp > 0
                ? retryOriginTimestamp : runTimestamp;
        NSMutableDictionary<NSString *, NSString *> *decision = [@{
            @"identifier": [NSString stringWithFormat:
                @"com.commcats.gdrivebackup.%@.failure.%.0f", profileID, runTimestamp],
            @"kind": @"failure",
            @"profileID": profileID,
            @"issueTimestamp": [NSString stringWithFormat:@"%.0f", eventTimestamp],
            @"issueOriginTimestamp":
                [NSString stringWithFormat:@"%.0f", issueOriginTimestamp],
            @"titleKey": @"backupNotificationFailureTitle",
            @"bodyKey": bodyKey
        } mutableCopy];
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
        @"issueOriginTimestamp": [NSString stringWithFormat:@"%.0f", dueTimestamp],
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
