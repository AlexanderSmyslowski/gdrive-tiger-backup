#import <Cocoa/Cocoa.h>
#include <unistd.h>

static NSImage *CreateApplicationIcon(void) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(128, 128)];
    [image lockFocus];

    NSRect bounds = NSMakeRect(0, 0, 128, 128);
    NSBezierPath *base = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 8, 8) xRadius:24 yRadius:24];
    NSGradient *baseGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.62 green:0.88 blue:1.0 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.06 green:0.33 blue:0.83 alpha:1.0]
    ]];
    [baseGradient drawInBezierPath:base angle:-90];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.28] setFill];
    for (CGFloat y = 20; y < 112; y += 7) {
        NSRectFill(NSMakeRect(14, y, 100, 1));
    }

    NSBezierPath *drive = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(25, 34, 78, 52) xRadius:12 yRadius:12];
    NSGradient *driveGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.98 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.58 alpha:1.0]
    ]];
    [driveGradient drawInBezierPath:drive angle:-90];
    [[NSColor colorWithCalibratedWhite:0.20 alpha:0.45] setStroke];
    drive.lineWidth = 2;
    [drive stroke];

    NSBezierPath *slot = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(39, 62, 50, 9) xRadius:4 yRadius:4];
    [[NSColor colorWithCalibratedRed:0.10 green:0.30 blue:0.58 alpha:0.86] setFill];
    [slot fill];

    NSBezierPath *light = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(82, 44, 10, 10)];
    [[NSColor colorWithCalibratedRed:0.45 green:1.0 blue:0.30 alpha:1.0] setFill];
    [light fill];

    NSBezierPath *check = [NSBezierPath bezierPath];
    [check moveToPoint:NSMakePoint(42, 44)];
    [check lineToPoint:NSMakePoint(57, 28)];
    [check lineToPoint:NSMakePoint(90, 76)];
    [[NSColor colorWithCalibratedRed:1.0 green:0.93 blue:0.20 alpha:1.0] setStroke];
    check.lineWidth = 9;
    check.lineCapStyle = NSLineCapStyleRound;
    check.lineJoinStyle = NSLineJoinStyleRound;
    [check stroke];

    [image unlockFocus];
    return image;
}

static NSString *TrimConfigValue(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length >= 2) {
        unichar first = [trimmed characterAtIndex:0];
        unichar last = [trimmed characterAtIndex:trimmed.length - 1];
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        }
    }
    return trimmed;
}

static NSString *ConfiguredLanguage(void) {
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/gdrive-tiger-backup/config"];
    NSString *config = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if ([line hasPrefix:@"GDRIVE_BACKUP_LANG="]) {
            NSString *value = TrimConfigValue([line substringFromIndex:[@"GDRIVE_BACKUP_LANG=" length]]).lowercaseString;
            NSArray<NSString *> *supported = @[@"de", @"en", @"fr", @"es", @"ja", @"yue", @"ko"];
            for (NSString *code in supported) {
                if ([value isEqualToString:code] || [value hasPrefix:[code stringByAppendingString:@"-"]] || [value hasPrefix:[code stringByAppendingString:@"_"]]) {
                    return code;
                }
            }
            if ([value hasPrefix:@"zh-hk"] || [value hasPrefix:@"zh_hk"] || [value hasPrefix:@"zh-hant-hk"] || [value hasPrefix:@"zh_hant_hk"] || [value hasPrefix:@"zh-mo"] || [value hasPrefix:@"zh_mo"]) {
                return @"yue";
            }
        }
    }

    NSString *preferred = NSLocale.preferredLanguages.firstObject.lowercaseString;
    if ([preferred hasPrefix:@"de"]) return @"de";
    if ([preferred hasPrefix:@"fr"]) return @"fr";
    if ([preferred hasPrefix:@"es"]) return @"es";
    if ([preferred hasPrefix:@"ja"]) return @"ja";
    if ([preferred hasPrefix:@"ko"]) return @"ko";
    if ([preferred hasPrefix:@"yue"] || [preferred hasPrefix:@"zh-hk"] || [preferred hasPrefix:@"zh_hk"] || [preferred hasPrefix:@"zh-hant-hk"] || [preferred hasPrefix:@"zh_hant_hk"] || [preferred hasPrefix:@"zh-mo"] || [preferred hasPrefix:@"zh_mo"]) return @"yue";
    return @"en";
}

