#import "BackupStatusSupport.h"

#include <errno.h>
#include <signal.h>

static BOOL GDTIsUnsignedInteger(NSString *value, BOOL positive) {
    if (!value.length || [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) {
        return NO;
    }
    unsigned long long number = strtoull(value.UTF8String, NULL, 10);
    return !positive || number > 0;
}

static NSString *GDTNormalizedTarget(NSDictionary<NSString *, NSString *> *config) {
    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    NSSet<NSString *> *networkTargets = [NSSet setWithArray:@[@"nas", @"network", @"smb", @"afp", @"nfs"]];
    return [networkTargets containsObject:target] ? @"nas" : @"apfs";
}

static NSString *GDTAPFSVolumePath(NSDictionary<NSString *, NSString *> *config) {
    NSString *volume = config[@"GDRIVE_BACKUP_VOLUME"];
    if (volume.length) {
        return volume.stringByStandardizingPath;
    }
    NSString *name = config[@"GDRIVE_BACKUP_VOLUME_NAME"] ?: @"GoogleDrive-Backup";
    return [[@"/Volumes" stringByAppendingPathComponent:name] stringByStandardizingPath];
}

static NSString *GDTMountedVolumeRootForPath(NSString *path) {
    NSArray<NSString *> *components = path.stringByStandardizingPath.pathComponents;
    if (components.count >= 3 && [components[1] isEqualToString:@"Volumes"]) {
        return [@"/Volumes" stringByAppendingPathComponent:components[2]];
    }
    return path.stringByStandardizingPath;
}

NSString *GDTBackupSummaryPath(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_SUMMARY_STATE_FILE"];
    if (override.length) {
        return override;
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/GDrive Backup Tiger/last-run.status"];
}

NSString *GDTBackupSummaryPathForConfig(NSDictionary<NSString *, NSString *> *config) {
    NSString *override = NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_SUMMARY_STATE_FILE"];
    if (override.length) return override;
    NSString *profileID = config[@"GDRIVE_BACKUP_PROFILE_ID"];
    if (!profileID.length || profileID.length > 64) return GDTBackupSummaryPath();
    NSCharacterSet *first = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789"];
    NSCharacterSet *remaining = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789-"];
    if (![first characterIsMember:[profileID characterAtIndex:0]]) return GDTBackupSummaryPath();
    for (NSUInteger index = 1; index < profileID.length; index++) {
        if (![remaining characterIsMember:[profileID characterAtIndex:index]]) {
            return GDTBackupSummaryPath();
        }
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:
        @"Library/Application Support/GDrive Backup Tiger/profiles/%@/last-run.status",
        profileID]];
}

NSDictionary<NSString *, NSString *> *GDTReadBackupSummaryAtPath(NSString *path) {
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (!content.length) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange separator = [line rangeOfString:@"="];
        if (separator.location == NSNotFound || separator.location == 0) {
            continue;
        }
        NSString *key = [line substringToIndex:separator.location];
        NSString *value = [line substringFromIndex:NSMaxRange(separator)];
        values[key] = value;
    }
    return values;
}

NSString *GDTBackupSummaryStatusForValues(NSDictionary<NSString *, NSString *> *values) {
    NSString *status = values[@"status"] ?: @"";
    NSString *pid = values[@"pid"] ?: @"";
    NSString *startedAt = values[@"started_at"] ?: @"";
    if (![values[@"protocol"] isEqualToString:@"1"] ||
        !GDTIsUnsignedInteger(pid, YES) ||
        !GDTIsUnsignedInteger(startedAt, YES)) {
        return @"unknown";
    }

    if ([status isEqualToString:@"running"] && !values[@"finished_at"] && !values[@"exit_code"]) {
        errno = 0;
        if (kill((pid_t)pid.intValue, 0) == 0 || errno == EPERM) {
            return @"running";
        }
        return @"interrupted";
    }

    NSString *finishedAt = values[@"finished_at"] ?: @"";
    NSString *exitCode = values[@"exit_code"] ?: @"";
    if (!GDTIsUnsignedInteger(finishedAt, YES) ||
        !GDTIsUnsignedInteger(exitCode, NO) ||
        finishedAt.longLongValue < startedAt.longLongValue) {
        return @"unknown";
    }
    if ([status isEqualToString:@"success"] && exitCode.intValue == 0) {
        return @"success";
    }
    if ([status isEqualToString:@"failure"]) {
        return @"failure";
    }
    if ([status isEqualToString:@"cancelled"] &&
        (exitCode.intValue == 129 || exitCode.intValue == 130 || exitCode.intValue == 143)) {
        return @"cancelled";
    }
    return @"unknown";
}

