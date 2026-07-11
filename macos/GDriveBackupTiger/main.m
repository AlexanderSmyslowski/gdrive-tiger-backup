#import <Cocoa/Cocoa.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>

#import "ConfigSupport.h"
#import "BackupStatusSupport.h"
#import "Localization.h"

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

static NSString *ScheduleAgentPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.commcats.gdrivebackup.schedule.plist"];
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
@property(nonatomic, copy) NSString *terminalStatus;
@property(nonatomic, copy) NSString *terminalDetail;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) NSString *confirmDetail;
@property(nonatomic, copy) NSString *primaryActionTitle;
@property(nonatomic, copy) NSString *secondaryActionTitle;
@property(nonatomic) CGFloat progressPercent;
@property(nonatomic, copy) NSString *progressTitle;
@property(nonatomic, copy) NSString *progressDetail;
@property(nonatomic, copy) void (^confirmHandler)(BOOL approved);
@property(nonatomic, strong) NSButton *primaryButton;
@property(nonatomic, strong) NSButton *secondaryButton;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL reduceMotion;
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
        self.titleLabel = [self nativeLabelWithFrame:NSMakeRect(76, 16, 300, 20)
                                                font:[NSFont fontWithName:@"Lucida Grande Bold" size:15] ?: [NSFont boldSystemFontOfSize:15]
                                               color:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0]];
        self.titleLabel.stringValue = @"Google Drive Backup";
        self.titleLabel.accessibilityLabel = self.titleLabel.stringValue;
        [self addSubview:self.titleLabel];

        self.statusLabel = [self nativeLabelWithFrame:NSMakeRect(112, 76, 250, 18)
                                                 font:[NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12]
                                                color:[NSColor colorWithCalibratedWhite:0.22 alpha:1.0]];
        [self addSubview:self.statusLabel];

        self.detailLabel = [self nativeLabelWithFrame:NSMakeRect(112, 133, 250, 16)
                                                 font:[NSFont fontWithName:@"Lucida Grande" size:10] ?: [NSFont systemFontOfSize:10]
                                                color:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];
        [self addSubview:self.detailLabel];

        self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(112, 106, 250, 19)];
        self.progressIndicator.style = NSProgressIndicatorStyleBar;
        self.progressIndicator.indeterminate = YES;
        self.progressIndicator.minValue = 0;
        self.progressIndicator.maxValue = 100;
        self.progressIndicator.accessibilityRole = NSAccessibilityProgressIndicatorRole;
        self.progressIndicator.accessibilityLabel = @"Backup progress";
        [self addSubview:self.progressIndicator];
        self.secondaryButton = [[NSButton alloc] initWithFrame:[self secondaryButtonRect]];
        self.secondaryButton.bezelStyle = NSBezelStyleRounded;
        self.secondaryButton.font = [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?: [NSFont boldSystemFontOfSize:11];
        self.secondaryButton.keyEquivalent = @"\e";
        self.secondaryButton.accessibilityRole = NSAccessibilityButtonRole;
        self.secondaryButton.target = self;
        self.secondaryButton.action = @selector(confirmSecondary:);
        self.secondaryButton.hidden = YES;
        [self addSubview:self.secondaryButton];

        self.primaryButton = [[NSButton alloc] initWithFrame:[self primaryButtonRect]];
        self.primaryButton.bezelStyle = NSBezelStyleRounded;
        self.primaryButton.font = [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?: [NSFont boldSystemFontOfSize:11];
        self.primaryButton.keyEquivalent = @"\r";
        self.primaryButton.accessibilityRole = NSAccessibilityButtonRole;
        self.primaryButton.target = self;
        self.primaryButton.action = @selector(confirmPrimary:);
        self.primaryButton.hidden = YES;
        [self addSubview:self.primaryButton];

        self.secondaryButton.nextKeyView = self.primaryButton;
        self.primaryButton.nextKeyView = self.secondaryButton;
        _reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        [self startAnimationTimerIfNeeded];
        [self updateNativeLabels];
    }
    return self;
}

- (void)startAnimationTimerIfNeeded {
    if (self.reduceMotion || self.terminalStatus.length || self.timer) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0)
                                                 repeats:YES
                                                   block:^(NSTimer *timer) {
        (void)timer;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.phase = fmod(strongSelf.phase + 1.3, 360.0);
        strongSelf.needsDisplay = YES;
    }];
}

- (void)setReduceMotion:(BOOL)reduceMotion {
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
        [self.timer invalidate];
        self.timer = nil;
        [self.progressIndicator stopAnimation:nil];
    } else {
        [self startAnimationTimerIfNeeded];
        if (self.progressIndicator.indeterminate) {
            [self.progressIndicator startAnimation:nil];
        }
    }
    self.needsDisplay = YES;
}

- (NSTextField *)nativeLabelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    return label;
}

- (void)updateNativeLabels {
    NSString *language = self.language ?: @"en";
    NSString *status = self.progressTitle ?: T(language, @"running");
    NSString *detail = self.progressDetail ?: T(language, @"runningHint");
    if (self.confirmMode) {
        status = self.confirmTitle ?: T(language, @"confirmTarget");
        detail = self.confirmDetail ?: @"";
        self.detailLabel.frame = NSMakeRect(112, 98, 250, 16);
        // Confirmation details are usually filesystem paths. Middle truncation
        // preserves both the volume and final destination folder in the compact UI.
        self.detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    } else {
        self.detailLabel.frame = NSMakeRect(112, 133, 250, 16);
        self.detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        if ([self.terminalStatus isEqualToString:@"success"]) {
            status = T(language, @"completed");
            detail = T(language, @"completedHint");
        } else if ([self.terminalStatus isEqualToString:@"failure"]) {
            status = T(language, @"failed");
            detail = self.terminalDetail ?: T(language, @"failedHint");
        } else if ([self.terminalStatus isEqualToString:@"cancelled"]) {
            status = T(language, @"cancelled");
            detail = T(language, @"cancelledHint");
        } else if ([self.terminalStatus isEqualToString:@"skipped"]) {
            status = T(language, @"skipped");
            detail = T(language, @"skippedHint");
        }
    }
    self.statusLabel.stringValue = status ?: @"";
    self.detailLabel.stringValue = detail ?: @"";
    self.detailLabel.toolTip = self.detailLabel.stringValue;
    self.statusLabel.accessibilityLabel = self.statusLabel.stringValue;
    self.detailLabel.accessibilityLabel = self.detailLabel.stringValue;
    self.progressIndicator.accessibilityLabel = T(language, @"backupProgress");
}

- (void)setConfirmMode:(BOOL)confirmMode {
    _confirmMode = confirmMode;
    self.primaryButton.hidden = !confirmMode;
    self.secondaryButton.hidden = !confirmMode;
    self.progressIndicator.hidden = confirmMode;
    [self updateNativeLabels];
    self.needsDisplay = YES;
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy];
    [self updateNativeLabels];
}

- (void)setConfirmTitle:(NSString *)confirmTitle {
    _confirmTitle = [confirmTitle copy];
    [self updateNativeLabels];
}

- (void)setConfirmDetail:(NSString *)confirmDetail {
    _confirmDetail = [confirmDetail copy];
    [self updateNativeLabels];
}

- (void)setProgressTitle:(NSString *)progressTitle {
    _progressTitle = [progressTitle copy];
    [self updateNativeLabels];
}

- (void)setProgressDetail:(NSString *)progressDetail {
    _progressDetail = [progressDetail copy];
    [self updateNativeLabels];
}

- (void)setTerminalDetail:(NSString *)terminalDetail {
    _terminalDetail = [terminalDetail copy];
    [self updateNativeLabels];
    self.needsDisplay = YES;
}

- (void)setProgressPercent:(CGFloat)progressPercent {
    _progressPercent = progressPercent;
    BOOL indeterminate = progressPercent < 0;
    self.progressIndicator.indeterminate = indeterminate;
    if (!indeterminate) {
        self.progressIndicator.doubleValue = MAX(0.0, MIN(100.0, progressPercent));
    }
}

- (void)setPrimaryActionTitle:(NSString *)primaryActionTitle {
    _primaryActionTitle = [primaryActionTitle copy];
    self.primaryButton.title = _primaryActionTitle ?: @"";
    self.primaryButton.accessibilityLabel = self.primaryButton.title;
}

- (void)setSecondaryActionTitle:(NSString *)secondaryActionTitle {
    _secondaryActionTitle = [secondaryActionTitle copy];
    self.secondaryButton.title = _secondaryActionTitle ?: @"";
    self.secondaryButton.accessibilityLabel = self.secondaryButton.title;
}

- (void)confirmPrimary:(id)sender {
    (void)sender;
    if (self.confirmHandler) {
        self.confirmHandler(YES);
    }
}

- (void)confirmSecondary:(id)sender {
    (void)sender;
    if (self.confirmHandler) {
        self.confirmHandler(NO);
    }
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)setTerminalStatus:(NSString *)terminalStatus {
    _terminalStatus = [terminalStatus copy];
    self.completed = [_terminalStatus isEqualToString:@"success"];
    if (_terminalStatus.length) {
        [self.timer invalidate];
        self.timer = nil;
    }
    [self updateNativeLabels];
    self.needsDisplay = YES;
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

    if ([self.terminalStatus isEqualToString:@"success"]) {
        [self drawCheckmarkAt:NSMakePoint(58, 94)];
    } else if ([self.terminalStatus isEqualToString:@"failure"]) {
        [self drawFailureAt:NSMakePoint(58, 94)];
    } else if ([self.terminalStatus isEqualToString:@"cancelled"]) {
        [self drawCancelledAt:NSMakePoint(58, 94)];
    } else if ([self.terminalStatus isEqualToString:@"skipped"]) {
        [self drawSkippedAt:NSMakePoint(58, 94)];
    } else {
        [self drawSpinnerAt:NSMakePoint(58, 94)];
    }

    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithCalibratedWhite:0.36 alpha:0.42] setStroke];
    panel.lineWidth = 1.5;
    [panel stroke];
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