static NSString *T(NSString *language, NSString *key) {
    NSDictionary<NSString *, NSString *> *de = @{
        @"confirmTarget": @"Dieses Volume verwenden?",
        @"startBackup": @"Backup starten",
        @"notNow": @"Nicht jetzt",
        @"running": @"Sicherung wird erstellt ...",
        @"completed": @"Sicherung abgeschlossen.",
        @"runningHint": @"Bitte Festplatte nicht auswerfen.",
        @"completedHint": @"Backup ist fertig.",
        @"setupTitle": @"Backup-Ziel und Startmodus",
        @"targetType": @"Zieltyp",
        @"externalVolume": @"Externe Platte",
        @"nas": @"NAS / Netzwerk",
        @"mountedNas": @"Gemountete NAS",
        @"refresh": @"Aktualisieren",
        @"discover": @"Suchen",
        @"openFinder": @"Im Finder öffnen",
        @"nasUrl": @"NAS-URL",
        @"nasMount": @"Mountpunkt",
        @"nasSubdir": @"Zielordner",
        @"schedule": @"Starten",
        @"scheduleManual": @"Nur manuell",
        @"scheduleLogin": @"Beim Login",
        @"scheduleHourly": @"Stündlich",
        @"scheduleDaily": @"Täglich 20:00",
        @"save": @"Speichern",
        @"dryRun": @"Backup prüfen",
        @"backupNow": @"Backup jetzt",
        @"dryRunTip": @"Prüft Quelle und Ziel, ohne Dateien zu kopieren.",
        @"backupNowTip": @"Startet das echte Backup und schreibt auf das gewählte Ziel.",
        @"statusReady": @"Bereit.",
        @"statusSaved": @"Gespeichert.",
        @"statusSearching": @"Suche im Netzwerk ...",
        @"statusDiscoveryDone": @"Netzwerksuche abgeschlossen.",
        @"statusBackupStarted": @"Backup gestartet.",
        @"statusDryRunStarted": @"Prüflauf gestartet. Es wird nichts kopiert.",
        @"selectMountedVolume": @"Volume auswählen"
    };
    NSDictionary<NSString *, NSString *> *en = @{
        @"confirmTarget": @"Use this volume?",
        @"startBackup": @"Start backup",
        @"notNow": @"Not now",
        @"running": @"Backup is running ...",
        @"completed": @"Backup completed.",
        @"runningHint": @"Please do not eject the disk.",
        @"completedHint": @"Backup is done.",
        @"setupTitle": @"Backup target and trigger",
        @"targetType": @"Target type",
        @"externalVolume": @"External disk",
        @"nas": @"NAS / Network",
        @"mountedNas": @"Mounted NAS",
        @"refresh": @"Refresh",
        @"discover": @"Search",
        @"openFinder": @"Open in Finder",
        @"nasUrl": @"NAS URL",
        @"nasMount": @"Mount point",
        @"nasSubdir": @"Destination folder",
        @"schedule": @"Start",
        @"scheduleManual": @"Manual only",
        @"scheduleLogin": @"At login",
        @"scheduleHourly": @"Hourly",
        @"scheduleDaily": @"Daily 20:00",
        @"save": @"Save",
        @"dryRun": @"Check backup",
        @"backupNow": @"Back up now",
        @"dryRunTip": @"Checks source and destination without copying files.",
        @"backupNowTip": @"Starts the real backup and writes to the selected destination.",
        @"statusReady": @"Ready.",
        @"statusSaved": @"Saved.",
        @"statusSearching": @"Searching network ...",
        @"statusDiscoveryDone": @"Network search completed.",
        @"statusBackupStarted": @"Backup started.",
        @"statusDryRunStarted": @"Check started. No files will be copied.",
        @"selectMountedVolume": @"Select volume"
    };
    NSDictionary<NSString *, NSString *> *fr = @{
        @"confirmTarget": @"Utiliser ce volume ?",
        @"startBackup": @"Sauvegarder",
        @"notNow": @"Pas maintenant",
        @"running": @"Sauvegarde en cours ...",
        @"completed": @"Sauvegarde terminée.",
        @"runningHint": @"Veuillez ne pas éjecter le disque.",
        @"completedHint": @"Sauvegarde terminée."
    };
    NSDictionary<NSString *, NSString *> *es = @{
        @"confirmTarget": @"¿Usar este volumen?",
        @"startBackup": @"Iniciar copia",
        @"notNow": @"Ahora no",
        @"running": @"Copia en curso ...",
        @"completed": @"Copia completada.",
        @"runningHint": @"No expulses el disco.",
        @"completedHint": @"La copia esta lista."
    };
    NSDictionary<NSString *, NSString *> *ja = @{
        @"confirmTarget": @"このボリュームを使いますか？",
        @"startBackup": @"バックアップ開始",
        @"notNow": @"今はしない",
        @"running": @"バックアップ中...",
        @"completed": @"バックアップ完了。",
        @"runningHint": @"ディスクを取り出さないでください。",
        @"completedHint": @"完了しました。"
    };
    NSDictionary<NSString *, NSString *> *yue = @{
        @"confirmTarget": @"使用呢個卷宗？",
        @"startBackup": @"開始備份",
        @"notNow": @"暫時唔好",
        @"running": @"正在備份...",
        @"completed": @"備份完成。",
        @"runningHint": @"請勿退出磁碟。",
        @"completedHint": @"備份已完成。"
    };
    NSDictionary<NSString *, NSString *> *ko = @{
        @"confirmTarget": @"이 볼륨을 사용할까요?",
        @"startBackup": @"백업 시작",
        @"notNow": @"지금 안 함",
        @"running": @"백업 중...",
        @"completed": @"백업 완료.",
        @"runningHint": @"디스크를 꺼내지 마세요.",
        @"completedHint": @"백업이 완료되었습니다."
    };

    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *tables = @{
        @"de": de,
        @"en": en,
        @"fr": fr,
        @"es": es,
        @"ja": ja,
        @"yue": yue,
        @"ko": ko
    };
    return (tables[language][key] ?: en[key]) ?: key;
}

static NSString *ConfigPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".config/gdrive-tiger-backup/config"];
}

static NSString *ScheduleAgentPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.commcats.gdrivebackup.schedule.plist"];
}

