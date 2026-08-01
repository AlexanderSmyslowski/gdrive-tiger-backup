#import <Foundation/Foundation.h>

#import "OnboardingSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
    } else {
        printf("not ok - %s\n", name.UTF8String);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSDictionary *nasConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"0",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Archive",
            @"GDRIVE_BACKUP_NAS_URL": @"smb://nas.local/archive",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/Toshiba_4TB",
            @"GDRIVE_BACKUP_VOLUME_NAME": @"Toshiba_4TB",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"USB-UUID"
        };
        NSDictionary *nasUpdates =
            GDTOnboardingConfigurationUpdates(nasConfig, @"nas");
        Assert([nasUpdates[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"nas"] &&
               [nasUpdates[@"GDRIVE_BACKUP_SCHEDULE"] isEqualToString:@"daily"] &&
               [nasUpdates[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"1"],
               @"NAS can be selected as the one automatic primary destination");
        Assert([nasUpdates[@"GDRIVE_BACKUP_NAS_MOUNT"]
                   isEqualToString:@"/Volumes/Archive"] &&
               [nasUpdates[@"GDRIVE_BACKUP_VOLUME_UUID"]
                   isEqualToString:@"USB-UUID"],
               @"an optional external disk identity survives selecting NAS as primary");

        NSDictionary *externalUpdates =
            GDTOnboardingConfigurationUpdates(nasConfig, @"apfs");
        Assert([externalUpdates[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"apfs"] &&
               [externalUpdates[@"GDRIVE_BACKUP_VOLUME"]
                   isEqualToString:@"/Volumes/Toshiba_4TB"],
               @"an external disk can be selected as the automatic primary destination");
        Assert(!externalUpdates[@"GDRIVE_BACKUP_SECOND_SCHEDULE"],
               @"the two-role model never creates a second schedule");
    }
    return failures == 0 ? 0 : 1;
}

