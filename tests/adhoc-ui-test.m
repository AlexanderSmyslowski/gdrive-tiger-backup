#import <Cocoa/Cocoa.h>
#import "TestApplicationSupport.h"
#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface AppDelegate (AdHocTestContract)
- (NSArray *)adHocDestinationsForConfigs:(NSArray *)configs descriptors:(NSArray *)descriptors;
@end

@interface AdHocTestDelegate : AppDelegate
@property(nonatomic, copy) NSArray *records;
@property(nonatomic, copy) NSArray *disks;
@property(nonatomic, copy) NSDictionary *launchEnvironment;
@property(nonatomic) NSUInteger launches;
@end
@implementation AdHocTestDelegate
- (BOOL)adHocEngineAvailable { return YES; }
- (NSArray *)adHocConfigRecords { return self.records; }
- (void)inspectAdHocVolumes:(void (^)(NSArray *))completion { completion(self.disks); }
- (void)refreshOverviewStatus:(id)sender { (void)sender; }
- (BOOL)launchBackupWithArgument:(NSString *)argument trigger:(NSString *)trigger
    assumeYes:(BOOL)assumeYes additionalEnvironment:(NSDictionary *)environment
    completion:(void (^)(NSInteger))completion {
    (void)completion;
    NSCAssert([argument isEqual:@"--run"] && [trigger isEqual:@"manual"] && assumeYes, @"explicit manual launch");
    self.launches++; self.launchEnvironment = environment; return YES;
}
@end