static NSMutableDictionary<NSString *, NSString *> *ReadConfigDictionary(void) {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    NSString *config = [NSString stringWithContentsOfFile:ConfigPath() encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange range = [line rangeOfString:@"="];
        if (range.location == NSNotFound || [line hasPrefix:@"#"]) {
            continue;
        }
        NSString *key = [[line substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = TrimConfigValue([line substringFromIndex:range.location + 1]);
        if (key.length) {
            values[key] = value;
        }
    }
    return values;
}

static NSString *ShellQuote(NSString *value) {
    NSString *escaped = [value ?: @"" stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static BOOL WriteConfigUpdates(NSDictionary<NSString *, NSString *> *updates, NSError **error) {
    NSString *path = ConfigPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *config = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray<NSString *> *lines = [[config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSMutableSet<NSString *> *remaining = [NSMutableSet setWithArray:updates.allKeys];

    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        NSRange range = [line rangeOfString:@"="];
        if (range.location == NSNotFound || [line hasPrefix:@"#"]) {
            continue;
        }
        NSString *key = [[line substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = updates[key];
        if (value) {
            lines[index] = [NSString stringWithFormat:@"%@=%@", key, ShellQuote(value)];
            [remaining removeObject:key];
        }
    }

    if (lines.count && lines.lastObject.length == 0) {
        [lines removeLastObject];
    }

    NSArray<NSString *> *orderedKeys = @[
        @"GDRIVE_BACKUP_TARGET",
        @"GDRIVE_BACKUP_NAS_MOUNT",
        @"GDRIVE_BACKUP_NAS_URL",
        @"GDRIVE_BACKUP_NAS_SUBDIR",
        @"GDRIVE_BACKUP_NAS_START_ON_MOUNT",
        @"GDRIVE_BACKUP_SCHEDULE"
    ];
    for (NSString *key in orderedKeys) {
        if ([remaining containsObject:key]) {
            [lines addObject:[NSString stringWithFormat:@"%@=%@", key, ShellQuote(updates[key])]];
            [remaining removeObject:key];
        }
    }
    for (NSString *key in remaining.allObjects) {
        [lines addObject:[NSString stringWithFormat:@"%@=%@", key, ShellQuote(updates[key])]];
    }

    NSString *newConfig = [[lines arrayByAddingObject:@""] componentsJoinedByString:@"\n"];
    return [newConfig writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static NSString *RunCommand(NSString *launchPath, NSArray<NSString *> *arguments, NSDictionary<NSString *, NSString *> *environment, int *statusOut) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments ?: @[];
    if (environment) {
        NSMutableDictionary *env = NSProcessInfo.processInfo.environment.mutableCopy;
        [env addEntriesFromDictionary:environment];
        task.environment = env;
    }

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (statusOut) {
            *statusOut = 127;
        }
        return exception.reason ?: @"";
    }

    if (statusOut) {
        *statusOut = task.terminationStatus;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSArray<NSDictionary<NSString *, NSString *> *> *MountedNetworkVolumes(void) {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *volumes = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *byPath = [NSMutableDictionary dictionary];
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/Volumes" error:nil] ?: @[];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSString *path = [@"/Volumes" stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }

        NSURL *url = [NSURL fileURLWithPath:path];
        NSNumber *isLocal = nil;
        NSURL *remountURL = nil;
        [url getResourceValue:&isLocal forKey:NSURLVolumeIsLocalKey error:nil];
        [url getResourceValue:&remountURL forKey:NSURLVolumeURLForRemountingKey error:nil];

        BOOL networkVolume = (isLocal && !isLocal.boolValue) || remountURL.absoluteString.length > 0;
        if (!networkVolume) {
            continue;
        }

        NSMutableDictionary<NSString *, NSString *> *volume = [@{
            @"name": name,
            @"path": path,
            @"url": remountURL.absoluteString ?: @"",
            @"writable": [NSFileManager.defaultManager isWritableFileAtPath:path] ? @"1" : @"0",
            @"readable": [NSFileManager.defaultManager isReadableFileAtPath:path] ? @"1" : @"0"
        } mutableCopy];
        byPath[path] = volume;
        [volumes addObject:volume];
    }

    int status = 0;
    NSString *mountOutput = RunCommand(@"/sbin/mount", @[], nil, &status);
    for (NSString *line in [mountOutput componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line containsString:@" on /Volumes/"] || (![line containsString:@" (smbfs,"] && ![line containsString:@" (afpfs,"] && ![line containsString:@" (nfs,"])) {
            continue;
        }

        NSRange onRange = [line rangeOfString:@" on /Volumes/"];
        NSRange typeRange = [line rangeOfString:@" (" options:0 range:NSMakeRange(NSMaxRange(onRange), line.length - NSMaxRange(onRange))];
        if (onRange.location == NSNotFound || typeRange.location == NSNotFound) {
            continue;
        }

        NSString *source = [line substringToIndex:onRange.location];
        NSString *path = [line substringWithRange:NSMakeRange(onRange.location + 4, typeRange.location - (onRange.location + 4))];
        NSString *name = path.lastPathComponent;
        NSString *url = @"";
        if ([source hasPrefix:@"//"]) {
            NSString *withoutSlashes = [source substringFromIndex:2];
            NSRange atRange = [withoutSlashes rangeOfString:@"@" options:NSBackwardsSearch];
            if (atRange.location != NSNotFound) {
                withoutSlashes = [withoutSlashes substringFromIndex:atRange.location + 1];
            }
            url = [@"smb://" stringByAppendingString:withoutSlashes];
        }

        NSMutableDictionary<NSString *, NSString *> *volume = byPath[path];
        if (volume) {
            if (url.length && !volume[@"url"].length) {
                volume[@"url"] = url;
            }
            continue;
        }

        volume = [@{
            @"name": name ?: path,
            @"path": path,
            @"url": url,
            @"writable": [NSFileManager.defaultManager isWritableFileAtPath:path] ? @"1" : @"0",
            @"readable": [NSFileManager.defaultManager isReadableFileAtPath:path] ? @"1" : @"0"
        } mutableCopy];
        byPath[path] = volume;
        [volumes addObject:volume];
    }
    return volumes;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *DiscoverBonjourStorage(void) {
    NSString *script = @"pids=''; for t in _smb._tcp _afpovertcp._tcp; do /usr/bin/dns-sd -B \"$t\" local 2>/dev/null & pids=\"$pids $!\"; done; sleep 3; for p in $pids; do kill \"$p\" 2>/dev/null; done; wait 2>/dev/null";
    int status = 0;
    NSString *output = RunCommand(@"/bin/bash", @[@"-lc", script], nil, &status);
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *services = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line containsString:@" Add "]) {
            continue;
        }
        NSString *scheme = nil;
        NSString *typeToken = nil;
        if ([line containsString:@"_smb._tcp."]) {
            scheme = @"smb";
            typeToken = @"_smb._tcp.";
        } else if ([line containsString:@"_afpovertcp._tcp."]) {
            scheme = @"afp";
            typeToken = @"_afpovertcp._tcp.";
        } else {
            continue;
        }

        NSRange range = [line rangeOfString:typeToken];
        if (range.location == NSNotFound) {
            continue;
        }
        NSString *name = [[line substringFromIndex:NSMaxRange(range)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) {
            continue;
        }
        NSString *hostPart = [[name lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        NSString *candidateURL = [NSString stringWithFormat:@"%@://%@.local", scheme, hostPart];
        NSString *key = [NSString stringWithFormat:@"%@:%@", scheme, name];
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [services addObject:@{
            @"name": name,
            @"url": candidateURL,
            @"scheme": scheme.uppercaseString
        }];
    }
    return services;
}

@interface TigerBackupView : NSView
@property(nonatomic) CGFloat phase;
@property(nonatomic) BOOL completed;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) NSString *confirmDetail;
@property(nonatomic, copy) NSString *primaryActionTitle;
@property(nonatomic, copy) NSString *secondaryActionTitle;
@property(nonatomic) CGFloat progressPercent;
@property(nonatomic, copy) NSString *progressTitle;
@property(nonatomic, copy) NSString *progressDetail;
@property(nonatomic, copy) void (^minimizeHandler)(void);
@property(nonatomic, copy) void (^confirmHandler)(BOOL approved);
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL draggingWindow;
@property(nonatomic) NSPoint dragStartMouse;
@property(nonatomic) NSPoint dragStartOrigin;
@end

@implementation TigerBackupView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.progressPercent = -1;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0)
                                                     repeats:YES
                                                       block:^(NSTimer *timer) {
            self.phase = fmod(self.phase + 1.3, 360.0);
            self.needsDisplay = YES;
        }];
    }
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;

    NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:18 yRadius:18];
    [NSGraphicsContext saveGraphicsState];
    [panel addClip];

    NSGradient *bodyGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.97 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.82 alpha:1.0]
    ]];
    [bodyGradient drawInRect:bounds angle:-90];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.24] setFill];
    for (CGFloat y = 44; y < NSHeight(bounds); y += 4) {
        NSRectFill(NSMakeRect(0, y, NSWidth(bounds), 1));
    }

    NSRect titleBar = NSMakeRect(0, 0, NSWidth(bounds), 48);
    NSGradient *titleGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.70 alpha:1.0]
    ]];
    [titleGradient drawInRect:titleBar angle:-90];
    [[NSColor colorWithCalibratedWhite:0.48 alpha:0.38] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(titleBar) - 1, NSWidth(bounds), 1));

    [self drawTrafficLights];
    if (self.completed) {
        [self drawCheckmarkAt:NSMakePoint(58, 94)];
    } else {
        [self drawSpinnerAt:NSMakePoint(58, 94)];
    }
    [self drawLabels];
    [self drawProgressBarInRect:NSMakeRect(112, 106, 250, 19)];

    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithCalibratedWhite:0.36 alpha:0.42] setStroke];
    panel.lineWidth = 1.5;
    [panel stroke];
}

