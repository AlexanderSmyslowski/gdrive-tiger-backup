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

NSString *GDTBackupSummaryStatusAtPath(NSString *path) {
    NSDictionary<NSString *, NSString *> *values = GDTReadBackupSummaryAtPath(path);
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