- (void)drawFailureAt:(NSPoint)center {
    NSBezierPath *badge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 28, center.y - 28, 56, 56)];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:1.0 green:0.48 blue:0.42 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.72 green:0.08 blue:0.06 alpha:1.0]
    ]];
    [gradient drawInBezierPath:badge angle:-90];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.55] setStroke];
    badge.lineWidth = 1.5;
    [badge stroke];

    NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross moveToPoint:NSMakePoint(center.x - 14, center.y - 14)];
    [cross lineToPoint:NSMakePoint(center.x + 14, center.y + 14)];
    [cross moveToPoint:NSMakePoint(center.x + 14, center.y - 14)];
    [cross lineToPoint:NSMakePoint(center.x - 14, center.y + 14)];
    [[NSColor whiteColor] setStroke];
    cross.lineWidth = 6;
    cross.lineCapStyle = NSLineCapStyleRound;
    [cross stroke];
}

- (void)drawCancelledAt:(NSPoint)center {
    NSBezierPath *badge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 28, center.y - 28, 56, 56)];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.34 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.83 green:0.43 blue:0.04 alpha:1.0]
    ]];
    [gradient drawInBezierPath:badge angle:-90];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.55] setStroke];
    badge.lineWidth = 1.5;
    [badge stroke];

    NSBezierPath *stop = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(center.x - 12, center.y - 12, 24, 24)
                                                          xRadius:4
                                                          yRadius:4];
    [[NSColor whiteColor] setFill];
    [stop fill];
}

- (void)drawSkippedAt:(NSPoint)center {
    NSBezierPath *badge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 28, center.y - 28, 56, 56)];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.82 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]
    ]];
    [gradient drawInBezierPath:badge angle:-90];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.55] setStroke];
    badge.lineWidth = 1.5;
    [badge stroke];

    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(center.x - 11, center.y - 14, 8, 28));
    NSRectFill(NSMakeRect(center.x + 3, center.y - 14, 8, 28));
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
    if ([self.terminalStatus isEqualToString:@"failure"]) {
        subtitle = T(language, @"failed");
        hint = self.terminalDetail ?: T(language, @"failedHint");
    } else if ([self.terminalStatus isEqualToString:@"cancelled"]) {
        subtitle = T(language, @"cancelled");
        hint = T(language, @"cancelledHint");
    } else if ([self.terminalStatus isEqualToString:@"skipped"]) {
        subtitle = T(language, @"skipped");
        hint = T(language, @"skippedHint");
    }
    [subtitle drawInRect:NSMakeRect(112, 76, 250, 18) withAttributes:subtitleAttributes];

    if (self.confirmMode) {
        [hint drawInRect:NSMakeRect(112, 98, 250, 16) withAttributes:hintAttributes];
    } else {
        [hint drawInRect:NSMakeRect(112, 133, 250, 16) withAttributes:hintAttributes];
    }
}

- (void)drawProgressBarInRect:(NSRect)rect {
    if (self.confirmMode) {
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
    } else if (self.terminalStatus.length && !self.completed) {
        fraction = 0.0;
    }
    NSRect fillRect = inner;
    fillRect.size.width = floor(NSWidth(inner) * fraction);

    NSArray<NSColor *> *colors = self.completed ? @[
        [NSColor colorWithCalibratedRed:0.43 green:0.90 blue:0.35 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.08 green:0.55 blue:0.18 alpha:1.0]
    ] : [self.terminalStatus isEqualToString:@"failure"] ? @[
        [NSColor colorWithCalibratedRed:1.0 green:0.48 blue:0.42 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.72 green:0.08 blue:0.06 alpha:1.0]
    ] : [self.terminalStatus isEqualToString:@"cancelled"] ? @[
        [NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.34 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.83 green:0.43 blue:0.04 alpha:1.0]
    ] : [self.terminalStatus isEqualToString:@"skipped"] ? @[
        [NSColor colorWithCalibratedWhite:0.72 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]
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

    NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 84, NSWidth(bounds) - 36, 292) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.54] setFill];
    [panel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.24] setStroke];
    panel.lineWidth = 1;
    [panel stroke];

    NSBezierPath *schedulePanel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 388, NSWidth(bounds) - 36, 52) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.42] setFill];
    [schedulePanel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.20] setStroke];
    [schedulePanel stroke];
}

@end

@interface TigerOverviewView : NSView
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSString *lastRunText;
@property(nonatomic, copy) NSString *lastRunDetail;
@property(nonatomic, copy) NSString *nextRunText;
@property(nonatomic, copy) NSString *targetText;
@property(nonatomic, copy) NSString *storageText;
@property(nonatomic, copy) void (^backupHandler)(void);
@property(nonatomic, copy) void (^settingsHandler)(void);
@property(nonatomic, strong) NSTextField *statusSymbolLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSTextField *lastRunCaptionLabel;
@property(nonatomic, strong) NSTextField *lastRunValueLabel;
@property(nonatomic, strong) NSTextField *lastRunDetailLabel;
@property(nonatomic, strong) NSTextField *nextRunCaptionLabel;
@property(nonatomic, strong) NSTextField *nextRunValueLabel;
@property(nonatomic, strong) NSTextField *targetCaptionLabel;
@property(nonatomic, strong) NSTextField *targetValueLabel;
@property(nonatomic, strong) NSTextField *storageCaptionLabel;
@property(nonatomic, strong) NSTextField *storageValueLabel;
@property(nonatomic, strong) NSButton *backupButton;
@property(nonatomic, strong) NSButton *settingsButton;
@end

@implementation TigerOverviewView

- (BOOL)isFlipped {
    return YES;
}

- (NSTextField *)overviewLabelWithFrame:(NSRect)frame
                                   font:(NSFont *)font
                                  color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    return label;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }

    self.wantsLayer = YES;
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
    NSColor *muted = [NSColor colorWithCalibratedWhite:0.38 alpha:1.0];
    NSFont *captionFont = [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?: [NSFont boldSystemFontOfSize:11];
    NSFont *valueFont = [NSFont fontWithName:@"Lucida Grande" size:13] ?: [NSFont systemFontOfSize:13];

    NSTextField *title = [self overviewLabelWithFrame:NSMakeRect(28, 18, 420, 28)
                                                 font:[NSFont fontWithName:@"Lucida Grande Bold" size:21] ?: [NSFont boldSystemFontOfSize:21]
                                                color:ink];
    title.stringValue = @"Google Drive Backup";
    title.accessibilityLabel = title.stringValue;
    [self addSubview:title];

    self.subtitleLabel = [self overviewLabelWithFrame:NSMakeRect(29, 48, 500, 20)
                                                  font:[NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12]
                                                 color:muted];
    [self addSubview:self.subtitleLabel];

    self.statusSymbolLabel = [self overviewLabelWithFrame:NSMakeRect(48, 108, 48, 48)
                                                      font:[NSFont fontWithName:@"Lucida Grande Bold" size:31] ?: [NSFont boldSystemFontOfSize:31]
                                                     color:ink];
    self.statusSymbolLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:self.statusSymbolLabel];

    self.lastRunCaptionLabel = [self overviewLabelWithFrame:NSMakeRect(116, 94, 180, 18)
                                                        font:captionFont color:muted];
    [self addSubview:self.lastRunCaptionLabel];
    self.lastRunValueLabel = [self overviewLabelWithFrame:NSMakeRect(116, 118, 440, 26)
                                                      font:[NSFont fontWithName:@"Lucida Grande Bold" size:18] ?: [NSFont boldSystemFontOfSize:18]
                                                     color:ink];
    [self addSubview:self.lastRunValueLabel];
    self.lastRunDetailLabel = [self overviewLabelWithFrame:NSMakeRect(116, 151, 440, 20)
                                                       font:valueFont color:muted];
    [self addSubview:self.lastRunDetailLabel];

    self.nextRunCaptionLabel = [self overviewLabelWithFrame:NSMakeRect(48, 232, 132, 19)
                                                        font:captionFont color:muted];
    [self addSubview:self.nextRunCaptionLabel];
    self.nextRunValueLabel = [self overviewLabelWithFrame:NSMakeRect(190, 230, 374, 22)
                                                      font:valueFont color:ink];
    [self addSubview:self.nextRunValueLabel];

    self.targetCaptionLabel = [self overviewLabelWithFrame:NSMakeRect(48, 273, 132, 19)
                                                       font:captionFont color:muted];
    [self addSubview:self.targetCaptionLabel];
    self.targetValueLabel = [self overviewLabelWithFrame:NSMakeRect(190, 271, 374, 22)
                                                     font:valueFont color:ink];
    [self addSubview:self.targetValueLabel];

    self.storageCaptionLabel = [self overviewLabelWithFrame:NSMakeRect(48, 314, 132, 19)
                                                        font:captionFont color:muted];
    [self addSubview:self.storageCaptionLabel];
    self.storageValueLabel = [self overviewLabelWithFrame:NSMakeRect(190, 312, 374, 22)
                                                      font:valueFont color:ink];
    [self addSubview:self.storageValueLabel];

    self.settingsButton = [[NSButton alloc] initWithFrame:NSMakeRect(342, 368, 118, 30)];
    self.settingsButton.bezelStyle = NSBezelStyleRounded;
    self.settingsButton.target = self;
    self.settingsButton.action = @selector(openSettings:);
    self.settingsButton.accessibilityRole = NSAccessibilityButtonRole;
    [self addSubview:self.settingsButton];

    self.backupButton = [[NSButton alloc] initWithFrame:NSMakeRect(470, 368, 124, 30)];
    self.backupButton.bezelStyle = NSBezelStyleRounded;
    self.backupButton.keyEquivalent = @"\r";
    self.backupButton.target = self;
    self.backupButton.action = @selector(startBackup:);
    self.backupButton.accessibilityRole = NSAccessibilityButtonRole;
    [self addSubview:self.backupButton];
    self.settingsButton.nextKeyView = self.backupButton;
    self.backupButton.nextKeyView = self.settingsButton;

    self.language = @"en";
    self.status = @"unknown";
    return self;
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    self.lastRunCaptionLabel.stringValue = T(_language, @"overviewLastRun");
    self.subtitleLabel.stringValue = T(_language, @"overviewSubtitle");
    self.subtitleLabel.accessibilityLabel = self.subtitleLabel.stringValue;
    self.nextRunCaptionLabel.stringValue = T(_language, @"overviewNextRun");
    self.targetCaptionLabel.stringValue = T(_language, @"overviewTarget");
    self.storageCaptionLabel.stringValue = T(_language, @"overviewStorage");
    self.settingsButton.title = T(_language, @"overviewSettings");
    self.backupButton.title = T(_language, @"backupNow");
    self.settingsButton.accessibilityLabel = self.settingsButton.title;
    self.backupButton.accessibilityLabel = self.backupButton.title;
    [self layoutActionButtons];
    [self updateValueAccessibilityLabels];
    [self setStatus:self.status ?: @"unknown"];
}