- (void)drawTrafficLights {
    NSArray<NSColor *> *colors = @[
        [NSColor colorWithCalibratedRed:0.95 green:0.27 blue:0.22 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.99 green:0.75 blue:0.18 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.35 green:0.78 blue:0.25 alpha:1.0]
    ];

    for (NSUInteger index = 0; index < colors.count; index++) {
        NSRect rect = NSMakeRect(18 + index * 18, 17, 11, 11);
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:rect];
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
            [[NSColor whiteColor] colorWithAlphaComponent:0.75],
            colors[index]
        ]];
        [gradient drawInBezierPath:dot angle:-90];
        [[NSColor colorWithCalibratedWhite:0.25 alpha:0.35] setStroke];
        [dot stroke];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect redButton = NSMakeRect(18, 17, 11, 11);
    NSRect yellowButton = NSMakeRect(36, 17, 11, 11);

    if (self.confirmMode) {
        if (NSPointInRect(point, NSInsetRect(redButton, -7, -7)) && self.confirmHandler) {
            self.confirmHandler(NO);
            return;
        }
        if (NSPointInRect(point, [self primaryButtonRect]) && self.confirmHandler) {
            self.confirmHandler(YES);
            return;
        }
        if (NSPointInRect(point, [self secondaryButtonRect]) && self.confirmHandler) {
            self.confirmHandler(NO);
            return;
        }
    }

    if (NSPointInRect(point, NSInsetRect(yellowButton, -7, -7)) && self.minimizeHandler) {
        self.minimizeHandler();
        return;
    }

    self.draggingWindow = YES;
    self.dragStartMouse = NSEvent.mouseLocation;
    self.dragStartOrigin = self.window.frame.origin;
    [self.window makeKeyWindow];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.draggingWindow || !self.window) {
        [super mouseDragged:event];
        return;
    }

    NSPoint currentMouse = NSEvent.mouseLocation;
    NSPoint newOrigin = NSMakePoint(self.dragStartOrigin.x + currentMouse.x - self.dragStartMouse.x,
                                    self.dragStartOrigin.y + currentMouse.y - self.dragStartMouse.y);
    [self.window setFrameOrigin:newOrigin];
}

- (void)mouseUp:(NSEvent *)event {
    self.draggingWindow = NO;
}

- (void)drawSpinnerAt:(NSPoint)center {
    CGFloat ringRadius = 28;
    NSRect diskRect = NSMakeRect(center.x - 23, center.y - 18, 46, 36);
    NSBezierPath *disk = [NSBezierPath bezierPathWithRoundedRect:diskRect xRadius:7 yRadius:7];

    NSGradient *diskGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.91 green:0.94 blue:0.96 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.56 green:0.61 blue:0.66 alpha:1.0]
    ]];
    [diskGradient drawInBezierPath:disk angle:-90];
    [[NSColor colorWithCalibratedWhite:0.36 alpha:0.65] setStroke];
    disk.lineWidth = 1;
    [disk stroke];

    NSBezierPath *slot = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(center.x - 12, center.y - 3, 24, 6) xRadius:3 yRadius:3];
    [[NSColor colorWithCalibratedRed:0.18 green:0.38 blue:0.64 alpha:0.85] setFill];
    [slot fill];

    for (NSUInteger i = 0; i < 10; i++) {
        CGFloat angle = (((CGFloat)i / 10.0) * M_PI * 2.0) + self.phase * M_PI / 180.0;
        CGFloat alpha = 0.22 + (CGFloat)i * 0.075;
        NSPoint dotCenter = NSMakePoint(center.x + cos(angle) * ringRadius, center.y + sin(angle) * ringRadius);
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotCenter.x - 3.3, dotCenter.y - 3.3, 6.6, 6.6)];
        [[NSColor colorWithCalibratedRed:0.02 green:0.42 blue:1.0 alpha:alpha] setFill];
        [dot fill];
    }
}

- (void)drawCheckmarkAt:(NSPoint)center {
    NSBezierPath *badge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 28, center.y - 28, 56, 56)];
    NSGradient *badgeGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.64 green:0.95 blue:0.54 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.12 green:0.63 blue:0.20 alpha:1.0]
    ]];
    [badgeGradient drawInBezierPath:badge angle:-90];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.55] setStroke];
    badge.lineWidth = 1.5;
    [badge stroke];

    NSBezierPath *check = [NSBezierPath bezierPath];
    [check moveToPoint:NSMakePoint(center.x - 15, center.y + 1)];
    [check lineToPoint:NSMakePoint(center.x - 4, center.y + 13)];
    [check lineToPoint:NSMakePoint(center.x + 18, center.y - 14)];
    [[NSColor whiteColor] setStroke];
    check.lineWidth = 6;
    check.lineCapStyle = NSLineCapStyleRound;
    check.lineJoinStyle = NSLineJoinStyleRound;
    [check stroke];
}

- (void)drawLabels {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSFont *titleFont = [NSFont fontWithName:@"Lucida Grande Bold" size:15] ?: [NSFont boldSystemFontOfSize:15];
    NSFont *bodyFont = [NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12];
    NSFont *hintFont = [NSFont fontWithName:@"Lucida Grande" size:10] ?: [NSFont systemFontOfSize:10];

    NSDictionary *titleAttributes = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.10 alpha:1.0],
        NSParagraphStyleAttributeName: style
    };
    NSDictionary *subtitleAttributes = @{
        NSFontAttributeName: bodyFont,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.22 alpha:1.0],
        NSParagraphStyleAttributeName: style
    };
    NSDictionary *hintAttributes = @{
        NSFontAttributeName: hintFont,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
        NSParagraphStyleAttributeName: style
    };

    [@"Google Drive Backup" drawInRect:NSMakeRect(76, 16, 300, 20) withAttributes:titleAttributes];
    NSString *language = self.language ?: @"en";
    NSString *subtitle = self.confirmMode ? (self.confirmTitle ?: T(language, @"confirmTarget")) : (self.completed ? T(language, @"completed") : (self.progressTitle ?: T(language, @"running")));
    NSString *hint = self.confirmMode ? (self.confirmDetail ?: @"") : (self.completed ? T(language, @"completedHint") : (self.progressDetail ?: T(language, @"runningHint")));
    [subtitle drawInRect:NSMakeRect(112, 76, 250, 18) withAttributes:subtitleAttributes];

    if (self.confirmMode) {
        [hint drawInRect:NSMakeRect(112, 98, 250, 16) withAttributes:hintAttributes];
    } else {
        [hint drawInRect:NSMakeRect(112, 133, 250, 16) withAttributes:hintAttributes];
    }
}

