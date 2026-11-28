// Included inside AppDelegate: guides the user through creating an own Google
// OAuth Desktop client, because rclone's shared client is being retired and
// Google offers no API for creating Desktop clients. The app opens each
// console page, picks the downloaded client file up from Downloads, keeps a
// private copy and connects the remote; no secret is typed or pasted.

static NSString *const GDTGoogleClientStoreName = @"google-oauth-client.json";

- (NSArray<NSString *> *)googleClientSetupURLs {
    return @[
        @"https://console.cloud.google.com/projectcreate",
        @"https://console.cloud.google.com/apis/library/drive.googleapis.com",
        @"https://console.cloud.google.com/auth/overview",
        @"https://console.cloud.google.com/auth/audience",
        @"https://console.cloud.google.com/auth/clients/create"
    ];
}

- (void)showGoogleClientAssistant {
    if (self.googleClientWindow) {
        [self.googleClientWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    NSString *language = self.language ?: @"en";
    const CGFloat width = 580, margin = 20, stepHeight = 58;
    NSArray<NSString *> *urls = [self googleClientSetupURLs];
    const CGFloat height = 196 + stepHeight * urls.count;

    // No close button: Cancel is the single way out, so the Downloads poll
    // always stops together with the window.
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = T(language, @"googleClientTitle");
    window.releasedWhenClosed = NO;
    NSView *content = window.contentView;
    __block CGFloat top = margin;
    NSTextField *(^addLabel)(NSString *, CGFloat, CGFloat, CGFloat, BOOL) =
        ^NSTextField *(NSString *text, CGFloat x, CGFloat labelWidth, CGFloat labelHeight, BOOL bold) {
            NSTextField *label = [NSTextField wrappingLabelWithString:text];
            label.font = bold ? [NSFont boldSystemFontOfSize:14] : [NSFont systemFontOfSize:12];
            label.frame = NSMakeRect(x, height - top - labelHeight, labelWidth, labelHeight);
            label.selectable = NO;
            [content addSubview:label];
            return label;
        };

    addLabel(T(language, @"googleClientTitle"), margin, width - 2 * margin, 20, YES);
    top += 26;
    addLabel(T(language, @"googleClientIntro"), margin, width - 2 * margin, 48, NO);
    top += 58;

    for (NSUInteger index = 0; index < urls.count; index++) {
        NSString *stepKey = [NSString stringWithFormat:@"googleClientStep%lu", (unsigned long)index + 1];
        addLabel([NSString stringWithFormat:@"%lu.", (unsigned long)index + 1], margin, 22, 18, YES);
        addLabel(T(language, stepKey), margin + 24, width - 2 * margin - 24 - 104, stepHeight - 8, NO);
        NSButton *open = [NSButton buttonWithTitle:T(language, @"googleClientOpen")
                                            target:self
                                            action:@selector(openGoogleClientStep:)];
        open.tag = (NSInteger)index;
        open.frame = NSMakeRect(width - margin - 96, height - top - 26, 96, 26);
        open.accessibilityLabel = [NSString stringWithFormat:@"%lu. %@",
            (unsigned long)index + 1, T(language, @"googleClientOpen")];
        [content addSubview:open];
        top += stepHeight;
    }

    top += 6;
    self.googleClientStatusField = addLabel(T(language, @"googleClientWaiting"),
                                            margin, width - 2 * margin, 34, NO);
    top += 44;
    NSButton *choose = [NSButton buttonWithTitle:T(language, @"googleClientChooseFile")
                                          target:self
                                          action:@selector(chooseGoogleClientFile:)];
    choose.frame = NSMakeRect(margin, height - top - 28, 180, 28);
    [content addSubview:choose];
    NSButton *cancel = [NSButton buttonWithTitle:T(language, @"googleClientCancel")
                                          target:self
                                          action:@selector(cancelGoogleClientAssistant:)];
    cancel.keyEquivalent = @"\033";
    cancel.frame = NSMakeRect(width - margin - 120, height - top - 28, 120, 28);
    [content addSubview:cancel];

    self.googleClientWindow = window;
    // Only files downloaded from now on count; an old client file in
    // Downloads must never be picked up silently.
    self.googleClientStartedAt = [NSDate dateWithTimeIntervalSinceNow:-2];
    self.googleClientRejectedPath = nil;
    self.googleClientTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                              target:self
                                                            selector:@selector(pollGoogleClientDownloads:)
                                                            userInfo:nil
                                                             repeats:YES];
    if (self.setupWindow) {
        NSRect parent = self.setupWindow.frame;
        [window setFrameOrigin:NSMakePoint(NSMidX(parent) - width / 2,
                                           NSMaxY(parent) - height - 60)];
    } else {
        [window center];
    }
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openGoogleClientStep:(NSButton *)sender {
    NSArray<NSString *> *urls = [self googleClientSetupURLs];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= urls.count) return;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:urls[(NSUInteger)sender.tag]]];
}

