#import "DiagnosticsSupport.h"

static NSString *GDTAllowedString(id value, NSSet<NSString *> *allowed) {
    return [value isKindOfClass:NSString.class] && [allowed containsObject:value]
        ? value : @"unknown";
}

static NSString *GDTValidatedPattern(id value, NSString *pattern) {
    if (![value isKindOfClass:NSString.class]) {
        return @"unknown";
    }
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:pattern options:0 error:nil];
    NSString *string = value;
    NSTextCheckingResult *match = [expression firstMatchInString:string
                                                         options:0
                                                           range:NSMakeRange(0, string.length)];
    return match && NSEqualRanges(match.range, NSMakeRange(0, string.length))
        ? string : @"unknown";
}

static BOOL GDTStrictBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

static NSDictionary<NSString *, id> *GDTHealthRow(NSDictionary<NSString *, id> *health,
                                                   NSString *key,
                                                   BOOL includeMissing) {
    NSDictionary *input = [health[key] isKindOfClass:NSDictionary.class] ? health[key] : @{};
    NSString *status = GDTAllowedString(input[@"status"],
        [NSSet setWithArray:@[@"ready", @"failure", @"blocked", @"unknown"]]);
    NSMutableDictionary<NSString *, id> *row = [@{@"status": status} mutableCopy];
    if (includeMissing) {
        NSSet<NSString *> *known = [NSSet setWithArray:@[@"rclone", @"flock", @"jq"]];
        NSMutableArray<NSString *> *missing = [NSMutableArray array];
        if ([input[@"missing"] isKindOfClass:NSArray.class]) {
            for (id item in input[@"missing"]) {
                if ([item isKindOfClass:NSString.class] && [known containsObject:item]) {
                    [missing addObject:item];
                }
            }
        }
        [missing sortUsingSelector:@selector(compare:)];
        row[@"missing"] = missing;
    }
    return row;
}

@implementation GDTDiagnosticsBuilder

+ (NSDictionary<NSString *, id> *)snapshotForConfig:(NSDictionary<NSString *, NSString *> *)config
                                              summary:(NSDictionary<NSString *, NSString *> *)summary
                                          setupHealth:(NSDictionary<NSString *, id> *)setupHealth
                                              appInfo:(NSDictionary<NSString *, id> *)appInfo
                                         serviceState:(NSDictionary<NSString *, id> *)serviceState
                                          scriptState:(NSDictionary<NSString *, id> *)scriptState {
    NSDictionary<NSString *, id> *dependencies = GDTHealthRow(setupHealth, @"dependencies", YES);
    NSDictionary<NSString *, id> *remote = GDTHealthRow(setupHealth, @"remote", NO);
    NSDictionary<NSString *, id> *destination = GDTHealthRow(setupHealth, @"destination", NO);

    NSString *target = GDTAllowedString([config[@"GDRIVE_BACKUP_TARGET"] lowercaseString],
        [NSSet setWithArray:@[@"apfs", @"nas"]]);
    NSString *scheduleMode = GDTAllowedString([config[@"GDRIVE_BACKUP_SCHEDULE"] lowercaseString],
        [NSSet setWithArray:@[@"manual", @"login", @"hourly", @"daily"]]);
    NSString *encryption = GDTAllowedString([config[@"GDRIVE_BACKUP_ENCRYPTION"] lowercaseString],
        [NSSet setWithArray:@[@"none", @"apfs"]]);

    BOOL validSummary = [summary[@"protocol"] isEqualToString:@"1"];
    NSString *lastStatus = validSummary
        ? GDTAllowedString(summary[@"status"], [NSSet setWithArray:@[
            @"success", @"failure", @"cancelled", @"running", @"interrupted", @"unknown"
        ]]) : @"unknown";
    NSMutableDictionary<NSString *, id> *lastRun = [@{@"status": lastStatus} mutableCopy];
    if (validSummary) {
        NSString *trigger = GDTAllowedString(summary[@"trigger"],
            [NSSet setWithArray:@[@"manual", @"schedule", @"mount"]]);
        if (![trigger isEqualToString:@"unknown"]) {
            lastRun[@"trigger"] = trigger;
        }
        for (NSString *key in @[@"started_at", @"finished_at", @"exit_code"]) {
            NSString *value = GDTValidatedPattern(summary[key], @"^[0-9]+$");
            if (![value isEqualToString:@"unknown"]) {
                lastRun[key] = value;
            }
        }
        NSString *reason = GDTAllowedString(summary[@"reason"],
            [NSSet setWithArray:@[@"destination_permission_denied", @"nas_connection_lost"]]);
        if (![reason isEqualToString:@"unknown"]) {
            lastRun[@"reason"] = reason;
        }
    }

    NSString *version = GDTValidatedPattern(appInfo[@"version"], @"^[0-9]+(?:\\.[0-9]+){1,3}$");
    NSString *build = GDTValidatedPattern(appInfo[@"build"], @"^[0-9]+$");
    NSString *osVersion = GDTValidatedPattern(appInfo[@"osVersion"], @"^macOS [0-9]+(?:\\.[0-9]+){0,2}$");
    NSString *architecture = GDTAllowedString(appInfo[@"architecture"],
        [NSSet setWithArray:@[@"arm64", @"x86_64"]]);

    BOOL controllerLoaded = GDTStrictBoolean(serviceState[@"controllerLoaded"]);
    BOOL scheduleLoaded = GDTStrictBoolean(serviceState[@"scheduleLoaded"]);
    BOOL scriptInstalled = GDTStrictBoolean(scriptState[@"installed"]);
    BOOL scriptExecutable = GDTStrictBoolean(scriptState[@"executable"]);
    BOOL manualSchedule = [scheduleMode isEqualToString:@"manual"];
    BOOL setupReady = [setupHealth[@"overall"] isEqualToString:@"ready"] &&
        [dependencies[@"status"] isEqualToString:@"ready"] &&
        [remote[@"status"] isEqualToString:@"ready"] &&
        [destination[@"status"] isEqualToString:@"ready"];
    NSSet<NSString *> *attentionStatuses = [NSSet setWithArray:@[
        @"failure", @"cancelled", @"interrupted", @"unknown"
    ]];
    BOOL lastRunHealthy = ![attentionStatuses containsObject:lastStatus];
    BOOL ready = setupReady && controllerLoaded && scriptInstalled && scriptExecutable &&
        (manualSchedule || scheduleLoaded) && lastRunHealthy;

    return @{
        @"protocol": @"1",
        @"overall": ready ? @"ready" : @"attention",
        @"app": @{@"version": version, @"build": build},
        @"system": @{@"osVersion": osVersion, @"architecture": architecture},
        @"dependencies": dependencies,
        @"remote": remote,
        @"destination": @{
            @"status": destination[@"status"] ?: @"unknown",
            @"kind": target,
            @"encryption": encryption
        },
        @"schedule": @{@"mode": scheduleMode, @"loaded": @(scheduleLoaded)},
        @"controller": @{@"loaded": @(controllerLoaded)},
        @"script": @{@"installed": @(scriptInstalled), @"executable": @(scriptExecutable)},
        @"lastRun": lastRun
    };
}