- (void)drawProgressBarInRect:(NSRect)rect {
    if (self.confirmMode) {
        NSString *language = self.language ?: @"en";
        [self drawButtonWithTitle:(self.secondaryActionTitle ?: T(language, @"notNow")) inRect:[self secondaryButtonRect] primary:NO];
        [self drawButtonWithTitle:(self.primaryActionTitle ?: T(language, @"startBackup")) inRect:[self primaryButtonRect] primary:YES];
        return;
    }

    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:9 yRadius:9];
    [[NSColor colorWithCalibratedWhite:0.91 alpha:1.0] setFill];
    [outer fill];
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.55] setStroke];
    outer.lineWidth = 1;
    [outer stroke];

    NSRect inner = NSInsetRect(rect, 2, 2);
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:7 yRadius:7];
    CGFloat fraction = 1.0;
    if (!self.completed && self.progressPercent >= 0) {
        fraction = MAX(0.0, MIN(1.0, self.progressPercent / 100.0));
    }
    NSRect fillRect = inner;
    fillRect.size.width = floor(NSWidth(inner) * fraction);

    NSArray<NSColor *> *colors = self.completed ? @[
        [NSColor colorWithCalibratedRed:0.43 green:0.90 blue:0.35 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.08 green:0.55 blue:0.18 alpha:1.0]
    ] : @[
        [NSColor colorWithCalibratedRed:0.18 green:0.70 blue:1.0 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.03 green:0.33 blue:0.90 alpha:1.0]
    ];
    NSGradient *blueGradient = [[NSGradient alloc] initWithColors:colors];

    [NSGraphicsContext saveGraphicsState];
    [innerPath addClip];
    if (fillRect.size.width > 0) {
        NSRectClip(fillRect);
        [blueGradient drawInRect:inner angle:-90];
    }

    CGFloat spacing = 18;
    CGFloat offset = fmod(self.phase, spacing);
    [[[NSColor whiteColor] colorWithAlphaComponent:0.22] setFill];
    CGFloat stripeLimit = self.progressPercent >= 0 || self.completed ? NSWidth(fillRect) : NSWidth(inner);
    for (CGFloat x = -NSHeight(inner) * 2 - spacing + offset; x <= stripeLimit + spacing; x += spacing) {
        NSBezierPath *stripe = [NSBezierPath bezierPath];
        [stripe moveToPoint:NSMakePoint(NSMinX(inner) + x, NSMaxY(inner))];
        [stripe lineToPoint:NSMakePoint(NSMinX(inner) + x + 10, NSMaxY(inner))];
        [stripe lineToPoint:NSMakePoint(NSMinX(inner) + x + 25, NSMinY(inner))];
        [stripe lineToPoint:NSMakePoint(NSMinX(inner) + x + 15, NSMinY(inner))];
        [stripe closePath];
        [stripe fill];
    }
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *gloss = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(inner) + 2, NSMinY(inner) + 2, NSWidth(inner) - 4, NSHeight(inner) * 0.42) xRadius:5 yRadius:5];
    [[[NSColor whiteColor] colorWithAlphaComponent:0.34] setFill];
    [gloss fill];

    NSString *progressText = @"";
    if (self.completed) {
        progressText = @"100%";
    } else if (self.progressPercent >= 0) {
        progressText = [NSString stringWithFormat:@"%.0f%%", self.progressPercent];
    }

    if (progressText.length > 0) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont fontWithName:@"Lucida Grande Bold" size:10] ?: [NSFont boldSystemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName: style
        };
        [progressText drawInRect:NSMakeRect(NSMinX(rect), NSMinY(rect) + 3, NSWidth(rect), 13)
                  withAttributes:attributes];
    }
}

- (NSRect)primaryButtonRect {
    return NSMakeRect(232, 116, 130, 27);
}

- (NSRect)secondaryButtonRect {
    return NSMakeRect(112, 116, 110, 27);
}

- (void)drawButtonWithTitle:(NSString *)title inRect:(NSRect)rect primary:(BOOL)primary {
    NSBezierPath *button = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8];
    NSArray<NSColor *> *colors = primary ? @[
        [NSColor colorWithCalibratedRed:0.78 green:0.92 blue:1.0 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.22 green:0.52 blue:0.96 alpha:1.0]
    ] : @[
        [NSColor colorWithCalibratedWhite:0.98 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.74 alpha:1.0]
    ];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:colors];
    [gradient drawInBezierPath:button angle:-90];
    [[NSColor colorWithCalibratedWhite:0.28 alpha:0.55] setStroke];
    button.lineWidth = 1;
    [button stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?: [NSFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: primary ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite:0.14 alpha:1.0],
        NSParagraphStyleAttributeName: style
    };
    [title drawInRect:NSInsetRect(rect, 8, 6) withAttributes:attributes];
}

@end

@interface TigerSetupView : NSView
@end

@implementation TigerSetupView

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;

    NSGradient *bodyGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.97 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.84 alpha:1.0]
    ]];
    [bodyGradient drawInRect:bounds angle:-90];

    NSRect titleBar = NSMakeRect(0, 0, NSWidth(bounds), 64);
    NSGradient *titleGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.96 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.72 alpha:1.0]
    ]];
    [titleGradient drawInRect:titleBar angle:-90];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.22] setFill];
    for (CGFloat y = 72; y < NSHeight(bounds); y += 4) {
        NSRectFill(NSMakeRect(0, y, NSWidth(bounds), 1));
    }

    [[NSColor colorWithCalibratedWhite:0.46 alpha:0.35] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(titleBar) - 1, NSWidth(bounds), 1));

    NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 84, NSWidth(bounds) - 36, 222) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.54] setFill];
    [panel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.24] setStroke];
    panel.lineWidth = 1;
    [panel stroke];

    NSBezierPath *schedulePanel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 318, NSWidth(bounds) - 36, 52) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.42] setFill];
    [schedulePanel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.20] setStroke];
    [schedulePanel stroke];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *sentinelPath;
@property(nonatomic, copy) NSString *progressPath;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic) BOOL setupMode;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) NSString *confirmDetail;
@property(nonatomic, copy) NSString *primaryActionTitle;
@property(nonatomic, copy) NSString *secondaryActionTitle;
@property(nonatomic, copy) NSString *confirmResponsePath;
@property(nonatomic, strong) NSTimer *sentinelTimer;
@property(nonatomic, strong) NSTimer *confirmTimeoutTimer;
@property(nonatomic, strong) NSTimer *progressTimer;
@property(nonatomic) BOOL hiddenByUser;
@property(nonatomic) BOOL completing;
@property(nonatomic) BOOL confirmationAnswered;
@property(nonatomic, strong) NSPopUpButton *targetPopup;
@property(nonatomic, strong) NSPopUpButton *mountedNasPopup;
@property(nonatomic, strong) NSPopUpButton *discoveredNasPopup;
@property(nonatomic, strong) NSPopUpButton *schedulePopup;
@property(nonatomic, strong) NSTextField *nasURLField;
@property(nonatomic, strong) NSTextField *nasMountField;
@property(nonatomic, strong) NSTextField *nasSubdirField;
@property(nonatomic, strong) NSTextField *statusField;
@end

@implementation AppDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12];
    label.textColor = [NSColor colorWithCalibratedWhite:0.18 alpha:1.0];
    return label;
}

- (NSTextField *)fieldWithFrame:(NSRect)frame {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.font = [NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12];
    field.bezelStyle = NSTextFieldRoundedBezel;
    return field;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title ?: @"";
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    button.font = [NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12];
    return button;
}