NSString *GDTBackupSummaryStatusAtPath(NSString *path) {
    return GDTBackupSummaryStatusForValues(GDTReadBackupSummaryAtPath(path));
}

NSString *GDTBackupDestinationForConfig(NSDictionary<NSString *, NSString *> *config) {
    NSString *override = config[@"GDRIVE_BACKUP_DEST_ROOT"];
    if (override.length) {
        return override.stringByStandardizingPath;
    }
    if ([GDTNormalizedTarget(config) isEqualToString:@"nas"]) {
        NSString *mount = config[@"GDRIVE_BACKUP_NAS_MOUNT"];
        if (!mount.length) {
            return @"";
        }
        NSString *subdirectory = config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup";
        return [[mount stringByAppendingPathComponent:subdirectory] stringByStandardizingPath];
    }
    return GDTAPFSVolumePath(config);
}

NSString *GDTBackupCapacityPathForConfig(NSDictionary<NSString *, NSString *> *config) {
    if ([GDTNormalizedTarget(config) isEqualToString:@"nas"]) {
        NSString *mount = config[@"GDRIVE_BACKUP_NAS_MOUNT"];
        if (mount.length) {
            return mount.stringByStandardizingPath;
        }
    }
    NSString *destination = GDTBackupDestinationForConfig(config);
    return destination.length ? GDTMountedVolumeRootForPath(destination) : @"";
}

NSDate *GDTNextDailyRunAfterDate(NSDate *date, NSCalendar *calendar) {
    NSDate *candidate = [calendar dateBySettingHour:20
                                             minute:0
                                             second:0
                                             ofDate:date
                                            options:NSCalendarMatchNextTime];
    if ([candidate compare:date] != NSOrderedDescending) {
        candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:candidate options:0];
    }
    return candidate;
}

NSDictionary<NSString *, NSNumber *> *GDTStorageCapacityForPath(NSString *path) {
    BOOL isDirectory = NO;
    if (!path.length ||
        ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] ||
        !isDirectory) {
        return nil;
    }
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [NSFileManager.defaultManager attributesOfFileSystemForPath:path error:nil];
    NSNumber *freeBytes = attributes[NSFileSystemFreeSize];
    NSNumber *totalBytes = attributes[NSFileSystemSize];
    if (!freeBytes || !totalBytes) {
        return nil;
    }
    return @{ @"freeBytes": freeBytes, @"totalBytes": totalBytes };
}

NSDictionary<NSString *, NSString *> *GDTLastSuccessfulBackupForSummary(
    NSDictionary<NSString *, NSString *> *summary, NSDate *now) {
    if (![summary[@"protocol"] isEqualToString:@"1"]) return nil;
    BOOL success = [GDTBackupSummaryStatusForValues(summary) isEqualToString:@"success"];
    NSString *timestamp = summary[@"last_success_at"];
    if (!timestamp.length && success) timestamp = summary[@"finished_at"];
    if (!GDTIsUnsignedInteger(timestamp, YES) || timestamp.length > 12 ||
        timestamp.doubleValue > now.timeIntervalSince1970) return nil;
    NSString *target = summary[@"last_success_target"] ?: @"";
    NSString *destination = summary[@"last_success_destination"] ?: @"";
    NSString *volume = summary[@"last_success_volume"] ?: @"";
    if (!destination.length && success && [timestamp isEqualToString:summary[@"finished_at"]]) {
        target = summary[@"target"] ?: @"";
        destination = summary[@"destination"] ?: @"";
        NSArray *components = destination.pathComponents;
        if (components.count >= 3 && [components[1] isEqualToString:@"Volumes"])
            volume = components[2];
    }
    // Never attach the current destination to a timestamp preserved from another run.
    NSCharacterSet *controls = NSCharacterSet.controlCharacterSet;
    if (![@[@"nas", @"apfs"] containsObject:target] || !destination.isAbsolutePath ||
        !volume.length || volume.length > 255 ||
        [volume rangeOfCharacterFromSet:controls].location != NSNotFound) {
        target = @""; destination = @""; volume = @"";
    }
    return @{@"at": timestamp, @"target": target, @"destination": destination, @"volume": volume};
}