- (void)layoutActionButtons {
    CGFloat backupWidth = MAX(124.0, ceil(self.backupButton.cell.cellSize.width + 18.0));
    CGFloat settingsWidth = MAX(140.0, ceil(self.settingsButton.cell.cellSize.width + 18.0));
    CGFloat rightEdge = NSWidth(self.bounds) - 26.0;
    self.backupButton.frame = NSMakeRect(rightEdge - backupWidth, 368, backupWidth, 30);
    self.settingsButton.frame = NSMakeRect(NSMinX(self.backupButton.frame) - 10.0 - settingsWidth,
                                           368,
                                           settingsWidth,
                                           30);
}

- (void)setStatus:(NSString *)status {
    _status = [status copy] ?: @"unknown";
    NSDictionary<NSString *, NSArray *> *presentations = @{
        @"success": @[@"✓", [NSColor colorWithCalibratedRed:0.12 green:0.48 blue:0.17 alpha:1.0], @"completed"],
        @"failure": @[@"×", [NSColor colorWithCalibratedRed:0.70 green:0.10 blue:0.08 alpha:1.0], @"failed"],
        @"cancelled": @[@"■", [NSColor colorWithCalibratedRed:0.70 green:0.37 blue:0.03 alpha:1.0], @"cancelled"],
        @"running": @[@"↻", [NSColor colorWithCalibratedRed:0.05 green:0.32 blue:0.72 alpha:1.0], @"running"],
        @"interrupted": @[@"!", [NSColor colorWithCalibratedRed:0.68 green:0.28 blue:0.02 alpha:1.0], @"overviewStatusInterrupted"],
        @"unknown": @[@"?", [NSColor colorWithCalibratedWhite:0.38 alpha:1.0], @"overviewStatusUnknown"]
    };
    NSArray *presentation = presentations[_status] ?: presentations[@"unknown"];
    self.statusSymbolLabel.stringValue = presentation[0];
    self.statusSymbolLabel.textColor = presentation[1];
    self.statusSymbolLabel.accessibilityLabel = T(self.language ?: @"en", presentation[2]);
}

- (void)setLastRunText:(NSString *)lastRunText {
    _lastRunText = [lastRunText copy] ?: @"";
    self.lastRunValueLabel.stringValue = _lastRunText;
    [self updateValueAccessibilityLabels];
}

- (void)setLastRunDetail:(NSString *)lastRunDetail {
    _lastRunDetail = [lastRunDetail copy] ?: @"";
    self.lastRunDetailLabel.stringValue = _lastRunDetail;
    [self updateValueAccessibilityLabels];
}

- (void)setNextRunText:(NSString *)nextRunText {
    _nextRunText = [nextRunText copy] ?: @"";
    self.nextRunValueLabel.stringValue = _nextRunText;
    [self updateValueAccessibilityLabels];
}

- (void)setTargetText:(NSString *)targetText {
    _targetText = [targetText copy] ?: @"";
    self.targetValueLabel.stringValue = _targetText;
    [self updateValueAccessibilityLabels];
}

- (void)setStorageText:(NSString *)storageText {
    _storageText = [storageText copy] ?: @"";
    self.storageValueLabel.stringValue = _storageText;
    [self updateValueAccessibilityLabels];
}

- (void)updateValueAccessibilityLabels {
    NSString *language = self.language ?: @"en";
    self.lastRunValueLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
        T(language, @"overviewLastRun"), self.lastRunValueLabel.stringValue ?: @""];
    self.lastRunDetailLabel.accessibilityLabel = self.lastRunDetailLabel.stringValue ?: @"";
    self.nextRunValueLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
        T(language, @"overviewNextRun"), self.nextRunValueLabel.stringValue ?: @""];
    self.targetValueLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
        T(language, @"overviewTarget"), self.targetValueLabel.stringValue ?: @""];
    self.storageValueLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
        T(language, @"overviewStorage"), self.storageValueLabel.stringValue ?: @""];
}

- (void)startBackup:(id)sender {
    (void)sender;
    if (self.backupHandler) {
        self.backupHandler();
    }
}

- (void)openSettings:(id)sender {
    (void)sender;
    if (self.settingsHandler) {
        self.settingsHandler();
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;
    NSGradient *background = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.98 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.86 alpha:1.0]
    ]];
    [background drawInRect:bounds angle:-90];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.38] setFill];
    for (CGFloat y = 72; y < NSHeight(bounds); y += 5) {
        NSRectFill(NSMakeRect(0, y, NSWidth(bounds), 1));
    }

    for (NSValue *value in @[
        [NSValue valueWithRect:NSMakeRect(24, 82, NSWidth(bounds) - 48, 108)],
        [NSValue valueWithRect:NSMakeRect(24, 214, NSWidth(bounds) - 48, 132)]
    ]) {
        NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:value.rectValue xRadius:14 yRadius:14];
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.68] setFill];
        [panel fill];
        [[NSColor colorWithCalibratedWhite:0.42 alpha:0.30] setStroke];
        panel.lineWidth = 1;
        [panel stroke];
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *sentinelPath;
@property(nonatomic, copy) NSString *progressPath;
@property(nonatomic, copy) NSString *runStatePath;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic) BOOL setupMode;
@property(nonatomic) BOOL overviewMode;
@property(nonatomic) BOOL menubarOnlyMode;
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
@property(nonatomic) BOOL reduceMotion;
@property(nonatomic) BOOL voiceOverEnabled;
@property(nonatomic, strong) NSPopUpButton *targetPopup;
@property(nonatomic, strong) NSButton *encryptionCheckbox;
@property(nonatomic, strong) NSPopUpButton *mountedNasPopup;
@property(nonatomic, strong) NSPopUpButton *discoveredNasPopup;
@property(nonatomic, strong) NSPopUpButton *schedulePopup;
@property(nonatomic, strong) NSTextField *nasURLField;
@property(nonatomic, strong) NSTextField *nasMountField;
@property(nonatomic, strong) NSTextField *nasSubdirField;
@property(nonatomic, strong) NSTextField *statusField;
@property(nonatomic, strong) NSTextField *destinationPreviewField;
@property(nonatomic, strong) NSButton *setupBackupButton;
@property(nonatomic, strong) NSButton *setupDryRunButton;
@property(nonatomic) BOOL manualLaunchPending;
@property(nonatomic, copy) NSString *configuredAPFSVolumePath;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *overviewRefreshTimer;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *lastOverviewSnapshot;
@property(nonatomic) NSTimeInterval overviewRefreshInterval;
@property(nonatomic) BOOL overviewRefreshInFlight;
@property(nonatomic) BOOL overviewLaunchPending;
@property(nonatomic, copy) NSString *lastMountTriggerPath;
@property(nonatomic, strong) NSDate *lastMountTriggerDate;
@property(nonatomic, copy) NSString *terminalFailureReason;
@end

@implementation AppDelegate

- (NSString *)applicationModeForArguments:(NSArray<NSString *> *)arguments {
    if (arguments.count <= 1) {
        return @"overview";
    }
    NSString *argument = arguments[1];
    if ([argument isEqualToString:@"--setup"]) {
        return @"setup";
    }
    if ([argument isEqualToString:@"--confirm"]) {
        return @"confirm";
    }
    if ([argument isEqualToString:@"--menubar"]) {
        return @"menubar";
    }
    return @"progress";
}