- (void)showSetupWindow {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp setApplicationIconImage:CreateApplicationIcon()];

    NSSize size = NSMakeSize(610, 430);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2, NSMidY(screenFrame) - size.height / 2);

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"GDrive Backup Tiger";
    self.window.releasedWhenClosed = NO;

    TigerSetupView *content = [[TigerSetupView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = content;

    NSMutableDictionary<NSString *, NSString *> *config = ReadConfigDictionary();
    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];

    NSTextField *title = [self label:@"Google Drive Backup" frame:NSMakeRect(26, 16, 300, 22)];
    title.font = [NSFont fontWithName:@"Lucida Grande Bold" size:17] ?: [NSFont boldSystemFontOfSize:17];
    [content addSubview:title];

    NSTextField *subtitle = [self label:T(self.language, @"setupTitle") frame:NSMakeRect(26, 39, 420, 18)];
    subtitle.textColor = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    [content addSubview:subtitle];

    [content addSubview:[self label:T(self.language, @"targetType") frame:NSMakeRect(34, 100, 124, 22)]];
    self.targetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 96, 170, 28)];
    [self.targetPopup addItemWithTitle:T(self.language, @"externalVolume")];
    self.targetPopup.lastItem.representedObject = @"apfs";
    [self.targetPopup addItemWithTitle:T(self.language, @"nas")];
    self.targetPopup.lastItem.representedObject = @"nas";
    [self.targetPopup selectItemAtIndex:[target isEqualToString:@"nas"] ? 1 : 0];
    [content addSubview:self.targetPopup];

    [content addSubview:[self label:T(self.language, @"mountedNas") frame:NSMakeRect(34, 136, 124, 22)]];
    self.mountedNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 132, 270, 28)];
    self.mountedNasPopup.target = self;
    self.mountedNasPopup.action = @selector(selectMountedNAS:);
    [content addSubview:self.mountedNasPopup];
    [content addSubview:[self button:T(self.language, @"refresh") frame:NSMakeRect(444, 132, 120, 28) action:@selector(refreshMountedNAS:)]];

    [content addSubview:[self label:T(self.language, @"nasUrl") frame:NSMakeRect(34, 174, 124, 22)]];
    self.nasURLField = [self fieldWithFrame:NSMakeRect(164, 170, 270, 26)];
    self.nasURLField.stringValue = config[@"GDRIVE_BACKUP_NAS_URL"] ?: @"";
    [content addSubview:self.nasURLField];
    [content addSubview:[self button:T(self.language, @"openFinder") frame:NSMakeRect(444, 169, 120, 28) action:@selector(openNASInFinder:)]];

    [content addSubview:[self label:T(self.language, @"nasMount") frame:NSMakeRect(34, 210, 124, 22)]];
    self.nasMountField = [self fieldWithFrame:NSMakeRect(164, 206, 270, 26)];
    self.nasMountField.stringValue = config[@"GDRIVE_BACKUP_NAS_MOUNT"] ?: @"";
    [content addSubview:self.nasMountField];

    [content addSubview:[self label:T(self.language, @"nasSubdir") frame:NSMakeRect(34, 246, 124, 22)]];
    self.nasSubdirField = [self fieldWithFrame:NSMakeRect(164, 242, 270, 26)];
    self.nasSubdirField.stringValue = config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup";
    [content addSubview:self.nasSubdirField];

    self.discoveredNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 278, 270, 28)];
    [self.discoveredNasPopup addItemWithTitle:@"Bonjour"];
    self.discoveredNasPopup.target = self;
    self.discoveredNasPopup.action = @selector(selectDiscoveredNAS:);
    [content addSubview:self.discoveredNasPopup];
    [content addSubview:[self button:T(self.language, @"discover") frame:NSMakeRect(444, 278, 120, 28) action:@selector(discoverNAS:)]];

    [content addSubview:[self label:T(self.language, @"schedule") frame:NSMakeRect(34, 334, 124, 22)]];
    self.schedulePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 330, 270, 28)];
    NSArray<NSArray<NSString *> *> *scheduleItems = @[
        @[T(self.language, @"scheduleManual"), @"manual"],
        @[T(self.language, @"scheduleLogin"), @"login"],
        @[T(self.language, @"scheduleHourly"), @"hourly"],
        @[T(self.language, @"scheduleDaily"), @"daily"]
    ];
    for (NSArray<NSString *> *item in scheduleItems) {
        [self.schedulePopup addItemWithTitle:item[0]];
        self.schedulePopup.lastItem.representedObject = item[1];
        if ([schedule isEqualToString:item[1]]) {
            [self.schedulePopup selectItem:self.schedulePopup.lastItem];
        }
    }
    [content addSubview:self.schedulePopup];

    self.statusField = [self label:T(self.language, @"statusReady") frame:NSMakeRect(26, 388, 270, 20)];
    self.statusField.textColor = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    [content addSubview:self.statusField];

    NSButton *saveButton = [self button:T(self.language, @"save") frame:NSMakeRect(282, 383, 88, 30) action:@selector(saveSetup:)];
    NSButton *dryRunButton = [self button:T(self.language, @"dryRun") frame:NSMakeRect(378, 383, 112, 30) action:@selector(startDryRun:)];
    dryRunButton.toolTip = T(self.language, @"dryRunTip");
    NSButton *backupButton = [self button:T(self.language, @"backupNow") frame:NSMakeRect(498, 383, 88, 30) action:@selector(startBackupNow:)];
    backupButton.toolTip = T(self.language, @"backupNowTip");
    [content addSubview:saveButton];
    [content addSubview:dryRunButton];
    [content addSubview:backupButton];

    [self refreshMountedNAS:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshMountedNAS:(id)sender {
    [self.mountedNasPopup removeAllItems];
    [self.mountedNasPopup addItemWithTitle:T(self.language, @"selectMountedVolume")];
    self.mountedNasPopup.lastItem.representedObject = @{};

    NSArray<NSDictionary<NSString *, NSString *> *> *volumes = MountedNetworkVolumes();
    NSString *currentMount = self.nasMountField.stringValue;
    NSString *wantedHost = [self hostPartFromURLString:self.nasURLField.stringValue];
    NSDictionary<NSString *, NSString *> *autoSelection = nil;

    for (NSDictionary<NSString *, NSString *> *volume in volumes) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@", volume[@"name"], volume[@"path"]];
        [self.mountedNasPopup addItemWithTitle:title];
        self.mountedNasPopup.lastItem.representedObject = volume;
        if ([volume[@"path"] isEqualToString:self.nasMountField.stringValue]) {
            [self.mountedNasPopup selectItem:self.mountedNasPopup.lastItem];
        }

        NSString *volumeHost = [self hostPartFromURLString:volume[@"url"]];
        if (!currentMount.length && wantedHost.length && [volumeHost isEqualToString:wantedHost]) {
            autoSelection = volume;
            [self.mountedNasPopup selectItem:self.mountedNasPopup.lastItem];
        }
    }

    if (!currentMount.length && !autoSelection && volumes.count == 1) {
        autoSelection = volumes.firstObject;
        [self.mountedNasPopup selectItemAtIndex:1];
    }

    if (autoSelection) {
        self.nasMountField.stringValue = autoSelection[@"path"] ?: @"";
        NSString *url = autoSelection[@"url"];
        if (url.length) {
            self.nasURLField.stringValue = url;
        }
        [self.targetPopup selectItemAtIndex:1];
    }
}

- (NSString *)hostPartFromURLString:(NSString *)urlString {
    if (!urlString.length) {
        return @"";
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url.host.length) {
        return url.host.lowercaseString;
    }

    NSString *withoutScheme = urlString;
    NSRange schemeRange = [withoutScheme rangeOfString:@"://"];
    if (schemeRange.location != NSNotFound) {
        withoutScheme = [withoutScheme substringFromIndex:NSMaxRange(schemeRange)];
    }
    NSRange atRange = [withoutScheme rangeOfString:@"@" options:NSBackwardsSearch];
    if (atRange.location != NSNotFound) {
        withoutScheme = [withoutScheme substringFromIndex:atRange.location + 1];
    }
    NSRange slashRange = [withoutScheme rangeOfString:@"/"];
    if (slashRange.location != NSNotFound) {
        withoutScheme = [withoutScheme substringToIndex:slashRange.location];
    }
    return withoutScheme.lowercaseString;
}

