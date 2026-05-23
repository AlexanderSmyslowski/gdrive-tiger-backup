#import <Cocoa/Cocoa.h>

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
        @"completedHint": @"Backup ist fertig."
    };
    NSDictionary<NSString *, NSString *> *en = @{
        @"confirmTarget": @"Use this volume?",
        @"startBackup": @"Start backup",
        @"notNow": @"Not now",
        @"running": @"Backup is running ...",
        @"completed": @"Backup completed.",
        @"runningHint": @"Please do not eject the disk.",
        @"completedHint": @"Backup is done."
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

@interface TigerBackupView : NSView
@property(nonatomic) CGFloat phase;
@property(nonatomic) BOOL completed;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) NSString *confirmDetail;
@property(nonatomic, copy) NSString *primaryActionTitle;
@property(nonatomic, copy) NSString *secondaryActionTitle;
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
    NSString *subtitle = self.confirmMode ? (self.confirmTitle ?: T(language, @"confirmTarget")) : (self.completed ? T(language, @"completed") : T(language, @"running"));
    NSString *hint = self.confirmMode ? (self.confirmDetail ?: @"") : (self.completed ? T(language, @"completedHint") : T(language, @"runningHint"));
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
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.55] setStroke];
    outer.lineWidth = 1;
    [outer stroke];

    NSRect inner = NSInsetRect(rect, 2, 2);
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:7 yRadius:7];
    NSArray<NSColor *> *colors = self.completed ? @[
        [NSColor colorWithCalibratedRed:0.43 green:0.90 blue:0.35 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.08 green:0.55 blue:0.18 alpha:1.0]
    ] : @[
        [NSColor colorWithCalibratedRed:0.18 green:0.70 blue:1.0 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.03 green:0.33 blue:0.90 alpha:1.0]
    ];
    NSGradient *blueGradient = [[NSGradient alloc] initWithColors:colors];
    [blueGradient drawInBezierPath:innerPath angle:-90];

    [NSGraphicsContext saveGraphicsState];
    [innerPath addClip];
    CGFloat spacing = 18;
    CGFloat offset = fmod(self.phase, spacing);
    [[[NSColor whiteColor] colorWithAlphaComponent:0.22] setFill];
    for (CGFloat x = -NSHeight(inner) * 2 - spacing + offset; x <= NSWidth(inner) + spacing; x += spacing) {
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

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *sentinelPath;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) NSString *confirmDetail;
@property(nonatomic, copy) NSString *primaryActionTitle;
@property(nonatomic, copy) NSString *secondaryActionTitle;
@property(nonatomic, copy) NSString *confirmResponsePath;
@property(nonatomic, strong) NSTimer *sentinelTimer;
@property(nonatomic, strong) NSTimer *confirmTimeoutTimer;
@property(nonatomic) BOOL hiddenByUser;
@property(nonatomic) BOOL completing;
@property(nonatomic) BOOL confirmationAnswered;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.language = ConfiguredLanguage();
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
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
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.sentinelTimer invalidate];
    [self.confirmTimeoutTimer invalidate];
    if (self.confirmMode && !self.confirmationAnswered) {
        [self writeConfirmation:NO];
    }
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

- (void)showCompletionAndQuit {
    if (self.completing) {
        return;
    }

    self.completing = YES;
    [self.sentinelTimer invalidate];
    self.sentinelTimer = nil;

    TigerBackupView *contentView = (TigerBackupView *)self.window.contentView;
    contentView.completed = YES;
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