- (BOOL)shouldInstallStatusItemForMode:(NSString *)mode {
    return [mode isEqualToString:@"overview"] || [mode isEqualToString:@"menubar"];
}

- (NSDateFormatter *)overviewDateFormatterWithCalendar:(NSCalendar *)calendar {
    NSDictionary<NSString *, NSString *> *localeIdentifiers = @{
        @"de": @"de_DE", @"en": @"en_US", @"fr": @"fr_FR", @"es": @"es_ES",
        @"ja": @"ja_JP", @"yue": @"zh_HK", @"ko": @"ko_KR"
    };
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:localeIdentifiers[self.language ?: @"en"] ?: @"en_US"];
    formatter.calendar = calendar;
    formatter.timeZone = calendar.timeZone;
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return formatter;
}

- (NSDictionary<NSString *, NSString *> *)overviewSnapshotForConfig:(NSDictionary<NSString *, NSString *> *)config
                                                          summaryPath:(NSString *)summaryPath
                                                                  now:(NSDate *)now
                                                             calendar:(NSCalendar *)calendar {
    NSString *language = self.language ?: @"en";
    NSDictionary<NSString *, NSString *> *summary = GDTReadBackupSummaryAtPath(summaryPath);
    NSString *status = GDTBackupSummaryStatusAtPath(summaryPath);
    NSDictionary<NSString *, NSString *> *statusKeys = @{
        @"success": @"completed",
        @"failure": @"failed",
        @"cancelled": @"cancelled",
        @"running": @"running",
        @"interrupted": @"overviewStatusInterrupted"
    };
    NSString *lastRun = nil;
    if ([status isEqualToString:@"unknown"]) {
        lastRun = summary.count ? T(language, @"overviewStatusUnknown") : T(language, @"overviewNeverRun");
    } else {
        lastRun = T(language, statusKeys[status] ?: @"overviewStatusUnknown");
    }

    NSString *timestamp = [status isEqualToString:@"running"] || [status isEqualToString:@"interrupted"]
        ? summary[@"started_at"] : summary[@"finished_at"];
    NSString *lastRunDetail = @"";
    if (timestamp.longLongValue > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.longLongValue];
        lastRunDetail = [[self overviewDateFormatterWithCalendar:calendar] stringFromDate:date] ?: @"";
    }

    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    NSString *nextRun = nil;
    if ([schedule isEqualToString:@"daily"]) {
        NSDate *nextDate = GDTNextDailyRunAfterDate(now, calendar);
        nextRun = [[self overviewDateFormatterWithCalendar:calendar] stringFromDate:nextDate];
    } else if ([schedule isEqualToString:@"login"]) {
        nextRun = T(language, @"scheduleLogin");
    } else if ([schedule isEqualToString:@"hourly"]) {
        // StartInterval does not expose a reliable wall-clock fire time, so the
        // overview states the cadence instead of inventing a precise timestamp.
        nextRun = T(language, @"scheduleHourly");
    } else {
        nextRun = T(language, @"scheduleManual");
    }

    NSString *destination = GDTBackupDestinationForConfig(config);
    NSString *target = destination.length
        ? [NSString stringWithFormat:@"%@ — %@", destination.lastPathComponent, destination]
        : T(language, @"overviewUnavailable");

    NSDictionary<NSString *, NSNumber *> *capacity =
        GDTStorageCapacityForPath(GDTBackupCapacityPathForConfig(config));
    NSString *storage = T(language, @"overviewUnavailable");
    if (capacity) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleDecimal;
        NSString *free = [formatter stringFromByteCount:capacity[@"freeBytes"].longLongValue];
        NSString *total = [formatter stringFromByteCount:capacity[@"totalBytes"].longLongValue];
        storage = [NSString stringWithFormat:T(language, @"overviewFreeOf"), free, total];
    }

    return @{
        @"status": status,
        @"lastRun": lastRun ?: @"",
        @"lastRunDetail": lastRunDetail,
        @"nextRun": nextRun ?: T(language, @"overviewUnavailable"),
        @"target": target,
        @"storage": storage
    };
}

- (void)applyOverviewSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                       toView:(TigerOverviewView *)view {
    NSString *status = snapshot[@"status"] ?: @"unknown";
    if (![status isEqualToString:@"running"]) {
        self.overviewLaunchPending = NO;
    }
    view.language = self.language ?: @"en";
    view.lastRunText = snapshot[@"lastRun"] ?: @"";
    view.lastRunDetail = snapshot[@"lastRunDetail"] ?: @"";
    view.nextRunText = snapshot[@"nextRun"] ?: @"";
    view.targetText = snapshot[@"target"] ?: @"";
    view.storageText = snapshot[@"storage"] ?: @"";
    view.status = status;
    view.backupButton.enabled = !self.overviewLaunchPending && ![status isEqualToString:@"running"];
}

- (NSMenuItem *)statusValueItemWithTitle:(NSString *)title value:(NSString *)value {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:
        [NSString stringWithFormat:@"%@: %@", title, value ?: @""] action:nil keyEquivalent:@""];
    item.enabled = NO;
    return item;
}

- (NSMenu *)statusMenuForSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot {
    NSString *language = self.language ?: @"en";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"GDrive Backup Tiger"];

    NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:T(language, @"overviewOpen")
                                                   action:@selector(showOverviewFromStatus:)
                                            keyEquivalent:@""];
    open.target = self;
    [menu addItem:open];
    [menu addItem:[NSMenuItem separatorItem]];

    NSString *lastRun = snapshot[@"lastRun"] ?: T(language, @"overviewNeverRun");
    NSString *detail = snapshot[@"lastRunDetail"] ?: @"";
    if (detail.length) {
        lastRun = [NSString stringWithFormat:@"%@ · %@", lastRun, detail];
    }
    [menu addItem:[self statusValueItemWithTitle:T(language, @"overviewLastRun") value:lastRun]];
    [menu addItem:[self statusValueItemWithTitle:T(language, @"overviewNextRun") value:snapshot[@"nextRun"]]];
    [menu addItem:[self statusValueItemWithTitle:T(language, @"overviewTarget") value:snapshot[@"target"]]];
    [menu addItem:[self statusValueItemWithTitle:T(language, @"overviewStorage") value:snapshot[@"storage"]]];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *backup = [[NSMenuItem alloc] initWithTitle:T(language, @"backupNow")
                                                     action:@selector(startOverviewBackup:)
                                              keyEquivalent:@""];
    backup.target = self;
    backup.enabled = !self.overviewLaunchPending &&
        ![snapshot[@"status"] isEqualToString:@"running"];
    [menu addItem:backup];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:T(language, @"overviewSettings")
                                                       action:@selector(showBackupSetup:)
                                                keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:T(language, @"quitMenu") action:@selector(terminate:) keyEquivalent:@"q"];
    return menu;
}

- (void)updateStatusItemPresentationForSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot {
    NSDictionary<NSString *, NSString *> *symbols = @{
        @"success": @"externaldrive.fill.badge.checkmark",
        @"failure": @"exclamationmark.triangle.fill",
        @"cancelled": @"stop.circle.fill",
        @"running": @"arrow.triangle.2.circlepath",
        @"interrupted": @"exclamationmark.circle.fill",
        @"unknown": @"externaldrive.fill"
    };
    NSString *status = snapshot[@"status"] ?: @"unknown";
    NSString *symbolName = symbols[status] ?: symbols[@"unknown"];
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                               accessibilityDescription:@"GDrive Backup Tiger"];
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.button.accessibilityLabel = [NSString stringWithFormat:@"GDrive Backup Tiger — %@",
        snapshot[@"lastRun"] ?: T(self.language ?: @"en", @"overviewStatusUnknown")];
}

- (void)updateOverviewRefreshTimerForStatus:(NSString *)status {
    NSTimeInterval interval = [status isEqualToString:@"running"] ? 2.0 : 30.0;
    if (self.overviewRefreshTimer && fabs(self.overviewRefreshInterval - interval) < 0.01) {
        return;
    }
    [self.overviewRefreshTimer invalidate];
    self.overviewRefreshInterval = interval;
    __weak typeof(self) weakSelf = self;
    self.overviewRefreshTimer = [NSTimer timerWithTimeInterval:interval
                                                       repeats:YES
                                                         block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf refreshOverviewStatus:nil];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.overviewRefreshTimer forMode:NSRunLoopCommonModes];
}

- (void)installStatusItemIfNeeded {
    if (self.statusItem) return;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSDictionary<NSString *, NSString *> *placeholder = @{
        @"status": @"unknown",
        @"lastRun": T(self.language ?: @"en", @"overviewNeverRun"),
        @"lastRunDetail": @"",
        @"nextRun": T(self.language ?: @"en", @"overviewUnavailable"),
        @"target": T(self.language ?: @"en", @"overviewUnavailable"),
        @"storage": T(self.language ?: @"en", @"overviewUnavailable")
    };
    self.statusItem.menu = [self statusMenuForSnapshot:placeholder];
    self.statusItem.menu.delegate = self;
    [self updateStatusItemPresentationForSnapshot:placeholder];
    [self refreshOverviewStatus:nil];
}