- (void)selectMountedNAS:(id)sender {
    NSDictionary *volume = self.mountedNasPopup.selectedItem.representedObject;
    NSString *path = volume[@"path"];
    if (!path.length) {
        return;
    }
    self.nasMountField.stringValue = path;
    NSString *url = volume[@"url"];
    if (url.length) {
        self.nasURLField.stringValue = url;
    }
    [self.targetPopup selectItemAtIndex:1];
}

- (void)selectDiscoveredNAS:(id)sender {
    NSDictionary *service = self.discoveredNasPopup.selectedItem.representedObject;
    NSString *url = service[@"url"];
    if (url.length) {
        self.nasURLField.stringValue = url;
        [self.targetPopup selectItemAtIndex:1];
    }
}

- (void)discoverNAS:(id)sender {
    self.statusField.stringValue = T(self.language, @"statusSearching");
    [self.discoveredNasPopup removeAllItems];
    [self.discoveredNasPopup addItemWithTitle:@"Bonjour"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary<NSString *, NSString *> *> *services = DiscoverBonjourStorage();
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.discoveredNasPopup removeAllItems];
            if (!services.count) {
                [self.discoveredNasPopup addItemWithTitle:@"Bonjour"];
            }
            for (NSDictionary<NSString *, NSString *> *service in services) {
                NSString *title = [NSString stringWithFormat:@"%@: %@", service[@"scheme"], service[@"name"]];
                [self.discoveredNasPopup addItemWithTitle:title];
                self.discoveredNasPopup.lastItem.representedObject = service;
            }
            self.statusField.stringValue = T(self.language, @"statusDiscoveryDone");
        });
    });
}

- (void)openNASInFinder:(id)sender {
    NSString *urlString = self.nasURLField.stringValue;
    if (!urlString.length) {
        NSDictionary *service = self.discoveredNasPopup.selectedItem.representedObject;
        urlString = service[@"url"];
    }
    if (!urlString.length) {
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [NSWorkspace.sharedWorkspace openURL:url];
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *timer) {
            [self refreshMountedNAS:nil];
        }];
        [NSTimer scheduledTimerWithTimeInterval:6.0 repeats:NO block:^(NSTimer *timer) {
            [self refreshMountedNAS:nil];
        }];
    }
}

- (NSDictionary<NSString *, NSString *> *)currentSetupUpdates {
    NSString *target = self.targetPopup.selectedItem.representedObject ?: @"apfs";
    NSString *schedule = self.schedulePopup.selectedItem.representedObject ?: @"manual";
    NSMutableDictionary<NSString *, NSString *> *updates = [NSMutableDictionary dictionary];
    updates[@"GDRIVE_BACKUP_TARGET"] = target;
    updates[@"GDRIVE_BACKUP_SCHEDULE"] = schedule;

    if ([target isEqualToString:@"nas"]) {
        updates[@"GDRIVE_BACKUP_NAS_MOUNT"] = self.nasMountField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_URL"] = self.nasURLField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_SUBDIR"] = self.nasSubdirField.stringValue.length ? self.nasSubdirField.stringValue : @"GoogleDrive-Backup";
        updates[@"GDRIVE_BACKUP_NAS_START_ON_MOUNT"] = @"0";
    }
    return updates;
}

- (BOOL)saveSetupValues {
    NSError *error = nil;
    if (!WriteConfigUpdates([self currentSetupUpdates], &error)) {
        self.statusField.stringValue = error.localizedDescription ?: @"Save failed.";
        return NO;
    }
    [self applySchedule:self.schedulePopup.selectedItem.representedObject ?: @"manual"];
    self.statusField.stringValue = T(self.language, @"statusSaved");
    return YES;
}

- (void)saveSetup:(id)sender {
    [self saveSetupValues];
}

- (void)startBackupNow:(id)sender {
    if (![self saveSetupValues]) {
        return;
    }
    [self launchBackupWithArgument:@"--run" assumeYes:YES];
    self.statusField.stringValue = T(self.language, @"statusBackupStarted");
}

- (void)startDryRun:(id)sender {
    if (![self saveSetupValues]) {
        return;
    }
    [self launchBackupWithArgument:@"--dry-run" assumeYes:YES];
    self.statusField.stringValue = T(self.language, @"statusDryRunStarted");
}

- (void)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"/usr/local/bin/backup-google-drive.sh", argument];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"HOME"] = NSHomeDirectory();
    environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    environment[@"GDRIVE_BACKUP_TRIGGER"] = @"manual";
    if (assumeYes) {
        environment[@"BACKUP_ASSUME_YES"] = @"1";
    }
    task.environment = environment;
    @try {
        [task launch];
    } @catch (NSException *exception) {
        self.statusField.stringValue = exception.reason ?: @"Launch failed.";
    }
}

