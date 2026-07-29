#import <Foundation/Foundation.h>
#import <objc/message.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSDictionary<NSString *, NSString *> *Decision(
    Class policyClass,
    NSDictionary<NSString *, NSString *> *config,
    NSDictionary<NSString *, NSString *> *summary,
    NSString *status,
    NSDate *now) {
    SEL selector = NSSelectorFromString(@"decisionForConfig:summary:status:now:");
    if (!policyClass || ![policyClass respondsToSelector:selector]) return nil;
    typedef NSDictionary *(*DecisionMethod)(
        id, SEL, NSDictionary *, NSDictionary *, NSString *, NSDate *);
    DecisionMethod method = (DecisionMethod)[policyClass methodForSelector:selector];
    return method(policyClass, selector, config, summary, status, now);
}

int main(void) {
    @autoreleasepool {
        Class policyClass = NSClassFromString(@"GDTAutomaticRetryPolicy");
        Assert(policyClass != Nil,
               @"automatic retry policy is available to the persistent controller");

        NSDictionary<NSString *, NSString *> *dailyNAS = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"office",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily",
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_PAUSED": @"0"
        };
        NSDictionary<NSString *, NSString *> *mountNotReady = @{
            @"protocol": @"1",
            @"status": @"failure",
            @"started_at": @"1000",
            @"finished_at": @"1040",
            @"exit_code": @"69",
            @"trigger": @"schedule",
            @"target": @"nas",
            @"reason": @"nas_mount_not_ready"
        };

        Assert(Decision(policyClass, dailyNAS, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2839]) == nil,
               @"a transient NAS failure is not retried before its 30-minute delay");

        NSDictionary<NSString *, NSString *> *due = Decision(
            policyClass, dailyNAS, mountNotReady, @"failure",
            [NSDate dateWithTimeIntervalSince1970:2840]);
        Assert([due[@"identifier"] isEqualToString:@"office.automatic-retry.1000"] &&
               [due[@"profileID"] isEqualToString:@"office"] &&
               [due[@"originStartedAt"] isEqualToString:@"1000"] &&
               [due[@"attempt"] isEqualToString:@"1"] &&
               [due[@"trigger"] isEqualToString:@"schedule-retry"],
               @"a retryable scheduled NAS failure creates one stable retry decision");

        NSMutableDictionary<NSString *, NSString *> *mountUnavailable =
            [mountNotReady mutableCopy];
        mountUnavailable[@"reason"] = @"nas_mount_unavailable";
        Assert(Decision(policyClass, dailyNAS, mountUnavailable, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) != nil,
               @"an unavailable configured NAS mount is retryable");

        NSMutableDictionary<NSString *, NSString *> *destinationUnreadable =
            [mountNotReady mutableCopy];
        destinationUnreadable[@"reason"] = @"destination_unreadable";
        NSDictionary<NSString *, NSString *> *unreadableRetry = Decision(
            policyClass, dailyNAS, destinationUnreadable, @"failure",
            [NSDate dateWithTimeIntervalSince1970:2840]);
        Assert([unreadableRetry[@"identifier"]
                   isEqualToString:@"office.automatic-retry.1000"] &&
               [unreadableRetry[@"trigger"] isEqualToString:@"schedule-retry"],
               @"a fail-closed transient NAS read failure is retried once");

        NSMutableDictionary<NSString *, NSString *> *permissionFailure =
            [mountNotReady mutableCopy];
        permissionFailure[@"reason"] = @"destination_permission_denied";
        Assert(Decision(policyClass, dailyNAS, permissionFailure, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"a permanent destination permission failure is not retried");

        for (NSString *reason in @[
                 @"invalid_name_codec",
                 @"name_codec_collision",
                 @"unsupported_rclone"
             ]) {
            NSMutableDictionary<NSString *, NSString *> *unsafeFailure =
                [mountNotReady mutableCopy];
            unsafeFailure[@"reason"] = reason;
            Assert(Decision(policyClass, dailyNAS, unsafeFailure, @"failure",
                            [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
                   [NSString stringWithFormat:
                       @"the permanent safety failure %@ is never retried", reason]);
        }

        NSMutableDictionary<NSString *, NSString *> *unclassified =
            [mountNotReady mutableCopy];
        [unclassified removeObjectForKey:@"reason"];
        Assert(Decision(policyClass, dailyNAS, unclassified, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"exit code 69 alone is too broad to authorize an automatic retry");

        NSMutableDictionary<NSString *, NSString *> *paused = [dailyNAS mutableCopy];
        paused[@"GDRIVE_BACKUP_PAUSED"] = @"1";
        Assert(Decision(policyClass, paused, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"pausing automatic backups cancels a pending retry");

        NSMutableDictionary<NSString *, NSString *> *manual = [dailyNAS mutableCopy];
        manual[@"GDRIVE_BACKUP_SCHEDULE"] = @"manual";
        Assert(Decision(policyClass, manual, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"manual-only profiles never create background retries");

        NSMutableDictionary<NSString *, NSString *> *external = [dailyNAS mutableCopy];
        external[@"GDRIVE_BACKUP_TARGET"] = @"apfs";
        Assert(Decision(policyClass, external, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"the NAS retry policy cannot start an external-volume backup");

        NSMutableDictionary<NSString *, NSString *> *alreadyRetried =
            [mountNotReady mutableCopy];
        alreadyRetried[@"trigger"] = @"schedule-retry";
        Assert(Decision(policyClass, dailyNAS, alreadyRetried, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"one scheduled failure can create at most one automatic retry");

        NSMutableDictionary<NSString *, NSString *> *superseded =
            [mountNotReady mutableCopy];
        superseded[@"last_success_at"] = @"1100";
        Assert(Decision(policyClass, dailyNAS, superseded, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"a newer successful backup cancels a pending retry");

        Assert(Decision(policyClass, dailyNAS, mountNotReady, @"running",
                        [NSDate dateWithTimeIntervalSince1970:2840]) == nil,
               @"a running backup prevents a parallel retry");

        Assert(Decision(policyClass, dailyNAS, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:11841]) != nil,
               @"sleeping for several hours defers rather than loses the retry");

        Assert(Decision(policyClass, dailyNAS, mountNotReady, @"failure",
                        [NSDate dateWithTimeIntervalSince1970:87441]) == nil,
               @"a retry still expires after one full day without a newer run");
    }

    if (failures > 0) {
        printf("%d automatic retry support test(s) failed.\n", failures);
        return 1;
    }
    printf("All automatic retry support tests passed.\n");
    return 0;
}
