// Included inside AppDelegate: ad-hoc choices never activate a profile because
// profile activation also replaces the user's automatic schedule.
- (NSArray *)adHocDestinationsForConfigs:(NSArray *)records descriptors:(NSArray *)descriptors {
    NSMutableArray *choices = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *record in records) {
        NSDictionary *config = record[@"config"];
        BOOL nas = [config[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"nas"];
        if (nas) {
            NSString *identity = [NSString stringWithFormat:@"nas:%@:%@",
                config[@"GDRIVE_BACKUP_NAS_URL"] ?: config[@"GDRIVE_BACKUP_NAS_MOUNT"] ?: @"",
                config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup"];
            if (![seen containsObject:identity]) {
                [seen addObject:identity];
                [choices addObject:@{@"id": identity, @"kind": @"nas", @"config": config,
                    @"configPath": record[@"configPath"] ?: @"",
                    @"label": GDTBackupTargetOverviewText(config, self.language),
                    @"available": @YES}];
            }
        }
        NSString *uuid = [config[@"GDRIVE_BACKUP_VOLUME_UUID"] uppercaseString];
        if (![[NSUUID alloc] initWithUUIDString:uuid] || [seen containsObject:uuid]) continue;
        [seen addObject:uuid];
        // Prefer the external profile's encryption and source settings when
        // the automatic NAS profile retains the same external identity.
        NSDictionary *source = record;
        for (NSDictionary *candidate in records) {
            NSDictionary *other = candidate[@"config"];
            if ([[other[@"GDRIVE_BACKUP_VOLUME_UUID"] uppercaseString] isEqual:uuid] &&
                [other[@"GDRIVE_BACKUP_TARGET"] isEqual:@"apfs"]) { source = candidate; break; }
        }
        NSMutableArray *matches = [NSMutableArray array];
        for (NSDictionary *disk in descriptors) {
            if ([[disk[@"volumeUUID"] uppercaseString] isEqual:uuid]) [matches addObject:disk];
        }
        NSDictionary *disk = matches.count == 1 ? matches.firstObject : nil;
        BOOL available = disk && [self isWritableExternalAPFSDescriptor:disk];
        NSDictionary *sourceConfig = source[@"config"];
        NSString *physical = GDTSafeDestinationLabelComponent(disk[@"mediaName"]);
        // USB bridges often hide the actual disk model behind a generic name.
        // The saved label remains tied to the verified UUID, not the mount path.
        NSSet *genericNames = [NSSet setWithArray:@[@"EXTERNAL_USB", @"EXTERNAL", @"USB", @"USB DISK", @"EXTERNAL MEDIA"]];
        if ([genericNames containsObject:physical.uppercaseString]) physical = @"";
        if (!physical.length) physical = GDTSafeDestinationLabelComponent(sourceConfig[@"GDRIVE_BACKUP_PROFILE_NAME"]);
        if (!physical.length) physical = T(self.language, @"externalVolume");
        NSMutableArray *parts = [NSMutableArray arrayWithObject:physical];
        if ([disk[@"sizeBytes"] longLongValue] > 0) {
            [parts addObject:[NSByteCountFormatter stringFromByteCount:[disk[@"sizeBytes"] longLongValue]
                countStyle:NSByteCountFormatterCountStyleDecimal]];
        }
        NSString *connection = GDTSafeDestinationLabelComponent(disk[@"connection"]);
        if (connection.length) [parts addObject:connection];
        NSString *name = GDTSafeDestinationLabelComponent(disk[@"name"]);
        if (!name.length) name = [sourceConfig[@"GDRIVE_BACKUP_VOLUME"] lastPathComponent] ?: @"";
        [parts addObject:[NSString stringWithFormat:@"%@: %@", GDTAdHocText(self.language, @"volume"), name]];
        NSString *problem = matches.count == 0 ? @"missing" : @"unsafe";
        if (!available) [parts addObject:GDTAdHocText(self.language, problem)];
        [choices addObject:@{@"id": uuid, @"volumeUUID": uuid, @"kind": @"apfs",
            @"config": sourceConfig, @"configPath": source[@"configPath"] ?: @"",
            @"path": disk[@"path"] ?: @"", @"label": [parts componentsJoinedByString:@" · "],
            @"available": @(available)}];
    }
    return choices;
}

- (NSArray *)adHocConfigRecords {
    NSMutableArray *records = [NSMutableArray array];
    NSString *activePath = self.profileStore.activeConfigPath ?: GDTConfigPath();
    [records addObject:@{@"config": [self savedSetupConfig] ?: @{}, @"configPath": activePath ?: @""}];
    for (NSDictionary *profile in self.profileStore.profiles) {
        NSString *path = profile[@"configPath"];
        if (![path isEqual:activePath]) [records addObject:@{@"config": GDTReadConfigDictionaryAtPath(path), @"configPath": path}];
    }
    return records;
}

- (void)refreshAdHocPicker {
    if (![self.window.contentView isKindOfClass:TigerOverviewView.class]) return;
    TigerOverviewView *view = (TigerOverviewView *)self.window.contentView;
    self.adHocChoices = [self adHocDestinationsForConfigs:[self adHocConfigRecords]
        descriptors:self.mountedExternalVolumeDescriptorsByPath.allValues ?: @[]];
    if (!self.adHocSelectedID.length) self.adHocSelectedID = self.adHocChoices.firstObject[@"id"];
    [view.destinationPopup removeAllItems];
    NSDictionary *selected = nil;
    for (NSDictionary *choice in self.adHocChoices) {
        [view.destinationPopup addItemWithTitle:choice[@"label"]];
        NSMenuItem *item = view.destinationPopup.lastItem;
        item.representedObject = choice;
        item.enabled = [choice[@"available"] boolValue];
        if ([choice[@"id"] isEqual:self.adHocSelectedID]) {
            [view.destinationPopup selectItem:item]; selected = choice;
        }
    }
    [view.destinationPopup.menu addItem:NSMenuItem.separatorItem];
    [view.destinationPopup addItemWithTitle:GDTAdHocText(self.language, @"add")];
    view.destinationPopup.lastItem.representedObject = @{@"add": @YES};
    view.destinationPopup.lastItem.enabled = YES;
    BOOL busy = self.overviewLaunchPending || self.adHocInspectionPending ||
        [self.lastOverviewSnapshot[@"status"] isEqual:@"running"];
    view.destinationPopup.enabled = !busy;
    view.backupButton.enabled = !busy && [selected[@"available"] boolValue];
    view.destinationPopup.toolTip = selected[@"label"];
    view.destinationPopup.accessibilityValue = selected[@"label"] ?: @"";
    if (self.adHocInspectionPending) view.destinationHint.stringValue = GDTAdHocText(self.language, @"checking");
    else if (busy && self.adHocRunChoice) view.destinationHint.stringValue = [NSString stringWithFormat:
        GDTAdHocText(self.language, @"on"), self.adHocRunChoice[@"label"]];
    else view.destinationHint.stringValue = GDTAdHocText(self.language,
        selected && [selected[@"available"] boolValue] ? @"once" : @"unavailable");
    view.destinationHint.toolTip = view.destinationHint.stringValue;
}

- (void)adHocDestinationChanged {
    TigerOverviewView *view = (TigerOverviewView *)self.window.contentView;
    NSDictionary *choice = view.destinationPopup.selectedItem.representedObject;
    if ([choice[@"add"] boolValue]) { [self showAdHocDestinationSheet]; return; }
    self.adHocSelectedID = choice[@"id"];
    [self refreshAdHocPicker];
}

- (void)inspectAdHocVolumes:(void (^)(NSArray *))completion {
    NSArray *paths = [self mountedVolumePathsForUnknownExternalVolumeRevalidation];
    if (!paths.count) { completion(@[]); return; }
    NSMutableArray *descriptors = [NSMutableArray array];
    __block NSUInteger remaining = paths.count;
    for (NSString *path in paths) {
        [self inspectMountedVolumeAtPath:path completion:^(NSDictionary *disk) {
            if (disk) [descriptors addObject:disk];
            if (--remaining == 0) completion(descriptors);
        }];
    }
}

- (void)showAdHocDestinationSheet {
    [self refreshAdHocPicker];
    self.adHocInspectionPending = YES;
    [self refreshAdHocPicker];
    [self inspectAdHocVolumes:^(NSArray *disks) {
        self.adHocInspectionPending = NO;
        NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 460, 30)];
        [picker addItemWithTitle:GDTAdHocText(self.language, @"choose")];
        NSSet *known = [self configuredExternalVolumeUUIDs];
        for (NSDictionary *disk in disks) {
            if (![self isWritableExternalAPFSDescriptor:disk] || [known containsObject:disk[@"volumeUUID"]]) continue;
            NSUInteger matches = 0;
            for (NSDictionary *other in disks) if ([other[@"volumeUUID"] isEqual:disk[@"volumeUUID"]]) matches++;
            if (matches != 1) continue;
            [picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@", disk[@"mediaName"] ?: disk[@"diskID"], disk[@"name"]]];
            picker.lastItem.representedObject = disk;
        }
        NSAlert *alert = [NSAlert new];
        alert.messageText = GDTAdHocText(self.language, @"adding");
        BOOL hasCandidates = picker.numberOfItems > 1;
        alert.informativeText = GDTAdHocText(self.language, hasCandidates ? @"addDetail" : @"none");
        GDTExplicitPopUpChoiceController *selection = [GDTExplicitPopUpChoiceController new];
        if (hasCandidates) {
            alert.accessoryView = picker;
            [alert addButtonWithTitle:GDTAdHocText(self.language, @"save")];
            selection.popup = picker;
            selection.confirmationButton = alert.buttons.firstObject;
            selection.confirmationButton.enabled = NO;
            picker.target = selection;
            picker.action = @selector(choiceDidChange:);
        }
        [alert addButtonWithTitle:T(self.language, @"notNow")];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (hasCandidates && selection.hasExplicitSelection && response == NSAlertFirstButtonReturn) {
                NSDictionary *disk = picker.selectedItem.representedObject;
                [self inspectAdHocVolumes:^(NSArray *current) {
                    NSArray *matching = [current filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                        (void)bindings; return [item[@"volumeUUID"] isEqual:disk[@"volumeUUID"]];
                    }]];
                    if (matching.count != 1 || ![self isWritableExternalAPFSDescriptor:matching.firstObject]) {
                        [self refreshAdHocPicker]; return;
                    }
                    NSDictionary *live = matching.firstObject;
                    NSMutableDictionary *config = [[self savedSetupConfig] mutableCopy];
                    // The new local destination must not inherit a network crypt
                    // remote or an absolute destination from another profile.
                    for (NSString *key in @[@"GDRIVE_BACKUP_DEST_ROOT", @"GDRIVE_BACKUP_CRYPT_REMOTE",
                            @"GDRIVE_BACKUP_SUMMARY_STATE_FILE", @"GDRIVE_BACKUP_PROGRESS_STATE_FILE"]) [config removeObjectForKey:key];
                    config[@"GDRIVE_BACKUP_TARGET"] = @"apfs";
                    config[@"GDRIVE_BACKUP_ENCRYPTION"] = @"none";
                    config[@"GDRIVE_BACKUP_VOLUME_UUID"] = live[@"volumeUUID"];
                    config[@"GDRIVE_BACKUP_VOLUME"] = live[@"path"];
                    config[@"GDRIVE_BACKUP_VOLUME_NAME"] = live[@"name"];
                    config[@"GDRIVE_BACKUP_SCHEDULE"] = @"manual";
                    config[@"GDRIVE_BACKUP_AUTO_CREATE_VOLUME"] = @"0";
                    NSError *error = nil;
                    NSDictionary *created = [self.profileStore createProfileNamed:live[@"name"] copyingConfig:config error:&error];
                    if (created) {
                        self.adHocSelectedID = live[@"volumeUUID"];
                        self.mountedExternalVolumeDescriptorsByPath[live[@"path"]] = live;
                    } else {
                        NSAlert *failure = [NSAlert new];
                        failure.messageText = error.localizedDescription ?: GDTAdHocText(self.language, @"unavailable");
                        [failure beginSheetModalForWindow:self.window completionHandler:nil];
                    }
                    [self refreshAdHocPicker];
                }];
            }
            [self refreshAdHocPicker];
        }];
    }];
}