- (NSString *)schedulePlistForMode:(NSString *)mode {
    NSString *home = NSHomeDirectory();
    NSMutableString *plist = [NSMutableString string];
    [plist appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [plist appendString:@"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"];
    [plist appendString:@"<plist version=\"1.0\"><dict>\n"];
    [plist appendString:@"  <key>Label</key><string>com.commcats.gdrivebackup.schedule</string>\n"];
    [plist appendString:@"  <key>ProgramArguments</key><array><string>/bin/bash</string><string>/usr/local/bin/backup-google-drive.sh</string><string>--run</string></array>\n"];
    [plist appendFormat:@"  <key>EnvironmentVariables</key><dict><key>HOME</key><string>%@</string><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string><key>GDRIVE_BACKUP_TRIGGER</key><string>schedule</string></dict>\n", home];
    if ([mode isEqualToString:@"login"]) {
        [plist appendString:@"  <key>RunAtLoad</key><true/>\n"];
    } else if ([mode isEqualToString:@"hourly"]) {
        [plist appendString:@"  <key>StartInterval</key><integer>3600</integer>\n"];
    } else if ([mode isEqualToString:@"daily"]) {
        [plist appendString:@"  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>20</integer><key>Minute</key><integer>0</integer></dict>\n"];
    }
    [plist appendString:@"</dict></plist>\n"];
    return plist;
}

- (void)applySchedule:(NSString *)mode {
    NSString *path = ScheduleAgentPath();
    NSString *domain = [NSString stringWithFormat:@"gui/%d", getuid()];
    NSString *service = [domain stringByAppendingString:@"/com.commcats.gdrivebackup.schedule"];
    RunCommand(@"/bin/launchctl", @[@"bootout", domain, path], nil, NULL);

    if (![mode isEqualToString:@"login"] && ![mode isEqualToString:@"hourly"] && ![mode isEqualToString:@"daily"]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return;
    }

    NSString *dir = [path stringByDeletingLastPathComponent];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[self schedulePlistForMode:mode] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    RunCommand(@"/bin/launchctl", @[@"bootstrap", domain, path], nil, NULL);
    RunCommand(@"/bin/launchctl", @[@"enable", service], nil, NULL);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.language = ConfiguredLanguage();
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (arguments.count == 1 || (arguments.count > 1 && [arguments[1] isEqualToString:@"--setup"])) {
        self.setupMode = YES;
        [self showSetupWindow];
        return;
    }

    if (arguments.count > 1 && [arguments[1] isEqualToString:@"--confirm"]) {
        self.confirmMode = YES;
        if (arguments.count > 6) {
            self.confirmTitle = arguments[2];
            self.confirmDetail = arguments[3];
            self.primaryActionTitle = arguments[4];
            self.secondaryActionTitle = arguments[5];
            self.confirmResponsePath = arguments[6];
        } else if (arguments.count > 5) {
            self.confirmTitle = arguments[2];
            self.confirmDetail = arguments[3];
            self.primaryActionTitle = arguments[4];
            self.secondaryActionTitle = T(self.language, @"notNow");
            self.confirmResponsePath = arguments[5];
        } else if (arguments.count > 3) {
            self.confirmTitle = T(self.language, @"confirmTarget");
            self.confirmDetail = arguments[2];
            self.primaryActionTitle = T(self.language, @"startBackup");
            self.secondaryActionTitle = T(self.language, @"notNow");
            self.confirmResponsePath = arguments[3];
        }
    } else if (arguments.count > 1) {
        self.sentinelPath = arguments[1];
        if (arguments.count > 2) {
            self.progressPath = arguments[2];
        }
    }

    [NSApp setApplicationIconImage:CreateApplicationIcon()];
    [NSApp setActivationPolicy:self.confirmMode ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];

    NSSize size = NSMakeSize(392, 162);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2, NSMidY(screenFrame) - size.height / 2);

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.level = NSFloatingWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    TigerBackupView *contentView = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    __weak typeof(self) weakSelf = self;
    contentView.confirmMode = self.confirmMode;
    contentView.language = self.language;
    contentView.confirmTitle = self.confirmTitle;
    contentView.confirmDetail = self.confirmDetail;
    contentView.primaryActionTitle = self.primaryActionTitle;
    contentView.secondaryActionTitle = self.secondaryActionTitle;
    contentView.minimizeHandler = ^{
        [weakSelf minimizeWindow];
    };
    contentView.confirmHandler = ^(BOOL approved) {
        [weakSelf finishConfirmation:approved];
    };
    self.window.contentView = contentView;
    self.window.alphaValue = 0;
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        self.window.animator.alphaValue = 1;
    } completionHandler:nil];

    [NSApp activateIgnoringOtherApps:YES];

    if (self.confirmMode) {
        self.confirmTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:120.0
                                                                   repeats:NO
                                                                     block:^(NSTimer *timer) {
            [self finishConfirmation:NO];
        }];
    } else {
        self.sentinelTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
            [self checkSentinel];
        }];
        self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
            [self readProgressFile];
        }];
        [self readProgressFile];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.sentinelTimer invalidate];
    [self.confirmTimeoutTimer invalidate];
    [self.progressTimer invalidate];
    if (self.confirmMode && !self.confirmationAnswered) {
        [self writeConfirmation:NO];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.setupMode;
}

- (void)minimizeWindow {
    if (self.completing || !self.window.isVisible) {
        return;
    }

    self.hiddenByUser = YES;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        self.window.animator.alphaValue = 0;
    } completionHandler:^{
        [self.window orderOut:nil];
    }];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (self.completing) {
        [self.window orderFrontRegardless];
        return NO;
    }

    if (self.hiddenByUser || !flag) {
        [self restoreWindowFromDock];
        return NO;
    }

    return YES;
}

- (void)restoreWindowFromDock {
    self.hiddenByUser = NO;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    self.window.alphaValue = 0;
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        self.window.animator.alphaValue = 1;
    } completionHandler:^{
        if (!self.completing) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
    }];
}

- (void)finishConfirmation:(BOOL)approved {
    if (self.confirmationAnswered) {
        return;
    }

    self.confirmationAnswered = YES;
    [self.confirmTimeoutTimer invalidate];
    self.confirmTimeoutTimer = nil;
    [self writeConfirmation:approved];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.14;
        self.window.animator.alphaValue = 0;
    } completionHandler:^{
        [NSApp terminate:nil];
    }];
}

- (void)writeConfirmation:(BOOL)approved {
    if (!self.confirmResponsePath.length) {
        return;
    }

    NSString *decision = approved ? @"yes\n" : @"no\n";
    [decision writeToFile:self.confirmResponsePath
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
}

- (void)checkSentinel {
    if (!self.sentinelPath.length) {
        return;
    }

    if (![NSFileManager.defaultManager fileExistsAtPath:self.sentinelPath]) {
        [self showCompletionAndQuit];
    }
}

- (NSDictionary<NSString *, NSString *> *)parseProgressContent:(NSString *)content {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange range = [line rangeOfString:@"="];
        if (range.location == NSNotFound) {
            continue;
        }
        NSString *key = [line substringToIndex:range.location];
        NSString *value = [line substringFromIndex:range.location + 1];
        values[key] = value;
    }
    return values;
}

- (void)readProgressFile {
    if (!self.progressPath.length) {
        return;
    }

    NSString *content = [NSString stringWithContentsOfFile:self.progressPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (!content.length) {
        return;
    }

    NSDictionary<NSString *, NSString *> *values = [self parseProgressContent:content];
    TigerBackupView *contentView = (TigerBackupView *)self.window.contentView;

    NSString *label = values[@"label"];
    NSString *phase = values[@"phase"];
    if (label.length && phase.length) {
        contentView.progressTitle = [NSString stringWithFormat:@"%@ · %@", phase, label];
    } else if (label.length) {
        contentView.progressTitle = label;
    }

    NSString *detail = values[@"detail"];
    if (detail.length) {
        contentView.progressDetail = detail;
    }

    NSString *percent = values[@"percent"];
    if (percent.length) {
        contentView.progressPercent = MAX(0.0, MIN(100.0, percent.doubleValue));
    }

    contentView.needsDisplay = YES;
}

- (void)showCompletionAndQuit {
    if (self.completing) {
        return;
    }

    self.completing = YES;
    [self.sentinelTimer invalidate];
    self.sentinelTimer = nil;

    TigerBackupView *contentView = (TigerBackupView *)self.window.contentView;
    contentView.completed = YES;
    contentView.progressPercent = 100;
    contentView.needsDisplay = YES;

    BOOL wasHidden = self.hiddenByUser || !self.window.isVisible;
    self.hiddenByUser = NO;

    if (wasHidden) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        self.window.alphaValue = 0;
        [self.window makeKeyAndOrderFront:nil];
        [self.window orderFrontRegardless];
    } else {
        self.window.alphaValue = 1;
        [self.window orderFrontRegardless];
    }

    [NSApp activateIgnoringOtherApps:YES];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        self.window.animator.alphaValue = 1;
    } completionHandler:^{
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }];

    [NSTimer scheduledTimerWithTimeInterval:8.0
                                    repeats:NO
                                      block:^(NSTimer *timer) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            self.window.animator.alphaValue = 0;
        } completionHandler:^{
            [NSApp terminate:nil];
        }];
    }];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