- (void)refreshOverviewStatus:(id)sender {
    (void)sender;
    if (self.overviewRefreshInFlight) return;
    self.overviewRefreshInFlight = YES;
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *summaryPath = GDTBackupSummaryPath();
    NSCalendar *calendar = NSCalendar.autoupdatingCurrentCalendar;
    NSDate *now = [NSDate date];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSDictionary<NSString *, NSString *> *snapshot =
            [strongSelf overviewSnapshotForConfig:config summaryPath:summaryPath now:now calendar:calendar];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            innerSelf.overviewRefreshInFlight = NO;
            innerSelf.lastOverviewSnapshot = snapshot;
            if ([innerSelf.window.contentView isKindOfClass:TigerOverviewView.class]) {
                [innerSelf applyOverviewSnapshot:snapshot toView:(TigerOverviewView *)innerSelf.window.contentView];
            }
            if (innerSelf.statusItem) {
                innerSelf.statusItem.menu = [innerSelf statusMenuForSnapshot:snapshot];
                innerSelf.statusItem.menu.delegate = innerSelf;
                [innerSelf updateStatusItemPresentationForSnapshot:snapshot];
            }
            [innerSelf updateOverviewRefreshTimerForStatus:snapshot[@"status"]];
        });
    });
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self refreshOverviewStatus:nil];
}

- (BOOL)mountedVolumePath:(NSString *)mountedPath
             matchesConfig:(NSDictionary<NSString *, NSString *> *)config {
    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    BOOL activeAPFSTarget = [target isEqualToString:@"apfs"] ||
        [target isEqualToString:@"volume"] || [target isEqualToString:@"disk"];
    // NAS schedules and external-disk mount backups are independent. When NAS
    // is active, only an explicitly retained APFS path may trigger this path.
    NSString *configuredPath = activeAPFSTarget
        ? GDTBackupCapacityPathForConfig(config)
        : config[@"GDRIVE_BACKUP_VOLUME"];
    if (!mountedPath.length || !configuredPath.length) {
        return NO;
    }
    NSString *mounted = mountedPath.stringByStandardizingPath;
    NSString *configured = configuredPath.stringByStandardizingPath;
    if ([NSFileManager.defaultManager fileExistsAtPath:mounted]) {
        mounted = mounted.stringByResolvingSymlinksInPath;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:configured]) {
        configured = configured.stringByResolvingSymlinksInPath;
    }
    return [mounted isEqualToString:configured];
}

- (void)workspaceVolumeDidMount:(NSNotification *)notification {
    [self refreshOverviewStatus:notification];
    NSURL *volumeURL = notification.userInfo[NSWorkspaceVolumeURLKey];
    if (![volumeURL isKindOfClass:NSURL.class] || !volumeURL.isFileURL) {
        return;
    }
    NSDictionary<NSString *, NSString *> *config = [self savedSetupConfig];
    NSString *mountedPath = volumeURL.path.stringByStandardizingPath;
    if (![self mountedVolumePath:mountedPath matchesConfig:config]) {
        return;
    }

    NSDate *now = [NSDate date];
    if ([self.lastMountTriggerPath isEqualToString:mountedPath] &&
        self.lastMountTriggerDate &&
        [now timeIntervalSinceDate:self.lastMountTriggerDate] < 15.0) {
        return;
    }
    self.lastMountTriggerPath = mountedPath;
    self.lastMountTriggerDate = now;
    [self launchBackupWithArgument:@"--run" trigger:@"mount" assumeYes:NO];
}

- (void)showOverviewWindow {
    self.overviewMode = YES;
    self.menubarOnlyMode = NO;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMainMenu];
    [NSApp setApplicationIconImage:CreateApplicationIcon()];
    [self installStatusItemIfNeeded];

    if ([self.window.contentView isKindOfClass:TigerOverviewView.class]) {
        [self.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [self refreshOverviewStatus:nil];
        return;
    }

    NSSize size = NSMakeSize(620, 420);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2, NSMidY(screenFrame) - size.height / 2);
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"GDrive Backup Tiger";
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;

    TigerOverviewView *content = [[TigerOverviewView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    __weak typeof(self) weakSelf = self;
    content.backupHandler = ^{ [weakSelf startOverviewBackup:nil]; };
    content.settingsHandler = ^{ [weakSelf showBackupSetup:nil]; };
    self.window.contentView = content;
    NSDictionary<NSString *, NSString *> *placeholder = self.lastOverviewSnapshot ?: @{
        @"status": @"unknown",
        @"lastRun": T(self.language ?: @"en", @"overviewNeverRun"),
        @"lastRunDetail": @"",
        @"nextRun": T(self.language ?: @"en", @"overviewUnavailable"),
        @"target": T(self.language ?: @"en", @"overviewUnavailable"),
        @"storage": T(self.language ?: @"en", @"overviewUnavailable")
    };
    [self applyOverviewSnapshot:placeholder toView:content];
    [self.window makeFirstResponder:content.backupButton];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshOverviewStatus:nil];
}

- (void)showOverviewFromStatus:(id)sender {
    (void)sender;
    [self showOverviewWindow];
}

- (void)showBackupSetup:(id)sender {
    (void)sender;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (![bundlePath.pathExtension.lowercaseString isEqualToString:@"app"]) {
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments = @[@"-n", bundlePath, @"--args", @"--setup"];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)startOverviewBackup:(id)sender {
    (void)sender;
    if (self.overviewLaunchPending) {
        return;
    }
    self.overviewLaunchPending = YES;
    if (![self launchBackupWithArgument:@"--run" assumeYes:YES]) {
        self.overviewLaunchPending = NO;
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *snapshot =
        [self.lastOverviewSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
    snapshot[@"status"] = @"running";
    snapshot[@"lastRun"] = T(self.language ?: @"en", @"statusBackupStarted");
    snapshot[@"lastRunDetail"] = @"";
    self.lastOverviewSnapshot = snapshot;
    if ([self.window.contentView isKindOfClass:TigerOverviewView.class]) {
        [self applyOverviewSnapshot:snapshot toView:(TigerOverviewView *)self.window.contentView];
    }
    [self updateOverviewRefreshTimerForStatus:@"running"];
}

- (CGFloat)animationDuration:(CGFloat)duration {
    return self.reduceMotion ? 0 : duration;
}

- (NSWindowStyleMask)statusWindowStyleMask {
    return NSWindowStyleMaskTitled |
        NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable |
        NSWindowStyleMaskFullSizeContentView;
}

- (NSTimeInterval)confirmationTimeout {
    return self.voiceOverEnabled ? 0 : 120.0;
}

- (NSTimeInterval)terminalDisplayDuration {
    return self.voiceOverEnabled ? 0 : 8.0;
}

- (void)setReduceMotion:(BOOL)reduceMotion {
    _reduceMotion = reduceMotion;
    if ([self.window.contentView isKindOfClass:TigerBackupView.class]) {
        ((TigerBackupView *)self.window.contentView).reduceMotion = reduceMotion;
    }
}

- (void)accessibilityDisplayOptionsChanged:(NSNotification *)notification {
    (void)notification;
    self.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.voiceOverEnabled = NSWorkspace.sharedWorkspace.isVoiceOverEnabled;
}

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

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"GDrive Backup Tiger"];
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:T(self.language, @"aboutMenu")
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    aboutItem.target = self;
    [appMenu addItem:aboutItem];

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:T(self.language, @"settingsMenu")
                                                          action:@selector(showSettings:)
                                                   keyEquivalent:@","];
    settingsItem.target = self;
    settingsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [appMenu addItem:settingsItem];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:T(self.language, @"hideMenu") action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:T(self.language, @"quitMenu") action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)showAbout:(id)sender {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"GDrive Backup Tiger";
    alert.informativeText = [NSString stringWithFormat:@"Version %@\nmacOS launchd Google Drive backup with external disk and NAS support.", version];
    [alert addButtonWithTitle:T(self.language, @"done")];
    [alert runModal];
}

- (void)showSettings:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(self.language, @"settingsTitle");
    alert.informativeText = T(self.language, @"languageSetting");

    NSPopUpButton *languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 240, 28)];
    for (NSString *code in SupportedLanguageCodes()) {
        [languagePopup addItemWithTitle:LanguageDisplayName(code)];
        languagePopup.lastItem.representedObject = code;
        if ([code isEqualToString:self.language]) {
            [languagePopup selectItem:languagePopup.lastItem];
        }
    }
    alert.accessoryView = languagePopup;
    [alert addButtonWithTitle:T(self.language, @"done")];
    [alert addButtonWithTitle:T(self.language, @"cancel")];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSString *selectedLanguage = languagePopup.selectedItem.representedObject ?: @"en";
    NSError *error = nil;
    if (!GDTWriteConfigUpdates(@{@"GDRIVE_BACKUP_LANG": selectedLanguage}, &error)) {
        self.statusField.stringValue = error.localizedDescription ?: @"Save failed.";
        return;
    }

    self.language = selectedLanguage;
    [self buildMainMenu];
    if (self.setupMode) {
        [self.window orderOut:nil];
        self.window = nil;
        [self showSetupWindow];
    }
}