- (BOOL)adHocEngineAvailable {
    int status = 0;
    NSString *capabilities = RunCommand(@"/bin/bash", @[@"/usr/local/bin/backup-google-drive.sh", @"--capabilities"],
        @{@"GDRIVE_BACKUP_CONFIG": @"/dev/null", @"MOUNT_SETTLE_SECONDS": @"0"}, &status);
    return status == 0 && [[capabilities componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
        containsObject:@"adhoc-target-v1"];
}

- (void)startAdHocBackup {
    if (self.overviewLaunchPending || self.adHocInspectionPending ||
        [self.lastOverviewSnapshot[@"status"] isEqual:@"running"]) return;
    if (![self adHocEngineAvailable]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = GDTAdHocText(self.language, @"engine");
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    NSString *selectedID = [self.adHocSelectedID copy];
    self.adHocInspectionPending = YES;
    [self refreshAdHocPicker];
    [self inspectAdHocVolumes:^(NSArray *disks) {
        self.adHocInspectionPending = NO;
        self.mountedExternalVolumeDescriptorsByPath = [NSMutableDictionary dictionary];
        for (NSDictionary *disk in disks) self.mountedExternalVolumeDescriptorsByPath[disk[@"path"]] = disk;
        NSArray *choices = [self adHocDestinationsForConfigs:[self adHocConfigRecords] descriptors:disks];
        NSDictionary *selected = nil;
        for (NSDictionary *choice in choices) if ([choice[@"id"] isEqual:selectedID]) selected = choice;
        if (!selected || ![selected[@"available"] boolValue] || [self.lastOverviewSnapshot[@"status"] isEqual:@"running"]) {
            [self refreshAdHocPicker]; return;
        }
        NSDictionary *config = selected[@"config"];
        NSString *suffix = [selected[@"kind"] isEqual:@"apfs"] ? selected[@"volumeUUID"] :
            config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
        self.adHocSummaryPath = [NSHomeDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"Library/Application Support/GDrive Backup Tiger/manual/%@/last-run.status", suffix]];
        self.adHocRunChoice = selected;
        self.adHocGeneration++;
        self.adHocRunStartedAt = floor(NSDate.date.timeIntervalSince1970);
        self.overviewLaunchPending = YES;
        [self refreshAdHocPicker];
        NSMutableDictionary *environment = [@{@"GDRIVE_BACKUP_CONFIG": selected[@"configPath"],
            @"GDRIVE_BACKUP_RUN_TARGET": selected[@"kind"],
            @"GDRIVE_BACKUP_SUMMARY_STATE_FILE": self.adHocSummaryPath,
            @"GDRIVE_BACKUP_PROGRESS_STATE_FILE": GDTBackupProgressPathForSummaryPath(self.adHocSummaryPath),
            @"BACKUP_PROGRESS_FOREGROUND": @"0"} mutableCopy];
        if ([selected[@"kind"] isEqual:@"apfs"]) environment[@"GDRIVE_BACKUP_RUN_VOLUME_UUID"] = selected[@"volumeUUID"];
        BOOL launched = [self launchBackupWithArgument:@"--run" trigger:@"manual" assumeYes:YES
            additionalEnvironment:environment completion:^(NSInteger status) {
                (void)status; self.overviewLaunchPending = NO;
                self.adHocGeneration++;
                [self refreshOverviewStatus:nil];
            }];
        if (!launched) { self.overviewLaunchPending = NO; self.adHocRunChoice = nil; }
        [self refreshOverviewStatus:nil];
    }];
}