+ (NSString *)reportForSnapshot:(NSDictionary<NSString *, id> *)snapshot {
    NSDictionary *app = [snapshot[@"app"] isKindOfClass:NSDictionary.class] ? snapshot[@"app"] : @{};
    NSDictionary *system = [snapshot[@"system"] isKindOfClass:NSDictionary.class] ? snapshot[@"system"] : @{};
    NSDictionary *dependencies = [snapshot[@"dependencies"] isKindOfClass:NSDictionary.class]
        ? snapshot[@"dependencies"] : @{};
    NSDictionary *remote = [snapshot[@"remote"] isKindOfClass:NSDictionary.class] ? snapshot[@"remote"] : @{};
    NSDictionary *destination = [snapshot[@"destination"] isKindOfClass:NSDictionary.class]
        ? snapshot[@"destination"] : @{};
    NSDictionary *schedule = [snapshot[@"schedule"] isKindOfClass:NSDictionary.class] ? snapshot[@"schedule"] : @{};
    NSDictionary *controller = [snapshot[@"controller"] isKindOfClass:NSDictionary.class]
        ? snapshot[@"controller"] : @{};
    NSDictionary *script = [snapshot[@"script"] isKindOfClass:NSDictionary.class] ? snapshot[@"script"] : @{};
    NSDictionary *lastRun = [snapshot[@"lastRun"] isKindOfClass:NSDictionary.class] ? snapshot[@"lastRun"] : @{};
    NSSet<NSString *> *knownTools = [NSSet setWithArray:@[@"rclone", @"flock", @"jq"]];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    if ([dependencies[@"missing"] isKindOfClass:NSArray.class]) {
        for (id tool in dependencies[@"missing"]) {
            if ([tool isKindOfClass:NSString.class] && [knownTools containsObject:tool]) {
                [missing addObject:tool];
            }
        }
    }
    [missing sortUsingSelector:@selector(compare:)];

    NSSet<NSString *> *healthStates = [NSSet setWithArray:@[
        @"ready", @"failure", @"blocked", @"unknown"
    ]];
    NSString *overall = GDTAllowedString(snapshot[@"overall"],
        [NSSet setWithArray:@[@"ready", @"attention"]]);
    NSString *version = GDTValidatedPattern(app[@"version"], @"^[0-9]+(?:\\.[0-9]+){1,3}$");
    NSString *build = GDTValidatedPattern(app[@"build"], @"^[0-9]+$");
    NSString *osVersion = GDTValidatedPattern(system[@"osVersion"],
        @"^macOS [0-9]+(?:\\.[0-9]+){0,2}$");
    NSString *architecture = GDTAllowedString(system[@"architecture"],
        [NSSet setWithArray:@[@"arm64", @"x86_64"]]);
    NSString *dependenciesStatus = GDTAllowedString(dependencies[@"status"], healthStates);
    NSString *remoteStatus = GDTAllowedString(remote[@"status"], healthStates);
    NSString *destinationStatus = GDTAllowedString(destination[@"status"], healthStates);
    NSString *destinationKind = GDTAllowedString(destination[@"kind"],
        [NSSet setWithArray:@[@"apfs", @"nas"]]);
    NSString *destinationEncryption = GDTAllowedString(destination[@"encryption"],
        [NSSet setWithArray:@[@"none", @"apfs"]]);
    NSString *scheduleMode = GDTAllowedString(schedule[@"mode"],
        [NSSet setWithArray:@[@"manual", @"login", @"hourly", @"daily"]]);
    NSString *lastStatus = GDTAllowedString(lastRun[@"status"],
        [NSSet setWithArray:@[
            @"success", @"failure", @"cancelled", @"running", @"interrupted", @"unknown"
        ]]);

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithArray:@[
        @"GDrive Backup Tiger Diagnostics",
        @"protocol=1",
        [NSString stringWithFormat:@"overall=%@", overall],
        [NSString stringWithFormat:@"app.version=%@", version],
        [NSString stringWithFormat:@"app.build=%@", build],
        [NSString stringWithFormat:@"system.os=%@", osVersion],
        [NSString stringWithFormat:@"system.architecture=%@", architecture],
        [NSString stringWithFormat:@"dependencies.status=%@", dependenciesStatus],
        [NSString stringWithFormat:@"dependencies.missing=%@",
            missing.count ? [missing componentsJoinedByString:@","] : @"none"],
        [NSString stringWithFormat:@"remote.status=%@", remoteStatus],
        [NSString stringWithFormat:@"destination.status=%@", destinationStatus],
        [NSString stringWithFormat:@"destination.kind=%@", destinationKind],
        [NSString stringWithFormat:@"destination.encryption=%@", destinationEncryption],
        [NSString stringWithFormat:@"schedule.mode=%@", scheduleMode],
        [NSString stringWithFormat:@"schedule.loaded=%@", GDTStrictBoolean(schedule[@"loaded"]) ? @"yes" : @"no"],
        [NSString stringWithFormat:@"controller.loaded=%@", GDTStrictBoolean(controller[@"loaded"]) ? @"yes" : @"no"],
        [NSString stringWithFormat:@"script.installed=%@", GDTStrictBoolean(script[@"installed"]) ? @"yes" : @"no"],
        [NSString stringWithFormat:@"script.executable=%@", GDTStrictBoolean(script[@"executable"]) ? @"yes" : @"no"],
        [NSString stringWithFormat:@"last_run.status=%@", lastStatus]
    ]];
    NSDictionary<NSString *, NSString *> *lastKeys = @{
        @"started_at": @"last_run.started_at",
        @"finished_at": @"last_run.finished_at",
        @"exit_code": @"last_run.exit_code",
        @"trigger": @"last_run.trigger",
        @"reason": @"last_run.reason"
    };
    NSDictionary<NSString *, NSString *> *safeLastValues = @{
        @"started_at": GDTValidatedPattern(lastRun[@"started_at"], @"^[0-9]+$"),
        @"finished_at": GDTValidatedPattern(lastRun[@"finished_at"], @"^[0-9]+$"),
        @"exit_code": GDTValidatedPattern(lastRun[@"exit_code"], @"^[0-9]+$"),
        @"trigger": GDTAllowedString(lastRun[@"trigger"],
            [NSSet setWithArray:@[@"manual", @"schedule", @"mount"]]),
        @"reason": GDTAllowedString(lastRun[@"reason"],
            [NSSet setWithArray:@[@"destination_permission_denied", @"nas_connection_lost"]])
    };
    for (NSString *key in @[@"started_at", @"finished_at", @"exit_code", @"trigger", @"reason"]) {
        NSString *value = safeLastValues[key];
        if (![value isEqualToString:@"unknown"]) {
            [lines addObject:[NSString stringWithFormat:@"%@=%@", lastKeys[key], value]];
        }
    }
    return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

@end
