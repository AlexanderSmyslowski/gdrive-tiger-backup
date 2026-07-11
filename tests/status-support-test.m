#import <Foundation/Foundation.h>

#import "BackupStatusSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSString *TemporaryPath(NSString *name) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"gdrive-%@-%@", name, NSUUID.UUID.UUIDString]];
}

static void TrashPath(NSString *path) {
    [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path]
                                resultingItemURL:nil
                                           error:nil];
}

int main(void) {
    @autoreleasepool {
        NSString *successPath = TemporaryPath(@"summary-success");
        [@"protocol=1\nstatus=success\npid=123\nstarted_at=100\nfinished_at=200\nexit_code=0\ntrigger=manual\ntarget=nas\ndestination=/Volumes/Archive\n"
            writeToFile:successPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(successPath) isEqualToString:@"success"],
               @"validated durable success is accepted");
        TrashPath(successPath);

        NSString *malformedPath = TemporaryPath(@"summary-malformed");
        [@"status=success\nexit_code=0\n"
            writeToFile:malformedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(malformedPath) isEqualToString:@"unknown"],
               @"malformed state never becomes success");
        TrashPath(malformedPath);
        Assert([GDTBackupSummaryStatusAtPath(TemporaryPath(@"missing")) isEqualToString:@"unknown"],
               @"missing state is explicitly unknown");

        NSString *orphanPath = TemporaryPath(@"summary-orphan");
        [@"protocol=1\nstatus=running\npid=99999999\nstarted_at=100\ntrigger=schedule\ntarget=apfs\ndestination=/Volumes/Archive\n"
            writeToFile:orphanPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(orphanPath) isEqualToString:@"interrupted"],
               @"a dead running process is reported as interrupted");
        TrashPath(orphanPath);

        NSDictionary *defaultAPFS = @{};
        Assert([GDTBackupDestinationForConfig(defaultAPFS) isEqualToString:@"/Volumes/GoogleDrive-Backup"],
               @"default APFS destination matches the backup engine");

        NSDictionary *nasConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Archive",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_NAS_URL": @"smb://private-user@example.invalid/Archive"
        };
        NSString *nasDestination = GDTBackupDestinationForConfig(nasConfig);
        Assert([nasDestination isEqualToString:@"/Volumes/Archive/GoogleDrive-Backup"] &&
               [nasDestination rangeOfString:@"private-user"].location == NSNotFound,
               @"NAS destination uses only the local mount path and never URL credentials");
        Assert([GDTBackupCapacityPathForConfig(nasConfig) isEqualToString:@"/Volumes/Archive"],
               @"NAS capacity is measured at the mount instead of a missing subfolder");

        NSDictionary *overrideConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_DEST_ROOT": @"/Volumes/Archive/Custom"
        };
        Assert([GDTBackupDestinationForConfig(overrideConfig) isEqualToString:@"/Volumes/Archive/Custom"],
               @"explicit destination override remains authoritative");

        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:2 * 60 * 60];
        NSDateComponents *beforeComponents = [[NSDateComponents alloc] init];
        beforeComponents.year = 2026;
        beforeComponents.month = 7;
        beforeComponents.day = 11;
        beforeComponents.hour = 19;
        beforeComponents.minute = 30;
        NSDate *before = [calendar dateFromComponents:beforeComponents];
        NSDate *beforeNext = GDTNextDailyRunAfterDate(before, calendar);
        NSDateComponents *beforeNextParts = [calendar components:(NSCalendarUnitDay | NSCalendarUnitHour)
                                                        fromDate:beforeNext];
        Assert(beforeNextParts.day == 11 && beforeNextParts.hour == 20,
               @"daily schedule points to today before 20:00");

        NSDateComponents *afterComponents = [beforeComponents copy];
        afterComponents.hour = 20;
        afterComponents.minute = 1;
        NSDate *after = [calendar dateFromComponents:afterComponents];
        NSDate *afterNext = GDTNextDailyRunAfterDate(after, calendar);
        NSDateComponents *afterNextParts = [calendar components:(NSCalendarUnitDay | NSCalendarUnitHour)
                                                       fromDate:afterNext];
        Assert(afterNextParts.day == 12 && afterNextParts.hour == 20,
               @"daily schedule rolls to tomorrow after 20:00");

        NSString *storagePath = TemporaryPath(@"storage");
        [NSFileManager.defaultManager createDirectoryAtPath:storagePath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        NSDictionary<NSString *, NSNumber *> *capacity = GDTStorageCapacityForPath(storagePath);
        Assert(capacity[@"totalBytes"].unsignedLongLongValue > 0 &&
               capacity[@"freeBytes"].unsignedLongLongValue > 0,
               @"mounted destination exposes free and total capacity");
        TrashPath(storagePath);
        Assert(GDTStorageCapacityForPath(TemporaryPath(@"missing-storage")) == nil,
               @"unavailable destination has no fabricated capacity");

        Assert([GDTBackupSummaryPath() hasSuffix:@"Library/Application Support/GDrive Backup Tiger/last-run.status"],
               @"default durable summary lives in private Application Support");
    }

    if (failures > 0) {
        printf("%d status support test(s) failed.\n", failures);
        return 1;
    }
    printf("All status support tests passed.\n");
    return 0;
}