- (void)showSetupWindow {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMainMenu];
    [NSApp setApplicationIconImage:CreateApplicationIcon()];

    NSSize size = NSMakeSize(610, 500);
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

    NSMutableDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *configuredTarget = [config[@"GDRIVE_BACKUP_TARGET"] lowercaseString];
    NSString *target = configuredTarget.length ? configuredTarget : @"apfs";
    BOOL preserveConfiguredAPFSTarget = [configuredTarget isEqualToString:@"apfs"];
    NSString *encryption = [config[@"GDRIVE_BACKUP_ENCRYPTION"] ?: @"none" lowercaseString];
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    NSString *configuredVolumeName = config[@"GDRIVE_BACKUP_VOLUME_NAME"] ?: @"GoogleDrive-Backup";
    self.configuredAPFSVolumePath = config[@"GDRIVE_BACKUP_VOLUME"] ?: [@"/Volumes" stringByAppendingPathComponent:configuredVolumeName];

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
    self.targetPopup.target = self;
    self.targetPopup.action = @selector(targetChanged:);
    [content addSubview:self.targetPopup];

    [content addSubview:[self label:T(self.language, @"destinationPreview") frame:NSMakeRect(34, 134, 124, 22)]];
    self.destinationPreviewField = [self fieldWithFrame:NSMakeRect(164, 130, 400, 26)];
    self.destinationPreviewField.editable = NO;
    self.destinationPreviewField.selectable = YES;
    self.destinationPreviewField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.destinationPreviewField.accessibilityRole = NSAccessibilityStaticTextRole;
    [content addSubview:self.destinationPreviewField];

    self.encryptionCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(164, 164, 400, 24)];
    self.encryptionCheckbox.buttonType = NSButtonTypeSwitch;
    self.encryptionCheckbox.title = T(self.language, @"encryptionAPFS");
    self.encryptionCheckbox.toolTip = T(self.language, @"encryptionAPFSTip");
    self.encryptionCheckbox.accessibilityHelp = self.encryptionCheckbox.toolTip;
    self.encryptionCheckbox.state = [encryption isEqualToString:@"apfs"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.encryptionCheckbox.font = [NSFont fontWithName:@"Lucida Grande" size:12] ?: [NSFont systemFontOfSize:12];
    [content addSubview:self.encryptionCheckbox];

    [content addSubview:[self label:T(self.language, @"mountedNas") frame:NSMakeRect(34, 200, 124, 22)]];
    self.mountedNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 196, 270, 28)];
    self.mountedNasPopup.target = self;
    self.mountedNasPopup.action = @selector(selectMountedNAS:);
    [content addSubview:self.mountedNasPopup];
    [content addSubview:[self button:T(self.language, @"refresh") frame:NSMakeRect(444, 196, 120, 28) action:@selector(refreshMountedNAS:)]];

    [content addSubview:[self label:T(self.language, @"nasUrl") frame:NSMakeRect(34, 238, 124, 22)]];
    self.nasURLField = [self fieldWithFrame:NSMakeRect(164, 234, 270, 26)];
    self.nasURLField.stringValue = config[@"GDRIVE_BACKUP_NAS_URL"] ?: @"";
    self.nasURLField.delegate = self;
    [content addSubview:self.nasURLField];
    [content addSubview:[self button:T(self.language, @"openFinder") frame:NSMakeRect(444, 233, 120, 28) action:@selector(openNASInFinder:)]];

    [content addSubview:[self label:T(self.language, @"nasMount") frame:NSMakeRect(34, 274, 124, 22)]];
    self.nasMountField = [self fieldWithFrame:NSMakeRect(164, 270, 270, 26)];
    self.nasMountField.stringValue = config[@"GDRIVE_BACKUP_NAS_MOUNT"] ?: @"";
    self.nasMountField.delegate = self;
    [content addSubview:self.nasMountField];

    [content addSubview:[self label:T(self.language, @"nasSubdir") frame:NSMakeRect(34, 310, 124, 22)]];
    self.nasSubdirField = [self fieldWithFrame:NSMakeRect(164, 306, 270, 26)];
    self.nasSubdirField.stringValue = config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup";
    self.nasSubdirField.delegate = self;
    [content addSubview:self.nasSubdirField];

    self.discoveredNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 342, 270, 28)];
    [self.discoveredNasPopup addItemWithTitle:@"Bonjour"];
    self.discoveredNasPopup.target = self;
    self.discoveredNasPopup.action = @selector(selectDiscoveredNAS:);
    [content addSubview:self.discoveredNasPopup];
    [content addSubview:[self button:T(self.language, @"discover") frame:NSMakeRect(444, 342, 120, 28) action:@selector(discoverNAS:)]];

    [content addSubview:[self label:T(self.language, @"schedule") frame:NSMakeRect(34, 404, 124, 22)]];
    self.schedulePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 400, 270, 28)];
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

    self.statusField = [self label:T(self.language, @"statusReady") frame:NSMakeRect(26, 458, 270, 20)];
    self.statusField.textColor = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    [content addSubview:self.statusField];

    NSButton *saveButton = [self button:T(self.language, @"save") frame:NSMakeRect(282, 453, 88, 30) action:@selector(saveSetup:)];
    self.setupDryRunButton = [self button:T(self.language, @"dryRun") frame:NSMakeRect(378, 453, 112, 30) action:@selector(startDryRun:)];
    self.setupDryRunButton.toolTip = T(self.language, @"dryRunTip");
    self.setupBackupButton = [self button:T(self.language, @"backupNow") frame:NSMakeRect(498, 453, 88, 30) action:@selector(startBackupNow:)];
    self.setupBackupButton.toolTip = T(self.language, @"backupNowTip");
    [content addSubview:saveButton];
    [content addSubview:self.setupDryRunButton];
    [content addSubview:self.setupBackupButton];

    [self refreshMountedNASAllowingTargetAutoSelection:!preserveConfiguredAPFSTarget];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)targetChanged:(id)sender {
    (void)sender;
    [self updateTargetControls];
}

- (void)updateTargetControls {
    NSString *target = self.targetPopup.selectedItem.representedObject ?: @"apfs";
    BOOL isAPFSTarget = [target isEqualToString:@"apfs"];
    self.encryptionCheckbox.enabled = isAPFSTarget;
    [self updateDestinationPreview];
}

- (void)updateDestinationPreview {
    if (!self.destinationPreviewField) {
        return;
    }
    NSString *destination = GDTBackupDestinationForConfig([self currentSetupUpdates]);
    if (!destination.length) {
        destination = T(self.language ?: @"en", @"overviewUnavailable");
    }
    self.destinationPreviewField.stringValue = destination;
    self.destinationPreviewField.toolTip = destination;
    self.destinationPreviewField.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
        T(self.language ?: @"en", @"destinationPreview"), destination];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateDestinationPreview];
}

- (void)refreshMountedNAS:(id)sender {
    (void)sender;
    [self refreshMountedNASAllowingTargetAutoSelection:YES];
}

- (void)refreshMountedNASAllowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
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
        if (allowAutomaticTargetSelection && !currentMount.length && wantedHost.length && [volumeHost isEqualToString:wantedHost]) {
            autoSelection = volume;
            [self.mountedNasPopup selectItem:self.mountedNasPopup.lastItem];
        }
    }

    if (allowAutomaticTargetSelection && !currentMount.length && !autoSelection && volumes.count == 1) {
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
    [self updateTargetControls];
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
    [self updateTargetControls];
}

- (void)selectDiscoveredNAS:(id)sender {
    NSDictionary *service = self.discoveredNasPopup.selectedItem.representedObject;
    NSString *url = service[@"url"];
    if (url.length) {
        self.nasURLField.stringValue = url;
        [self.targetPopup selectItemAtIndex:1];
        [self updateTargetControls];
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
            (void)timer;
            [self refreshMountedNAS:nil];
        }];
        [NSTimer scheduledTimerWithTimeInterval:6.0 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
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
    BOOL requiresEncryptedAPFS = [target isEqualToString:@"apfs"] && self.encryptionCheckbox.state == NSControlStateValueOn;
    updates[@"GDRIVE_BACKUP_ENCRYPTION"] = requiresEncryptedAPFS ? @"apfs" : @"none";

    if ([target isEqualToString:@"nas"]) {
        updates[@"GDRIVE_BACKUP_NAS_MOUNT"] = self.nasMountField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_URL"] = self.nasURLField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_SUBDIR"] = self.nasSubdirField.stringValue.length ? self.nasSubdirField.stringValue : @"GoogleDrive-Backup";
        updates[@"GDRIVE_BACKUP_NAS_START_ON_MOUNT"] = @"0";
    } else {
        updates[@"GDRIVE_BACKUP_VOLUME"] = self.configuredAPFSVolumePath.length
            ? self.configuredAPFSVolumePath
            : @"/Volumes/GoogleDrive-Backup";
    }
    return updates;
}

- (NSDictionary<NSString *, NSString *> *)savedSetupConfig {
    return GDTReadConfigDictionary();
}