NSDictionary<NSString *, NSString *> *GDTLatestSuccessfulBackupAtRoot(NSString *root, NSDate *now) {
    NSFileManager *manager = NSFileManager.defaultManager;
    BOOL (^plainDirectory)(NSString *) = ^BOOL(NSString *path) {
        return [[manager attributesOfItemAtPath:path error:nil][NSFileType] isEqualToString:NSFileTypeDirectory];
    };
    if (!plainDirectory(root)) return nil;
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:
        [root stringByAppendingPathComponent:@"last-run.status"]];
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
    for (NSString *kind in @[@"profiles", @"manual"]) {
        NSString *directory = [root stringByAppendingPathComponent:kind];
        if (!plainDirectory(directory)) continue;
        NSArray *children = [[manager contentsOfDirectoryAtPath:directory error:nil]
            sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in children) {
            if (!name.length || name.length > 64 ||
                [name rangeOfCharacterFromSet:safe.invertedSet].location != NSNotFound) continue;
            NSString *child = [directory stringByAppendingPathComponent:name];
            if (plainDirectory(child)) [paths addObject:[child stringByAppendingPathComponent:@"last-run.status"]];
        }
    }
    NSDictionary *latest = nil;
    for (NSString *path in paths) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
        if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular] ||
            [attributes[NSFileSize] unsignedLongLongValue] > 65536) continue;
        NSDictionary *record = GDTLastSuccessfulBackupForSummary(GDTReadBackupSummaryAtPath(path), now);
        if (record && (!latest || [record[@"at"] longLongValue] > [latest[@"at"] longLongValue] ||
            ([record[@"at"] isEqual:latest[@"at"]] && ![latest[@"volume"] length] && [record[@"volume"] length]))) latest = record;
    }
    return latest;
}

NSString *GDTBackupHistoryPath(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_HISTORY_FILE"];
    if (override.length) return override;
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/GDrive Backup Tiger/run-history.tsv"];
}

// Which destination a run went to, in words a user recognizes: the disk name
// for an external disk, the backup folder for a NAS share (whose mount point
// can change between "share" and "share-1" and must not split the history).
static NSString *GDTBackupHistoryLabel(NSString *target, NSString *destination) {
    NSArray<NSString *> *components = destination.stringByStandardizingPath.pathComponents;
    if ([target isEqualToString:@"apfs"] && components.count >= 3 &&
        [components[1] isEqualToString:@"Volumes"]) {
        return components[2];
    }
    NSString *last = destination.stringByStandardizingPath.lastPathComponent;
    return [last isEqualToString:@"/"] ? @"" : (last ?: @"");
}