- (void)closeGoogleClientAssistant {
    [self.googleClientTimer invalidate];
    self.googleClientTimer = nil;
    [self.googleClientWindow orderOut:nil];
    [self.googleClientWindow close];
    self.googleClientWindow = nil;
    self.googleClientStatusField = nil;
}

- (void)cancelGoogleClientAssistant:(id)sender {
    (void)sender;
    [self closeGoogleClientAssistant];
}

- (void)pollGoogleClientDownloads:(NSTimer *)timer {
    (void)timer;
    NSString *downloads = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    NSString *path = GDTNewestGoogleOAuthClientFile(downloads, self.googleClientStartedAt,
                                                    NSFileManager.defaultManager);
    if (!path.length || [path isEqualToString:self.googleClientRejectedPath]) return;
    [self acceptGoogleClientFileAtPath:path moveToTrash:YES];
}

- (void)chooseGoogleClientFile:(id)sender {
    (void)sender;
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.directoryURL = [NSURL fileURLWithPath:
        [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]];
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.googleClientWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL.path.length) {
            [weakSelf acceptGoogleClientFileAtPath:panel.URL.path moveToTrash:NO];
        }
    }];
}

- (void)acceptGoogleClientFileAtPath:(NSString *)path moveToTrash:(BOOL)moveToTrash {
    NSString *language = self.language ?: @"en";
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSData *data = attributes.fileSize <= 64 * 1024 ? [NSData dataWithContentsOfFile:path] : nil;
    NSString *reason = nil;
    NSDictionary<NSString *, NSString *> *client =
        GDTGoogleOAuthClientFromJSONData(data ?: NSData.data, &reason);
    if (!client) {
        self.googleClientRejectedPath = path;
        self.googleClientStatusField.stringValue = T(language,
            [reason isEqualToString:@"notDesktop"] ? @"googleClientWrongType" : @"googleClientInvalid");
        return;
    }

    // Google shows a client secret only once, so keep a private copy; the
    // download itself goes to the Trash instead of lingering in Downloads.
    NSString *supportDirectory = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/GDrive Backup Tiger"];
    [NSFileManager.defaultManager createDirectoryAtPath:supportDirectory
                            withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700}
                                                  error:nil];
    NSString *storePath = [supportDirectory stringByAppendingPathComponent:GDTGoogleClientStoreName];
    BOOL stored = [data writeToFile:storePath options:NSDataWritingAtomic error:nil] &&
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                       ofItemAtPath:storePath
                                              error:nil];
    if (!stored) {
        self.googleClientRejectedPath = path;
        self.googleClientStatusField.stringValue = T(language, @"setupConnectFailed");
        return;
    }
    if (moveToTrash) {
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path]
                                    resultingItemURL:nil
                                               error:nil];
    }
    [self closeGoogleClientAssistant];
    [self connectGoogleDriveWithOwnClient:client];
}

- (void)connectGoogleDriveWithOwnClient:(NSDictionary<NSString *, NSString *> *)client {
    if (self.googleDriveConnectInFlight) return;
    if (!self.setupHealthChecker) {
        self.setupHealthChecker = [GDTSetupHealthChecker productionChecker];
    }
    GDTSetupHealthChecker *checker = self.setupHealthChecker;
    checker.backupLockPath = [self automaticRetryLockPath];
    self.googleDriveConnectInFlight = YES;
    self.setupHealthView.actionButton.enabled = NO;
    self.statusField.stringValue = T(self.language ?: @"en", @"googleClientSigningIn");
    NSMutableDictionary<NSString *, NSString *> *config = [[self savedSetupConfig] mutableCopy];
    [config addEntriesFromDictionary:[self currentSetupUpdates]];
    NSString *clientID = client[@"clientID"];
    NSString *clientSecret = client[@"clientSecret"];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, id> *result = [checker connectGoogleDriveForConfig:config
                                                                           clientID:clientID
                                                                       clientSecret:clientSecret];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.googleDriveConnectInFlight = NO;
            strongSelf.setupHealthView.actionButton.enabled = YES;
            NSString *reason = result[@"reason"];
            NSString *key = [reason isEqualToString:@"connected"] ? @"setupConnectDone"
                : [reason isEqualToString:@"backupRunning"] ? @"googleClientBackupRunning"
                : @"setupConnectFailed";
            strongSelf.statusField.stringValue = T(strongSelf.language ?: @"en", key);
            // A re-check would replace the "backup running" hint at once;
            // the remote is unchanged in that case anyway.
            if (![reason isEqualToString:@"backupRunning"]) {
                [strongSelf runSetupHealthCheck:nil];
            }
        });
    });
}