- (BOOL)setupUpdatesMatchSavedConfig:(NSDictionary<NSString *, NSString *> *)updates
                         savedConfig:(NSDictionary<NSString *, NSString *> *)savedConfig {
    NSDictionary<NSString *, NSString *> *defaults = @{
        @"GDRIVE_BACKUP_TARGET": @"apfs",
        @"GDRIVE_BACKUP_SCHEDULE": @"manual",
        @"GDRIVE_BACKUP_ENCRYPTION": @"none",
        @"GDRIVE_BACKUP_NAS_MOUNT": @"",
        @"GDRIVE_BACKUP_NAS_URL": @"",
        @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
        @"GDRIVE_BACKUP_NAS_START_ON_MOUNT": @"0",
        @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup"
    };
    NSSet<NSString *> *caseInsensitiveKeys = [NSSet setWithArray:@[
        @"GDRIVE_BACKUP_TARGET", @"GDRIVE_BACKUP_SCHEDULE", @"GDRIVE_BACKUP_ENCRYPTION"
    ]];
    for (NSString *key in updates) {
        NSString *current = updates[key] ?: @"";
        NSString *saved = savedConfig[key] ?: defaults[key] ?: @"";
        if ([caseInsensitiveKeys containsObject:key]) {
            current = current.lowercaseString;
            saved = saved.lowercaseString;
        }
        if (![current isEqualToString:saved]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)hasUnsavedSetupChanges {
    return ![self setupUpdatesMatchSavedConfig:[self currentSetupUpdates]
                                   savedConfig:[self savedSetupConfig]];
}

- (BOOL)saveSetupValues {
    NSError *error = nil;
    if (!GDTWriteConfigUpdates([self currentSetupUpdates], &error)) {
        self.statusField.stringValue = error.localizedDescription ?: @"Save failed.";
        return NO;
    }
    if (![self applySchedule:self.schedulePopup.selectedItem.representedObject ?: @"manual" error:&error]) {
        self.statusField.stringValue = error.localizedDescription ?: @"Schedule update failed.";
        return NO;
    }
    self.statusField.stringValue = T(self.language, @"statusSaved");
    return YES;
}

- (void)saveSetup:(id)sender {
    [self saveSetupValues];
}

- (void)startBackupNow:(id)sender {
    (void)sender;
    if (self.manualLaunchPending) {
        return;
    }
    if ([self hasUnsavedSetupChanges]) {
        self.statusField.stringValue = T(self.language, @"statusUnsavedChanges");
        return;
    }
    self.manualLaunchPending = YES;
    self.setupBackupButton.enabled = NO;
    self.setupDryRunButton.enabled = NO;
    self.statusField.stringValue = T(self.language, @"statusBackupPreparing");
    if (![self launchBackupWithArgument:@"--run" assumeYes:YES]) {
        self.manualLaunchPending = NO;
        self.setupBackupButton.enabled = YES;
        self.setupDryRunButton.enabled = YES;
        return;
    }
    [self dismissSetupAfterBackupLaunch];
}

- (void)dismissSetupAfterBackupLaunch {
    [self.window orderOut:nil];
    [NSApp terminate:nil];
}

- (void)startDryRun:(id)sender {
    (void)sender;
    if ([self hasUnsavedSetupChanges]) {
        self.statusField.stringValue = T(self.language, @"statusUnsavedChanges");
        return;
    }
    if ([self launchBackupWithArgument:@"--dry-run" assumeYes:YES]) {
        self.statusField.stringValue = T(self.language, @"statusDryRunStarted");
    }
}

- (BOOL)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    return [self launchBackupWithArgument:argument trigger:@"manual" assumeYes:assumeYes];
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"/usr/local/bin/backup-google-drive.sh", argument];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"HOME"] = NSHomeDirectory();
    environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    environment[@"GDRIVE_BACKUP_TRIGGER"] = trigger.length ? trigger : @"manual";
    if (assumeYes) {
        environment[@"BACKUP_ASSUME_YES"] = @"1";
    }
    task.environment = environment;
    @try {
        [task launch];
        return YES;
    } @catch (NSException *exception) {
        self.statusField.stringValue = exception.reason ?: @"Launch failed.";
        return NO;
    }
}

- (NSData *)schedulePlistDataForMode:(NSString *)mode error:(NSError **)error {
    NSMutableDictionary<NSString *, id> *plist = [@{
        @"Label": @"com.commcats.gdrivebackup.schedule",
        @"ProgramArguments": @[@"/bin/bash", @"/usr/local/bin/backup-google-drive.sh", @"--run"],
        @"EnvironmentVariables": @{
            @"HOME": NSHomeDirectory(),
            @"PATH": @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            @"GDRIVE_BACKUP_TRIGGER": @"schedule"
        }
    } mutableCopy];
    if ([mode isEqualToString:@"login"]) {
        plist[@"RunAtLoad"] = @YES;
    } else if ([mode isEqualToString:@"hourly"]) {
        plist[@"StartInterval"] = @3600;
    } else if ([mode isEqualToString:@"daily"]) {
        plist[@"StartCalendarInterval"] = @{@"Hour": @20, @"Minute": @0};
    }
    return [NSPropertyListSerialization dataWithPropertyList:plist
                                                       format:NSPropertyListXMLFormat_v1_0
                                                      options:0
                                                        error:error];
}