int main(void) {
    @autoreleasepool {
        GDTInitializeAccessoryTestApplication();
        AppDelegate *delegate = [AppDelegate new];
        delegate.language = @"de";
        if (![delegate respondsToSelector:@selector(adHocDestinationsForConfigs:descriptors:)]) {
            fprintf(stderr, "FAIL: main window cannot offer a one-run destination\n");
            return 1;
        }
        NSDictionary *config = @{@"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_URL": @"smb://nas.local/archive",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/archive",
            @"GDRIVE_BACKUP_VOLUME_UUID": @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/Old name",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Toshiba 4 TB"};
        NSDictionary *disk = @{@"volumeUUID": @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            @"path": @"/Volumes/GoogleDrive-Backup 1 1", @"name": @"GoogleDrive-Backup 1",
            @"diskID": @"disk4", @"isLocal": @YES, @"isInternal": @NO,
            @"isPhysical": @YES, @"isSystemImage": @NO, @"isWritable": @YES,
            @"filesystem": @"apfs", @"mediaName": @"TOSHIBA", @"connection": @"USB",
            @"sizeBytes": @4000000000000};
        NSArray *configs = @[@{@"config": config, @"configPath": @"/test/default.conf"}];
        NSArray *choices = [delegate adHocDestinationsForConfigs:configs descriptors:@[disk]];
        NSCAssert(choices.count == 2, @"NAS and saved external volume must both be offered");
        NSDictionary *external = choices[1];
        NSCAssert([external[@"available"] boolValue], @"renamed UUID remains usable");
        NSCAssert([external[@"path"] isEqual:disk[@"path"]], @"use current UUID mount");
        NSCAssert([external[@"label"] containsString:@"TOSHIBA"] &&
                  [external[@"label"] containsString:@"GoogleDrive-Backup 1"], @"show physical and logical identity");
        NSMutableDictionary *genericDisk = [disk mutableCopy];
        genericDisk[@"mediaName"] = @"EXTERNAL_USB";
        NSCAssert([[delegate adHocDestinationsForConfigs:configs descriptors:@[genericDisk]][1][@"label"] containsString:@"Toshiba 4 TB"],
            @"generic USB adapter names retain the user's saved disk label");
        NSArray *dedup = [delegate adHocDestinationsForConfigs:@[configs[0], configs[0]] descriptors:@[disk]];
        NSCAssert(dedup.count == 2, @"profiles sharing one volume do not duplicate choices");
        NSArray *missing = [delegate adHocDestinationsForConfigs:configs descriptors:@[]];
        NSCAssert(![missing[1][@"available"] boolValue], @"disconnected disk cannot start");
        NSMutableDictionary *wrong = [disk mutableCopy];
        wrong[@"volumeUUID"] = @"11111111-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
        NSCAssert(![[delegate adHocDestinationsForConfigs:configs descriptors:@[wrong]][1][@"available"] boolValue], @"same name with wrong UUID cannot start");
        NSMutableDictionary *duplicate = [disk mutableCopy];
        duplicate[@"path"] = @"/Volumes/Clone";
        NSArray *ambiguous = [delegate adHocDestinationsForConfigs:configs descriptors:@[disk, duplicate]];
        NSCAssert(![ambiguous[1][@"available"] boolValue], @"duplicate UUID fails closed");
        wrong = [disk mutableCopy]; wrong[@"isWritable"] = @NO;
        NSCAssert(![[delegate adHocDestinationsForConfigs:configs descriptors:@[wrong]][1][@"available"] boolValue], @"read-only disk cannot start");
        NSCAssert([config[@"GDRIVE_BACKUP_TARGET"] isEqual:@"nas"], @"building choices never changes automatic target");
        AdHocTestDelegate *runner = [AdHocTestDelegate new];
        runner.language = @"de"; runner.records = configs; runner.disks = @[disk];
        runner.adHocSelectedID = disk[@"volumeUUID"];
        [runner startAdHocBackup];
        NSCAssert(runner.launches == 1 && [runner.launchEnvironment[@"GDRIVE_BACKUP_RUN_TARGET"] isEqual:@"apfs"], @"selected external target reaches the engine");
        NSCAssert([runner.launchEnvironment[@"GDRIVE_BACKUP_CONFIG"] isEqual:@"/test/default.conf"], @"run uses saved source contract");
        NSCAssert([runner.launchEnvironment[@"GDRIVE_BACKUP_RUN_VOLUME_UUID"] isEqual:disk[@"volumeUUID"]], @"engine rechecks the selected identity after loading saved configuration");
        NSCAssert([runner.launchEnvironment[@"GDRIVE_BACKUP_SUMMARY_STATE_FILE"] containsString:@"/manual/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/"], @"external result cannot overwrite scheduled NAS status");
        NSCAssert([runner.launchEnvironment[@"BACKUP_PROGRESS_FOREGROUND"] isEqual:@"0"], @"main window owns manual progress");
        [runner startAdHocBackup];
        NSCAssert(runner.launches == 1, @"double click cannot start a second run");
        runner.overviewLaunchPending = NO; runner.disks = @[];
        [runner startAdHocBackup];
        NSCAssert(runner.launches == 1, @"unplug between selection and start blocks launch");
        runner.disks = @[disk];
        [runner startAdHocBackup];
        NSCAssert(runner.launches == 2, @"a second manual run reuses the exact existing target");
        TigerOverviewView *view = [[TigerOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 620, 520)];
        view.language = @"de";
        NSCAssert(view.destinationPopup && view.destinationPopup.accessibilityLabel.length,
            @"visible picker exposes a spoken label");
        NSCAssert(NSMaxY(view.progressDetailLabel.frame) < NSMinY(view.nextRunValueLabel.frame), @"progress does not overlap schedule");
        NSCAssert(NSMaxX(view.destinationPopup.frame) < NSMinX(view.backupButton.frame), @"destination picker does not overlap start button");
        NSCAssert(!GDTShouldDisplayManualRun(100, (@{@"started_at": @"200"}), @"failure", NO), @"newer scheduled failure replaces earlier manual success");
        NSCAssert(GDTShouldDisplayManualRun(200, (@{@"started_at": @"100"}), @"failure", NO), @"new manual result is visible alongside the automatic alert");
        NSCAssert(!GDTShouldDisplayManualRun(200, (@{@"started_at": @"100"}), @"running", YES), @"active automatic run retains foreground status");
        [runner applyOverviewSnapshot:@{@"status": @"success"} toView:view];
        NSCAssert(runner.overviewLaunchPending, @"a stale success snapshot cannot release the task-owned start guard");
        NSString *preview = NSProcessInfo.processInfo.environment[@"GDT_ADHOC_PREVIEW_PATH"];
        if (preview.length) {
            if ([NSProcessInfo.processInfo.environment[@"GDT_ADHOC_LIVE_READONLY"] isEqual:@"1"]) {
                delegate.profileStore = [[GDTProfileStore alloc] initWithConfigDirectory:
                    [NSHomeDirectory() stringByAppendingPathComponent:@".config/gdrive-tiger-backup"]];
                __block NSArray *liveDisks = nil;
                [delegate inspectAdHocVolumes:^(NSArray *result) { liveDisks = result; }];
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
                while (!liveDisks && deadline.timeIntervalSinceNow > 0) {
                    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                }
                NSCAssert(liveDisks != nil, @"read-only attached-disk inspection completed");
                choices = [delegate adHocDestinationsForConfigs:[delegate adHocConfigRecords] descriptors:liveDisks];
                NSCAssert(choices.count > 1, @"live picker offers more than the automatic target");
                NSUInteger availableExternal = 0;
                for (NSDictionary *choice in choices) {
                    if ([choice[@"kind"] isEqual:@"apfs"] && [choice[@"available"] boolValue]) availableExternal++;
                }
                NSCAssert(availableExternal > 0, @"attached registered external backup is available");
                printf("PASS: live read-only inspection offers %lu registered external target(s)\n", (unsigned long)availableExternal);
            }
            view.lastRunText = @"Sicherung abgeschlossen.";
            view.lastRunDetail = @"Heute, 12:05 · NAS";
            view.nextRunText = @"Heute, 20:00";
            view.targetText = @"NAS · wdmycloudex2100 · GoogleDrive-Backup";
            view.storageText = @"1,33 TB frei von 1,96 TB";
            view.status = @"success";
            for (NSDictionary *choice in choices) [view.destinationPopup addItemWithTitle:choice[@"label"]];
            [view.destinationPopup selectItemAtIndex:1];
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:preview atomically:YES];
        }
        puts("PASS: ad-hoc destination identity and availability");
    }
    return 0;
}