static BOOL GDTHistoryNumber(NSString *value, NSUInteger maxLength) {
    return value.length && value.length <= maxLength &&
        [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static NSString *GDTHistoryText(NSString *value) {
    if (!value.length || value.length > 255 ||
        [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

NSArray<NSDictionary<NSString *, id> *> *GDTBackupHistoryGroups(
    NSString *content, NSUInteger runLimit, NSUInteger maxGroups) {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    NSRegularExpression *uuidPattern = [NSRegularExpression regularExpressionWithPattern:
        @"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$" options:0 error:nil];
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count < 7 || ![fields[0] isEqualToString:@"v1"]) continue;
        NSString *finished = fields[1], *status = fields[2], *target = fields[3], *started = fields[6];
        if (!GDTHistoryNumber(finished, 12)) continue;
        if (![@[@"nas", @"apfs"] containsObject:target] ||
            ![@[@"success", @"failure", @"cancelled"] containsObject:status]) continue;
        NSString *label = GDTHistoryText(GDTBackupHistoryLabel(target, fields[4]));
        if (!label.length) continue;
        NSString *uuid = fields.count >= 12 ? fields[7].uppercaseString : @"";
        if (![uuidPattern firstMatchInString:uuid options:0 range:NSMakeRange(0, uuid.length)]) uuid = @"";
        NSString *key = [target isEqualToString:@"nas"]
            ? [@"nas:" stringByAppendingString:label]
            : (uuid.length ? [@"apfs:" stringByAppendingString:uuid] : [@"apfs-name:" stringByAppendingString:label]);
        NSMutableDictionary *group = groups[key];
        if (!group) {
            group = [@{@"key": key, @"target": target, @"label": label,
                       @"runs": [NSMutableArray array]} mutableCopy];
            groups[key] = group;
        }
        NSNumber *at = @(finished.longLongValue);
        NSMutableDictionary *run = [@{@"status": status, @"finished": at} mutableCopy];
        if (GDTHistoryNumber(started, 12) && started.longLongValue > 0 &&
            started.longLongValue <= finished.longLongValue) run[@"started"] = @(started.longLongValue);
        [group[@"runs"] addObject:run];
        if ([at compare:group[@"lastActivity"] ?: @-1] != NSOrderedAscending) {
            group[@"lastActivity"] = at;
            group[@"label"] = label;
            if (fields.count >= 12) {
                NSString *device = GDTHistoryText(fields[8]);
                if (device.length) group[@"device"] = device;
                if (GDTHistoryNumber(fields[9], 16)) group[@"bytes"] = @(fields[9].longLongValue);
                if ([@[@"yes", @"no"] containsObject:fields[10]]) group[@"solid"] = fields[10];
                NSString *bus = GDTHistoryText(fields[11]);
                if (bus.length) group[@"bus"] = bus;
            }
        }
    }
    // Lines rebuilt from old logs carry no volume UUID. Attach them to the
    // one identified disk whose volume has the same name; with two such
    // disks the name is ambiguous and they stay a separate row.
    for (NSString *key in groups.allKeys) {
        if (![key hasPrefix:@"apfs-name:"]) continue;
        NSMutableDictionary *named = groups[key];
        NSMutableDictionary *match = nil;
        NSUInteger matches = 0;
        for (NSMutableDictionary *candidate in groups.allValues) {
            if ([candidate[@"key"] hasPrefix:@"apfs:"] && [candidate[@"label"] isEqualToString:named[@"label"]]) {
                match = candidate;
                matches++;
            }
        }
        if (matches != 1) continue;
        [match[@"runs"] addObjectsFromArray:named[@"runs"]];
        [groups removeObjectForKey:key];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (NSMutableDictionary *group in groups.allValues) {
        NSArray *runs = [group[@"runs"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"finished"] compare:a[@"finished"]];
        }];
        NSMutableDictionary *entry = [group mutableCopy];
        entry[@"runs"] = [runs subarrayWithRange:NSMakeRange(0, MIN(runLimit, runs.count))];
        entry[@"lastActivity"] = [runs.firstObject objectForKey:@"finished"] ?: @0;
        NSNumber *lastSuccess = nil, *lastFailure = nil;
        for (NSDictionary *run in runs) {
            if (!lastSuccess && [run[@"status"] isEqual:@"success"]) lastSuccess = run[@"finished"];
            if (!lastFailure && [run[@"status"] isEqual:@"failure"]) lastFailure = run[@"finished"];
        }
        if (lastSuccess) entry[@"lastSuccess"] = lastSuccess;
        if (lastFailure && (!lastSuccess || [lastFailure compare:lastSuccess] == NSOrderedDescending)) {
            entry[@"lastFailure"] = lastFailure;
        }
        [result addObject:entry];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [b[@"lastActivity"] compare:a[@"lastActivity"]];
        return order != NSOrderedSame ? order : [a[@"key"] compare:b[@"key"]];
    }];
    return [result subarrayWithRange:NSMakeRange(0, MIN(maxGroups, result.count))];
}