- (BOOL)applySchedule:(NSString *)mode error:(NSError **)error {
    NSString *path = ScheduleAgentPath();
    NSString *domain = [NSString stringWithFormat:@"gui/%d", getuid()];
    NSString *service = [domain stringByAppendingString:@"/com.commcats.gdrivebackup.schedule"];
    int status = 0;
    NSString *output = RunCommand(@"/bin/launchctl", @[@"print", service], nil, &status);
    if (status == 0) {
        output = RunCommand(@"/bin/launchctl", @[@"bootout", domain, path], nil, &status);
        if (status != 0) {
            if (error) {
                NSString *message = output.length ? output : @"launchctl bootout failed.";
                *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.schedule"
                                              code:status
                                          userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
        RunCommand(@"/bin/launchctl", @[@"print", service], nil, &status);
        if (status == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.schedule"
                                              code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"The previous backup schedule is still loaded."}];
            }
            return NO;
        }
    }

    if (![mode isEqualToString:@"login"] && ![mode isEqualToString:@"hourly"] && ![mode isEqualToString:@"daily"]) {
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path]
                                             resultingItemURL:nil
                                                        error:error]) {
                return NO;
            }
        }
        return YES;
    }

    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
        return NO;
    }
    NSData *plistData = [self schedulePlistDataForMode:mode error:error];
    if (!plistData || ![plistData writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }

    output = RunCommand(@"/bin/launchctl", @[@"bootstrap", domain, path], nil, &status);
    if (status != 0) {
        if (error) {
            NSString *message = output.length ? output : @"launchctl bootstrap failed.";
            *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.schedule"
                                          code:status
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
    output = RunCommand(@"/bin/launchctl", @[@"enable", service], nil, &status);
    if (status != 0) {
        if (error) {
            NSString *message = output.length ? output : @"launchctl enable failed.";
            *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.schedule"
                                          code:status
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.voiceOverEnabled = NSWorkspace.sharedWorkspace.isVoiceOverEnabled;
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
           selector:@selector(accessibilityDisplayOptionsChanged:)
               name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
             object:nil];
    self.language = ConfiguredLanguage();
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSString *mode = [self applicationModeForArguments:arguments];
    if ([self shouldInstallStatusItemForMode:mode]) {
        self.overviewMode = YES;
        self.menubarOnlyMode = [mode isEqualToString:@"menubar"];
        [NSWorkspace.sharedWorkspace.notificationCenter
            addObserver:self
               selector:@selector(workspaceVolumeDidMount:)
                   name:NSWorkspaceDidMountNotification
                 object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter
            addObserver:self
               selector:@selector(refreshOverviewStatus:)
                   name:NSWorkspaceDidUnmountNotification
                 object:nil];
        [NSApp setApplicationIconImage:CreateApplicationIcon()];
        [NSApp setActivationPolicy:self.menubarOnlyMode
            ? NSApplicationActivationPolicyAccessory
            : NSApplicationActivationPolicyRegular];
        [self buildMainMenu];
        [self installStatusItemIfNeeded];
        if ([mode isEqualToString:@"overview"]) {
            [self showOverviewWindow];
        }
        return;
    }

    if ([mode isEqualToString:@"setup"]) {
        self.setupMode = YES;
        [self showSetupWindow];
        return;
    }

    if ([mode isEqualToString:@"confirm"]) {
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
        if (arguments.count > 3) {
            self.runStatePath = arguments[3];
        }
    }

    [NSApp setApplicationIconImage:CreateApplicationIcon()];
    [NSApp setActivationPolicy:self.confirmMode ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];

    NSSize size = NSMakeSize(392, 162);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2, NSMidY(screenFrame) - size.height / 2);

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                             styleMask:[self statusWindowStyleMask]
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.delegate = self;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.level = self.confirmMode ? NSFloatingWindowLevel : NSNormalWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    TigerBackupView *contentView = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    __weak typeof(self) weakSelf = self;
    contentView.confirmMode = self.confirmMode;
    contentView.reduceMotion = self.reduceMotion;
    contentView.language = self.language;
    contentView.confirmTitle = self.confirmTitle;
    contentView.confirmDetail = self.confirmDetail;
    contentView.primaryActionTitle = self.primaryActionTitle;
    contentView.secondaryActionTitle = self.secondaryActionTitle;
    contentView.confirmHandler = ^(BOOL approved) {
        [weakSelf finishConfirmation:approved];
    };
    self.window.contentView = contentView;
    self.window.alphaValue = 0;
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = [self animationDuration:0.22];
        self.window.animator.alphaValue = 1;
    } completionHandler:nil];

    if (self.confirmMode) {
        [NSApp activateIgnoringOtherApps:YES];
    }

    if (self.confirmMode) {
        NSTimeInterval timeout = [self confirmationTimeout];
        if (timeout > 0) {
            self.confirmTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                                                       repeats:NO
                                                                         block:^(NSTimer *timer) {
                (void)timer;
                [self finishConfirmation:NO];
            }];
        }
    } else {
        self.sentinelTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
            (void)timer;
            [self checkSentinel];
        }];
        self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
            (void)timer;
            [self readProgressFile];
        }];
        [self readProgressFile];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.sentinelTimer invalidate];
    [self.confirmTimeoutTimer invalidate];
    [self.progressTimer invalidate];
    [self.overviewRefreshTimer invalidate];
    if (self.statusItem) {
        [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
        self.statusItem = nil;
    }
    if (self.confirmMode && !self.confirmationAnswered) {
        [self writeConfirmation:NO];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.setupMode;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    if (self.overviewMode) {
        [self.window orderOut:nil];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        return NO;
    }
    if (self.setupMode) {
        return YES;
    }
    if (self.completing) {
        [NSApp terminate:nil];
        return NO;
    }
    if (self.confirmMode) {
        [self finishConfirmation:NO];
        return NO;
    }
    [self minimizeWindow];
    return NO;
}

- (BOOL)windowShouldMiniaturize:(NSWindow *)window {
    (void)window;
    if (self.setupMode || self.overviewMode) {
        return YES;
    }
    [self minimizeWindow];
    return NO;
}

- (void)minimizeWindow {
    if (self.completing || !self.window.isVisible) {
        return;
    }

    self.hiddenByUser = YES;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = [self animationDuration:0.18];
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
        context.duration = [self animationDuration:0.18];
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
        context.duration = [self animationDuration:0.14];
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
    if (self.runStatePath.length) {
        NSString *status = [self runStatusAtPath:self.runStatePath];
        if ([status isEqualToString:@"running"]) {
            return;
        }
        if ([status isEqualToString:@"pending"]) {
            if ([self processIdentifierAtPathIsAlive:self.sentinelPath]) {
                return;
            }
            [self showTerminalStateAndQuit:@"failure"];
            return;
        }
        if ([status isEqualToString:@"failure"]) {
            self.terminalFailureReason = [self runReasonAtPath:self.runStatePath];
        }
        if (![status isEqualToString:@"running"]) {
            [self showTerminalStateAndQuit:status];
        }
        return;
    }

    if (self.sentinelPath.length &&
        ![NSFileManager.defaultManager fileExistsAtPath:self.sentinelPath]) {
        [self showTerminalStateAndQuit:@"failure"];
    }
}

- (BOOL)processIdentifierAtPathIsAlive:(NSString *)path {
    if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return NO;
    }
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    NSString *pid = [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if (!pid.length || [pid rangeOfCharacterFromSet:nonDigits].location != NSNotFound || pid.integerValue <= 0) {
        return NO;
    }
    errno = 0;
    return kill((pid_t)pid.intValue, 0) == 0 || errno == EPERM;
}

- (NSString *)runReasonAtPath:(NSString *)path {
    if (!path.length) {
        return @"";
    }
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    NSDictionary<NSString *, NSString *> *values = [self parseProgressContent:content ?: @""];
    NSString *reason = values[@"reason"] ?: @"";
    NSSet<NSString *> *safeReasons = [NSSet setWithArray:@[@"destination_permission_denied"]];
    return [safeReasons containsObject:reason] ? reason : @"";
}

- (NSString *)localizedTerminalDetailForReason:(NSString *)reason {
    if ([reason isEqualToString:@"destination_permission_denied"]) {
        return T(self.language ?: @"en", @"failedPermissionHint");
    }
    return T(self.language ?: @"en", @"failedHint");
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

- (NSString *)runStatusAtPath:(NSString *)path {
    if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return @"pending";
    }
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (!content.length) {
        return @"pending";
    }
    NSDictionary<NSString *, NSString *> *values = [self parseProgressContent:content ?: @""];
    if (![values[@"protocol"] isEqualToString:@"1"]) {
        return @"failure";
    }
    NSString *pid = values[@"pid"] ?: @"";
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if (!pid.length) {
        return @"pending";
    }
    if ([pid rangeOfCharacterFromSet:nonDigits].location != NSNotFound || pid.integerValue <= 0) {
        return @"failure";
    }
    if ([values[@"status"] isEqualToString:@"success"] &&
        [values[@"exit_code"] isEqualToString:@"0"]) {
        return @"success";
    }
    NSSet<NSString *> *cancelExitCodes = [NSSet setWithArray:@[@"129", @"130", @"143"]];
    if ([values[@"status"] isEqualToString:@"cancelled"] &&
        [cancelExitCodes containsObject:values[@"exit_code"] ?: @""]) {
        return @"cancelled";
    }
    NSSet<NSString *> *skipReasons = [NSSet setWithArray:@[@"already_running", @"user_declined"]];
    if ([values[@"status"] isEqualToString:@"skipped"] &&
        [skipReasons containsObject:values[@"reason"] ?: @""] &&
        [values[@"exit_code"] isEqualToString:@"0"]) {
        return @"skipped";
    }
    if ([values[@"status"] isEqualToString:@"failure"] &&
        values[@"exit_code"].integerValue != 0) {
        return @"failure";
    }
    if ([values[@"status"] isEqualToString:@"running"] && !values[@"exit_code"]) {
        errno = 0;
        if (kill((pid_t)pid.intValue, 0) == 0 || errno == EPERM) {
            return @"running";
        }
        return @"failure";
    }
    return @"pending";
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
    [self showTerminalStateAndQuit:@"success"];
}

- (NSString *)terminalAnnouncementForStatus:(NSString *)status {
    if ([status isEqualToString:@"failure"] && self.terminalFailureReason.length) {
        return [NSString stringWithFormat:@"%@ %@",
                T(self.language ?: @"en", @"failed"),
                [self localizedTerminalDetailForReason:self.terminalFailureReason]];
    }
    NSDictionary<NSString *, NSArray<NSString *> *> *keys = @{
        @"success": @[@"completed", @"completedHint"],
        @"failure": @[@"failed", @"failedHint"],
        @"cancelled": @[@"cancelled", @"cancelledHint"],
        @"skipped": @[@"skipped", @"skippedHint"]
    };
    NSArray<NSString *> *statusKeys = keys[status] ?: keys[@"failure"];
    return [NSString stringWithFormat:@"%@ %@",
            T(self.language ?: @"en", statusKeys[0]),
            T(self.language ?: @"en", statusKeys[1])];
}

- (void)applyTerminalStatus:(NSString *)status toView:(TigerBackupView *)contentView {
    NSSet<NSString *> *knownStatuses = [NSSet setWithArray:@[@"success", @"failure", @"cancelled", @"skipped"]];
    NSString *resolvedStatus = [knownStatuses containsObject:status ?: @""] ? status : @"failure";
    if ([resolvedStatus isEqualToString:@"failure"] && self.terminalFailureReason.length) {
        contentView.terminalDetail = [self localizedTerminalDetailForReason:self.terminalFailureReason];
    }
    contentView.terminalStatus = resolvedStatus;
    if ([resolvedStatus isEqualToString:@"success"]) {
        contentView.progressPercent = 100;
    }
    contentView.needsDisplay = YES;
    if (self.voiceOverEnabled) {
        NSAccessibilityPostNotificationWithUserInfo(
            contentView.statusLabel,
            NSAccessibilityAnnouncementRequestedNotification,
            @{
                NSAccessibilityAnnouncementKey: [self terminalAnnouncementForStatus:resolvedStatus],
                NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)
            });
    }
}

- (void)showTerminalStateAndQuit:(NSString *)status {
    if (self.completing) {
        return;
    }

    self.completing = YES;
    [self.sentinelTimer invalidate];
    self.sentinelTimer = nil;

    TigerBackupView *contentView = (TigerBackupView *)self.window.contentView;
    [self applyTerminalStatus:status toView:contentView];

    BOOL wasHidden = self.hiddenByUser || !self.window.isVisible;
    self.hiddenByUser = NO;

    if (wasHidden) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        self.window.alphaValue = 0;
        [self.window orderFront:nil];
    } else {
        self.window.alphaValue = 1;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = [self animationDuration:0.22];
        self.window.animator.alphaValue = 1;
    } completionHandler:^{
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }];

    NSTimeInterval displayDuration = [self terminalDisplayDuration];
    if (displayDuration > 0) {
        [NSTimer scheduledTimerWithTimeInterval:displayDuration
                                        repeats:NO
                                          block:^(NSTimer *timer) {
            (void)timer;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = [self animationDuration:0.18];
                self.window.animator.alphaValue = 0;
            } completionHandler:^{
                [NSApp terminate:nil];
            }];
        }];
    }
}

@end

static int TrashPathsFromArguments(int argc, const char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: GDriveBackupTiger --trash PATH [...]\n");
        return 64;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    int result = 0;
    for (int index = 2; index < argc; index++) {
        NSString *path = [NSString stringWithUTF8String:argv[index]];
        if (!path.length) {
            fprintf(stderr, "Invalid filesystem path.\n");
            result = 64;
            continue;
        }

        NSError *error = nil;
        NSURL *trashedURL = nil;
        if (![fileManager trashItemAtURL:[NSURL fileURLWithPath:path]
                         resultingItemURL:&trashedURL
                                    error:&error]) {
            const char *message = error.localizedDescription.UTF8String ?: "Trash operation failed.";
            fprintf(stderr, "%s: %s\n", path.fileSystemRepresentation, message);
            result = 1;
        }
    }
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && [[NSString stringWithUTF8String:argv[1]] isEqualToString:@"--trash"]) {
            return TrashPathsFromArguments(argc, argv);
        }

        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
