#import <Cocoa/Cocoa.h>
#import <Security/SecTask.h>
#import <UserNotifications/UserNotifications.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/file.h>
#include <unistd.h>

#import "ConfigSupport.h"
#import "ProfileSupport.h"
#import "BackupStatusSupport.h"
#import "BackupProgressSupport.h"
#import "NotificationSupport.h"
#import "SetupHealthSupport.h"
#import "RestoreSupport.h"
#import "RestoreBrowserView.h"
#import "DiagnosticsSupport.h"
#import "DiagnosticsView.h"
#import "UpdateSupport.h"
#import "Localization.h"
#import "NetworkMountSupport.h"
#import "AdHocStrings.h"

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
    NSData *data = nil;
    @try {
        [task launch];
        // A child can fill the pipe before it exits. Drain while it is running
        // so commands with verbose output cannot deadlock their caller.
        data = [pipe.fileHandleForReading readDataToEndOfFile];
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
        NSMutableDictionary<NSString *, NSString *> *volume = byPath[path];
        NSString *url = GDTPreferredNASRemountURL(
            volume[@"url"] ?: @"",
            source,
            [line containsString:@" (smbfs,"]);

        if (volume) {
            if (url.length) {
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
@property(nonatomic, copy) void (^cancelHandler)(void);
@property(nonatomic, strong) NSButton *primaryButton;
@property(nonatomic, strong) NSButton *secondaryButton;
@property(nonatomic, strong) NSButton *cancelButton;
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

        self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(242, 158, 120, 27)];
        self.cancelButton.bezelStyle = NSBezelStyleRounded;
        self.cancelButton.font = [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?: [NSFont boldSystemFontOfSize:11];
        self.cancelButton.keyEquivalent = @"\e";
        self.cancelButton.accessibilityRole = NSAccessibilityButtonRole;
        self.cancelButton.target = self;
        self.cancelButton.action = @selector(cancelBackup:);
        self.cancelButton.hidden = YES;
        [self addSubview:self.cancelButton];

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
        BOOL hasMultipleLines = [detail rangeOfString:@"\n"].location != NSNotFound;
        self.detailLabel.frame = NSMakeRect(112, 98, 250, hasMultipleLines ? 32 : 16);
        self.detailLabel.maximumNumberOfLines = hasMultipleLines ? 2 : 1;
        self.detailLabel.cell.wraps = hasMultipleLines;
        self.detailLabel.lineBreakMode = hasMultipleLines
            ? NSLineBreakByTruncatingTail
            : NSLineBreakByTruncatingMiddle;
    } else {
        self.detailLabel.frame = NSMakeRect(112, 133, 250, 16);
        self.detailLabel.maximumNumberOfLines = 1;
        self.detailLabel.cell.wraps = NO;
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
    self.cancelButton.title = T(language, @"cancelBackup");
    self.cancelButton.accessibilityLabel = self.cancelButton.title;
}

- (void)setConfirmMode:(BOOL)confirmMode {
    _confirmMode = confirmMode;
    self.primaryButton.hidden = !confirmMode;
    self.secondaryButton.hidden = !confirmMode;
    self.cancelButton.hidden = confirmMode || self.terminalStatus.length;
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

- (void)cancelBackup:(id)sender {
    (void)sender;
    if (self.cancelHandler) {
        self.cancelHandler();
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
    self.cancelButton.hidden = _terminalStatus.length || self.confirmMode;
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
        BOOL hasMultipleLines = [hint rangeOfString:@"\n"].location != NSNotFound;
        [hint drawInRect:NSMakeRect(112, 98, 250, hasMultipleLines ? 32 : 16)
          withAttributes:hintAttributes];
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
    return NSMakeRect(232, 137, 130, 27);
}

- (NSRect)secondaryButtonRect {
    return NSMakeRect(112, 137, 110, 27);
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

@interface TigerSetupHealthView : NSView
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSDictionary<NSString *, id> *snapshot;
@property(nonatomic) BOOL checking;
@property(nonatomic, copy) void (^checkHandler)(void);
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSButton *checkButton;
@property(nonatomic, copy) NSArray<NSTextField *> *rowTitleLabels;
@property(nonatomic, copy) NSArray<NSTextField *> *rowDetailLabels;
@property(nonatomic, copy) NSArray<NSTextField *> *rowSymbolLabels;
@end

@implementation TigerSetupHealthView

- (BOOL)isFlipped {
    return YES;
}

- (void)layoutControls {
    NSFont *buttonFont = self.checkButton.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
    CGFloat requiredWidth = [self.checkButton.title
        sizeWithAttributes:@{NSFontAttributeName: buttonFont}].width + 32.0;
    CGFloat buttonWidth = MIN(MAX(124.0, ceil(requiredWidth)), MAX(124.0, NSWidth(self.bounds) - 220.0));
    self.checkButton.frame = NSMakeRect(NSWidth(self.bounds) - buttonWidth - 8.0, 4.0,
                                        buttonWidth, 28.0);
    self.titleLabel.frame = NSMakeRect(8.0, 7.0,
        MAX(120.0, NSMinX(self.checkButton.frame) - 16.0), 18.0);
}

- (void)layout {
    [super layout];
    [self layoutControls];
}

- (NSTextField *)healthLabelWithFrame:(NSRect)frame
                                  font:(NSFont *)font
                                 color:(NSColor *)color {
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

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    NSFont *titleFont = [NSFont fontWithName:@"Lucida Grande Bold" size:11] ?:
        [NSFont boldSystemFontOfSize:11];
    NSFont *detailFont = [NSFont fontWithName:@"Lucida Grande" size:11] ?:
        [NSFont systemFontOfSize:11];
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.18 alpha:1.0];
    NSColor *muted = [NSColor colorWithCalibratedWhite:0.38 alpha:1.0];

    self.titleLabel = [self healthLabelWithFrame:NSMakeRect(8, 7, 250, 18)
                                            font:titleFont color:ink];
    self.titleLabel.accessibilityLabel = @"System check";
    [self addSubview:self.titleLabel];

    NSArray<NSString *> *titles = @[@"Tools", @"Google Drive", @"Backup destination"];
    NSMutableArray<NSTextField *> *titleLabels = [NSMutableArray array];
    NSMutableArray<NSTextField *> *detailLabels = [NSMutableArray array];
    NSMutableArray<NSTextField *> *symbolLabels = [NSMutableArray array];
    for (NSUInteger index = 0; index < titles.count; index++) {
        CGFloat y = 32.0 + index * 25.0;
        NSTextField *symbol = [self healthLabelWithFrame:NSMakeRect(8, y, 22, 18)
                                                    font:titleFont color:muted];
        symbol.stringValue = @"?";
        symbol.alignment = NSTextAlignmentCenter;
        symbol.accessibilityLabel = @"Not checked";
        [self addSubview:symbol];
        [symbolLabels addObject:symbol];

        NSTextField *title = [self healthLabelWithFrame:NSMakeRect(40, y, 126, 18)
                                                   font:titleFont color:ink];
        title.stringValue = titles[index];
        title.accessibilityLabel = title.stringValue;
        [self addSubview:title];
        [titleLabels addObject:title];

        NSTextField *detail = [self healthLabelWithFrame:NSMakeRect(172, y, 276, 18)
                                                    font:detailFont color:muted];
        detail.stringValue = @"Not checked";
        detail.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
            title.stringValue, detail.stringValue];
        [self addSubview:detail];
        [detailLabels addObject:detail];
    }
    self.rowTitleLabels = titleLabels;
    self.rowDetailLabels = detailLabels;
    self.rowSymbolLabels = symbolLabels;

    self.checkButton = [[NSButton alloc] initWithFrame:NSMakeRect(450, 4, 124, 28)];
    self.checkButton.bezelStyle = NSBezelStyleRounded;
    self.checkButton.title = @"Check setup";
    self.checkButton.target = self;
    self.checkButton.action = @selector(startCheck:);
    self.checkButton.accessibilityRole = NSAccessibilityButtonRole;
    self.checkButton.accessibilityLabel = self.checkButton.title;
    [self addSubview:self.checkButton];
    self.language = @"en";
    return self;
}

- (void)startCheck:(id)sender {
    (void)sender;
    if (self.checking || !self.checkHandler) {
        return;
    }
    self.checking = YES;
    self.checkHandler();
}

- (void)setChecking:(BOOL)checking {
    _checking = checking;
    self.checkButton.enabled = !checking;
    self.checkButton.title = T(self.language ?: @"en",
        checking ? @"setupCheckRunning" : @"setupCheckButton");
    self.checkButton.accessibilityLabel = self.checkButton.title;
    [self layoutControls];
    if (!checking) {
        [self applySnapshot:self.snapshot ?: @{}];
        return;
    }

    for (NSUInteger index = 0; index < self.rowSymbolLabels.count; index++) {
        NSTextField *symbolLabel = self.rowSymbolLabels[index];
        NSTextField *titleLabel = self.rowTitleLabels[index];
        NSTextField *detailLabel = self.rowDetailLabels[index];
        NSString *detail = T(self.language ?: @"en", @"setupCheckRunning");
        symbolLabel.stringValue = @"…";
        symbolLabel.textColor = [NSColor colorWithCalibratedRed:0.05 green:0.32 blue:0.72 alpha:1.0];
        symbolLabel.accessibilityLabel = detail;
        detailLabel.stringValue = detail;
        detailLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
            titleLabel.stringValue, detail];
    }
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    NSArray<NSString *> *titleKeys = @[
        @"setupCheckDependenciesLabel",
        @"setupCheckRemoteLabel",
        @"setupCheckDestinationLabel"
    ];
    for (NSUInteger index = 0; index < titleKeys.count; index++) {
        NSTextField *titleLabel = self.rowTitleLabels[index];
        titleLabel.stringValue = T(_language, titleKeys[index]);
        titleLabel.accessibilityLabel = titleLabel.stringValue;
    }
    self.checkButton.title = T(_language, @"setupCheckButton");
    self.checkButton.accessibilityLabel = self.checkButton.title;
    [self layoutControls];
    self.titleLabel.stringValue = T(_language, @"setupCheckSectionTitle");
    self.titleLabel.accessibilityLabel = self.titleLabel.stringValue;

    NSDictionary<NSString *, id> *snapshot = self.snapshot ?: @{
        @"dependencies": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"},
        @"remote": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"},
        @"destination": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"}
    };
    [self applySnapshot:snapshot];
}

- (void)applySnapshot:(NSDictionary<NSString *, id> *)snapshot {
    self.snapshot = snapshot;
    NSArray<NSString *> *rowKeys = @[@"dependencies", @"remote", @"destination"];
    NSDictionary<NSString *, NSArray *> *presentations = @{
        @"ready": @[@"✓", [NSColor colorWithCalibratedRed:0.10 green:0.48 blue:0.18 alpha:1.0]],
        @"failure": @[@"×", [NSColor colorWithCalibratedRed:0.70 green:0.10 blue:0.08 alpha:1.0]],
        @"blocked": @[@"—", [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]],
        @"checking": @[@"…", [NSColor colorWithCalibratedRed:0.05 green:0.32 blue:0.72 alpha:1.0]],
        @"unknown": @[@"?", [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]]
    };

    for (NSUInteger index = 0; index < rowKeys.count; index++) {
        NSDictionary<NSString *, id> *row = [snapshot[rowKeys[index]]
            isKindOfClass:NSDictionary.class] ? snapshot[rowKeys[index]] : @{};
        NSString *status = [row[@"status"] isKindOfClass:NSString.class]
            ? row[@"status"] : @"unknown";
        NSArray *presentation = presentations[status] ?: presentations[@"unknown"];
        NSString *detailKey = [row[@"detailKey"] isKindOfClass:NSString.class]
            ? row[@"detailKey"] : @"setupCheckNotRun";
        NSString *detail = T(self.language ?: @"en", detailKey);
        if ([detailKey isEqualToString:@"setupCheckDependenciesMissing"] &&
            [row[@"missing"] isKindOfClass:NSArray.class]) {
            NSMutableArray<NSString *> *missing = [NSMutableArray array];
            for (id value in row[@"missing"]) {
                if ([value isKindOfClass:NSString.class] && [value length]) {
                    [missing addObject:value];
                }
            }
            detail = [NSString stringWithFormat:detail,
                [missing componentsJoinedByString:@", "]];
        }

        NSTextField *symbolLabel = self.rowSymbolLabels[index];
        NSTextField *titleLabel = self.rowTitleLabels[index];
        NSTextField *detailLabel = self.rowDetailLabels[index];
        symbolLabel.stringValue = presentation[0];
        symbolLabel.textColor = presentation[1];
        symbolLabel.accessibilityLabel = detail;
        detailLabel.stringValue = detail;
        detailLabel.toolTip = detail;
        detailLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@",
            titleLabel.stringValue, detail];
    }
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

    NSBezierPath *profilePanel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 76, NSWidth(bounds) - 36, 44) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.42] setFill];
    [profilePanel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.20] setStroke];
    profilePanel.lineWidth = 1;
    [profilePanel stroke];

    NSBezierPath *healthPanel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 130, NSWidth(bounds) - 36, 116) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.42] setFill];
    [healthPanel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.20] setStroke];
    healthPanel.lineWidth = 1;
    [healthPanel stroke];

    NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 260, NSWidth(bounds) - 36, 292) xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.54] setFill];
    [panel fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.24] setStroke];
    panel.lineWidth = 1;
    [panel stroke];

    NSBezierPath *schedulePanel = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(18, 562, NSWidth(bounds) - 36, 106) xRadius:12 yRadius:12];
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
@property(nonatomic) BOOL progressVisible;
@property(nonatomic) CGFloat progressPercent;
@property(nonatomic, copy) NSString *progressSummary;
@property(nonatomic, copy) NSString *progressDetail;
@property(nonatomic, copy) void (^backupHandler)(void);
@property(nonatomic, copy) void (^settingsHandler)(void);
@property(nonatomic, copy) void (^restoreHandler)(void);
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
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSTextField *progressSummaryLabel;
@property(nonatomic, strong) NSTextField *progressPhaseLabel;
@property(nonatomic, strong) NSTextField *progressPercentLabel;
@property(nonatomic, strong) NSTextField *progressDetailLabel;
@property(nonatomic, strong) NSButton *backupButton;
@property(nonatomic, strong) NSButton *settingsButton;
@property(nonatomic, strong) NSButton *restoreButton;
@property(nonatomic, strong) NSPopUpButton *destinationPopup;
@property(nonatomic, strong) NSTextField *destinationCaption;
@property(nonatomic, strong) NSTextField *destinationHint;
@property(nonatomic, copy) void (^destinationHandler)(void);
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

    self.progressSummaryLabel = [self overviewLabelWithFrame:NSMakeRect(116, 174, 440, 18)
                                                         font:captionFont color:ink];
    [self addSubview:self.progressSummaryLabel];
    self.progressPhaseLabel = [self overviewLabelWithFrame:NSMakeRect(116, 194, 110, 18)
                                                       font:valueFont color:muted];
    [self addSubview:self.progressPhaseLabel];
    self.progressIndicator = [[NSProgressIndicator alloc]
        initWithFrame:NSMakeRect(232, 196, 200, 14)];
    self.progressIndicator.style = NSProgressIndicatorStyleBar;
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 100;
    self.progressIndicator.accessibilityRole = NSAccessibilityProgressIndicatorRole;
    [self addSubview:self.progressIndicator];
    self.progressPercentLabel = [self overviewLabelWithFrame:NSMakeRect(440, 193, 52, 18)
                                                         font:valueFont color:ink];
    [self addSubview:self.progressPercentLabel];
    self.progressDetailLabel = [self overviewLabelWithFrame:NSMakeRect(116, 216, 440, 18)
                                                        font:valueFont color:muted];
    self.progressDetailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.progressDetailLabel];

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

    self.storageCaptionLabel = [self overviewLabelWithFrame:NSMakeRect(48, 314, 180, 19)
                                                        font:captionFont color:muted];
    [self addSubview:self.storageCaptionLabel];
    self.storageValueLabel = [self overviewLabelWithFrame:NSMakeRect(238, 312, 326, 22)
                                                      font:valueFont color:ink];
    [self addSubview:self.storageValueLabel];

    self.settingsButton = [[NSButton alloc] initWithFrame:NSMakeRect(342, 368, 118, 30)];
    self.settingsButton.bezelStyle = NSBezelStyleRounded;
    self.settingsButton.target = self;
    self.settingsButton.action = @selector(openSettings:);
    self.settingsButton.accessibilityRole = NSAccessibilityButtonRole;
    [self addSubview:self.settingsButton];

    self.restoreButton = [[NSButton alloc] initWithFrame:NSMakeRect(214, 368, 118, 30)];
    self.restoreButton.bezelStyle = NSBezelStyleRounded;
    self.restoreButton.target = self;
    self.restoreButton.action = @selector(openRestore:);
    self.restoreButton.accessibilityRole = NSAccessibilityButtonRole;
    [self addSubview:self.restoreButton];

    self.backupButton = [[NSButton alloc] initWithFrame:NSMakeRect(470, 368, 124, 30)];
    self.backupButton.bezelStyle = NSBezelStyleRounded;
    self.backupButton.keyEquivalent = @"\r";
    self.backupButton.target = self;
    self.backupButton.action = @selector(startBackup:);
    self.backupButton.accessibilityRole = NSAccessibilityButtonRole;
    [self addSubview:self.backupButton];
    self.settingsButton.nextKeyView = self.restoreButton;
    self.restoreButton.nextKeyView = self.backupButton;
    self.backupButton.nextKeyView = self.settingsButton;

    self.destinationCaption = [self overviewLabelWithFrame:NSMakeRect(28, 394, 550, 20)
        font:captionFont color:ink];
    [self addSubview:self.destinationCaption];
    self.destinationPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 416, 420, 30)];
    self.destinationPopup.autoenablesItems = NO;
    self.destinationPopup.target = self;
    self.destinationPopup.action = @selector(destinationChanged:);
    [self addSubview:self.destinationPopup];
    self.destinationHint = [self overviewLabelWithFrame:NSMakeRect(28, 448, 566, 20)
        font:[NSFont systemFontOfSize:11] color:muted];
    [self addSubview:self.destinationHint];
    self.restoreButton.nextKeyView = self.destinationPopup;
    self.destinationPopup.nextKeyView = self.backupButton;
    for (NSView *field in @[self.nextRunCaptionLabel, self.nextRunValueLabel,
            self.targetCaptionLabel, self.targetValueLabel,
            self.storageCaptionLabel, self.storageValueLabel]) {
        NSRect position = field.frame;
        position.origin.y += 36;
        field.frame = position;
    }

    self.language = @"en";
    self.progressVisible = NO;
    self.progressPercent = -1.0;
    self.progressSummary = @"";
    self.progressDetail = @"";
    self.status = @"unknown";
    return self;
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    self.lastRunCaptionLabel.stringValue = T(_language, @"overviewLastRun");
    self.subtitleLabel.stringValue = T(_language, @"overviewSubtitle");
    self.subtitleLabel.accessibilityLabel = self.subtitleLabel.stringValue;
    self.nextRunCaptionLabel.stringValue = T(_language, @"overviewNextRun");
    self.targetCaptionLabel.stringValue = GDTAdHocText(_language, @"automatic");
    self.storageCaptionLabel.stringValue = GDTAdHocText(_language, @"storage");
    self.storageCaptionLabel.frame = NSMakeRect(48, 350, 230, 19);
    self.storageValueLabel.frame = NSMakeRect(290, 348, 274, 22);
    self.settingsButton.title = T(_language, @"overviewSettings");
    self.restoreButton.title = T(_language, @"restoreTitle");
    self.backupButton.title = T(_language, @"startBackup");
    self.destinationCaption.stringValue = GDTAdHocText(_language, @"choose");
    self.destinationPopup.accessibilityLabel = self.destinationCaption.stringValue;
    self.destinationHint.stringValue = GDTAdHocText(_language, @"once");
    self.settingsButton.accessibilityLabel = self.settingsButton.title;
    self.restoreButton.accessibilityLabel = self.restoreButton.title;
    self.backupButton.accessibilityLabel = self.backupButton.title;
    self.progressIndicator.accessibilityLabel = T(_language, @"backupProgressCurrentPhase");
    [self layoutActionButtons];
    [self updateValueAccessibilityLabels];
    [self updateProgressPresentation];
    [self setStatus:self.status ?: @"unknown"];
}

- (void)layoutActionButtons {
    CGFloat backupWidth = MAX(124.0, ceil(self.backupButton.cell.cellSize.width + 18.0));
    CGFloat settingsWidth = MAX(140.0, ceil(self.settingsButton.cell.cellSize.width + 18.0));
    CGFloat restoreWidth = MAX(140.0, ceil(self.restoreButton.cell.cellSize.width + 18.0));
    CGFloat rightEdge = NSWidth(self.bounds) - 26.0;
    self.backupButton.frame = NSMakeRect(rightEdge - backupWidth, 416, backupWidth, 30);
    self.destinationPopup.frame = NSMakeRect(24, 416, rightEdge - backupWidth - 34, 30);
    self.restoreButton.frame = NSMakeRect(NSMinX(self.backupButton.frame) - 10.0 - restoreWidth,
                                          476,
                                          restoreWidth,
                                          30);
    self.settingsButton.frame = NSMakeRect(NSMinX(self.restoreButton.frame) - 10.0 - settingsWidth,
                                           476,
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
    [self updateProgressPresentation];
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

- (void)setProgressVisible:(BOOL)progressVisible {
    _progressVisible = progressVisible;
    [self updateProgressPresentation];
}

- (void)setProgressPercent:(CGFloat)progressPercent {
    _progressPercent = progressPercent;
    [self updateProgressPresentation];
}

- (void)setProgressSummary:(NSString *)progressSummary {
    _progressSummary = [progressSummary copy] ?: @"";
    self.progressSummaryLabel.stringValue = _progressSummary;
    self.progressSummaryLabel.accessibilityLabel = _progressSummary;
}

- (void)setProgressDetail:(NSString *)progressDetail {
    _progressDetail = [progressDetail copy] ?: @"";
    self.progressDetailLabel.stringValue = _progressDetail;
    self.progressDetailLabel.accessibilityLabel = _progressDetail;
}

- (void)updateProgressPresentation {
    BOOL visible = self.progressVisible && [self.status isEqualToString:@"running"];
    for (NSView *progressView in @[
        self.progressSummaryLabel, self.progressPhaseLabel, self.progressIndicator,
        self.progressPercentLabel, self.progressDetailLabel
    ]) {
        progressView.hidden = !visible;
    }
    if (!visible) {
        [self.progressIndicator stopAnimation:nil];
        return;
    }
    BOOL indeterminate = self.progressPercent < 0.0;
    self.progressIndicator.indeterminate = indeterminate;
    if (indeterminate) {
        self.progressPercentLabel.stringValue = @"";
        [self.progressIndicator startAnimation:nil];
    } else {
        [self.progressIndicator stopAnimation:nil];
        CGFloat percent = MAX(0.0, MIN(100.0, self.progressPercent));
        self.progressIndicator.doubleValue = percent;
        self.progressPercentLabel.stringValue = [NSString stringWithFormat:@"%.0f %%", percent];
    }
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

- (void)destinationChanged:(id)sender {
    (void)sender;
    if (self.destinationHandler) self.destinationHandler();
}

- (void)openSettings:(id)sender {
    (void)sender;
    if (self.settingsHandler) {
        self.settingsHandler();
    }
}

- (void)openRestore:(id)sender {
    (void)sender;
    if (self.restoreHandler) {
        self.restoreHandler();
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
        [NSValue valueWithRect:NSMakeRect(24, 82, NSWidth(bounds) - 48, 160)],
        [NSValue valueWithRect:NSMakeRect(24, 250, NSWidth(bounds) - 48, 132)]
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

@interface GDTExplicitPopUpChoiceController : NSObject
@property(nonatomic, weak) NSPopUpButton *popup;
@property(nonatomic, weak) NSButton *confirmationButton;
@property(nonatomic) BOOL hasExplicitSelection;
- (void)choiceDidChange:(id)sender;
@end

@implementation GDTExplicitPopUpChoiceController

- (void)choiceDidChange:(id)sender {
    (void)sender;
    self.hasExplicitSelection =
        [self.popup.selectedItem.representedObject isKindOfClass:NSDictionary.class];
    self.confirmationButton.enabled = self.hasExplicitSelection;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSTextFieldDelegate, UNUserNotificationCenterDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *sentinelPath;
@property(nonatomic, copy) NSString *progressPath;
@property(nonatomic, copy) NSString *runStatePath;
@property(nonatomic) BOOL confirmMode;
@property(nonatomic) BOOL setupMode;
@property(nonatomic) BOOL overviewMode;
@property(nonatomic) BOOL menubarOnlyMode;
@property(nonatomic) BOOL progressForegroundMode;
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
@property(nonatomic, strong) NSPopUpButton *encryptionPopup;
@property(nonatomic, strong) NSTextField *cryptRemoteLabel;
@property(nonatomic, strong) NSTextField *cryptRemoteField;
@property(nonatomic, strong) NSPopUpButton *mountedNasPopup;
@property(nonatomic, strong) NSPopUpButton *discoveredNasPopup;
@property(nonatomic, strong) NSPopUpButton *schedulePopup;
@property(nonatomic, strong) NSButton *notificationCheckbox;
@property(nonatomic, strong) NSButton *successNotificationCheckbox;
@property(nonatomic, strong) NSTextField *nasURLField;
@property(nonatomic, strong) NSTextField *nasMountField;
@property(nonatomic, strong) NSTextField *nasSubdirField;
@property(nonatomic, strong) NSTextField *statusField;
@property(nonatomic, strong) NSTextField *destinationPreviewField;
@property(nonatomic, strong) NSButton *setupBackupButton;
@property(nonatomic, strong) NSButton *setupDryRunButton;
@property(nonatomic, strong) TigerSetupHealthView *setupHealthView;
@property(nonatomic, strong) GDTSetupHealthChecker *setupHealthChecker;
@property(nonatomic, strong) GDTProfileStore *profileStore;
@property(nonatomic, strong) NSPopUpButton *profilePopup;
@property(nonatomic, strong) NSButton *profileCreateButton;
@property(nonatomic, strong) NSButton *profileRenameButton;
@property(nonatomic, strong) NSButton *profileDeleteButton;
@property(nonatomic) BOOL setupHealthCheckInFlight;
@property(nonatomic) NSUInteger setupHealthGeneration;
@property(nonatomic) BOOL manualLaunchPending;
@property(nonatomic) BOOL dryRunPending;
@property(nonatomic, copy) NSString *configuredAPFSVolumePath;
@property(nonatomic, copy) NSString *configuredAPFSVolumeUUID;
@property(nonatomic, copy) NSString *setupContextStatusText;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSWindow *setupWindow;
@property(nonatomic) BOOL mountedNASRefreshInFlight;
@property(nonatomic) NSUInteger mountedNASRefreshGeneration;
@property(nonatomic) BOOL rebuildingSetupWindow;
@property(nonatomic, strong) NSWindow *restoreWindow;
@property(nonatomic, strong) GDTRestoreBrowserView *restoreView;
@property(nonatomic, strong) id restoreCatalog;
@property(nonatomic, strong) id restoreCopier;
@property(nonatomic) NSUInteger restoreLoadGeneration;
@property(nonatomic, strong) NSWindow *diagnosticsWindow;
@property(nonatomic, strong) GDTDiagnosticsView *diagnosticsView;
@property(nonatomic) NSUInteger diagnosticsGeneration;
@property(nonatomic, strong) GDTUpdateChecker *updateChecker;
@property(nonatomic) BOOL updateChecking;
@property(nonatomic, strong) GDTAutomaticUpdatePolicy *automaticUpdatePolicy;
@property(nonatomic) BOOL updateConsentRequested;
@property(nonatomic) NSUInteger updateConsentGeneration;
@property(nonatomic) NSUInteger updateConsentSnapshotGeneration;
@property(nonatomic) BOOL updateConsentOffered;
@property(nonatomic) BOOL updatePreferencesPresenting;
@property(nonatomic, copy) NSString *updateAuthorizationGeneration;
@property(nonatomic, strong) NSTimer *overviewRefreshTimer;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *lastOverviewSnapshot;
@property(nonatomic) NSTimeInterval overviewRefreshInterval;
@property(nonatomic) BOOL overviewRefreshInFlight;
@property(nonatomic) BOOL overviewLaunchPending;
@property(nonatomic, copy) NSString *adHocSelectedID;
@property(nonatomic, copy) NSDictionary *adHocRunChoice;
@property(nonatomic, copy) NSString *adHocSummaryPath;
@property(nonatomic) BOOL adHocInspectionPending;
@property(nonatomic) NSTimeInterval adHocRunStartedAt;
@property(nonatomic) NSUInteger adHocGeneration;
@property(nonatomic, copy) NSArray *adHocChoices;
@property(nonatomic, copy) NSString *lastMountTriggerPath;
@property(nonatomic, strong) NSDate *lastMountTriggerDate;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *mountedExternalVolumeDescriptorsByPath;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mountedExternalVolumeInspectionTokensByPath;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTimer *> *unknownExternalVolumeTimersByDiskID;
@property(nonatomic, strong) NSMutableSet<NSString *> *knownExternalDiskIDs;
@property(nonatomic, strong) NSMutableSet<NSString *> *notifiedUnknownExternalDiskIDs;
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingUnknownExternalDiskIDs;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *pendingUnknownExternalVolumeUUIDsByDiskID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *notifiedUnknownExternalVolumeUUIDsByDiskID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *unknownExternalVolumeDeliveryAttemptsByDiskID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTimer *> *unknownExternalVolumeRetryTimersByDiskID;
@property(nonatomic, copy) NSString *unknownExternalVolumeBootSessionIDCache;
@property(nonatomic, copy) NSString *terminalFailureReason;
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingBackupNotificationIdentifiers;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *
    pendingBackupNotificationKeysByProfileID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
    inFlightBackupNotificationDecisionsByProfileID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
    queuedBackupNotificationDecisionsByProfileID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *
    backupNotificationGenerationsByProfileID;
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingBackupSuccessIdentifiers;
@property(nonatomic, strong) NSMutableSet<NSString *> *automaticRetryIdentifiersInFlight;
- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision;
- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (BOOL)isBackupSuccessDecisionCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (BOOL)isBackupSuccessDecisionSourceCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp;
- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision;
- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision
                           completion:(void (^)(NSInteger status))completion;
- (NSString *)automaticRetryLockPath;
- (BOOL)automaticRetryLockIsAvailable;
- (NSString *)automaticRetrySummaryPathForProfileID:(NSString *)profileID;
- (NSDictionary<NSString *, NSString *> *)automaticRetrySummaryAtPath:(NSString *)path;
- (NSDictionary<NSString *, NSString *> *)automaticRetryDecisionForSummary:
    (NSDictionary<NSString *, NSString *> *)summary
                                                               summaryPath:(NSString *)summaryPath
                                                                 profileID:(NSString *)profileID;
- (NSTimeInterval)automaticRetryOriginForIdentifier:(NSString *)identifier
                                          profileID:(NSString *)profileID;
- (void)removeExactBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                      forProfileID:(NSString *)profileID;
- (void)removeDeliveredBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removePendingBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)enumeratePendingBackupNotificationRequestsWithCompletion:
    (void (^)(NSArray<UNNotificationRequest *> *requests))completion;
- (void)retireSupersededBackupNotificationForDecision:
    (NSDictionary<NSString *, NSString *> *)decision;
- (void)requestCancelBackup:(id)sender;
- (BOOL)cancelRunningBackup;
- (void)completeMountedNetworkVolumeDiscovery:
    (NSArray<NSDictionary<NSString *, NSString *> *> *)volumes
    generation:(NSUInteger)generation
    allowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection;
@end

static NSString *GDTSafeDestinationLabelComponent(NSString *value) {
    NSString *trimmed = [value ?: @""
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 255 ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        return @"";
    }
    return trimmed;
}

static BOOL GDTShouldDisplayManualRun(NSTimeInterval manualStartedAt,
    NSDictionary *automaticSummary, NSString *automaticStatus, BOOL manualPending) {
    if ([automaticStatus isEqual:@"running"]) return NO;
    return manualPending || manualStartedAt >= [automaticSummary[@"started_at"] doubleValue];
}

static NSString *GDTBackupTargetOverviewText(NSDictionary<NSString *, NSString *> *config,
                                             NSString *language) {
    NSString *rawTarget = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    BOOL isNAS = [@[@"nas", @"network", @"smb", @"afp", @"nfs"] containsObject:rawTarget];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    NSString *profileName = GDTSafeDestinationLabelComponent(config[@"GDRIVE_BACKUP_PROFILE_NAME"]);
    if (profileName.length && profileName.length <= 80 &&
        [profileName caseInsensitiveCompare:@"Default"] != NSOrderedSame) {
        [parts addObject:profileName];
    }
    [parts addObject:T(language, isNAS ? @"nas" : @"externalVolume")];

    if (isNAS) {
        NSURLComponents *components = [NSURLComponents
            componentsWithString:config[@"GDRIVE_BACKUP_NAS_URL"] ?: @""];
        // Reading only the parsed host keeps SMB user names and passwords out of
        // the status UI even when the saved URL contains legacy credentials.
        NSString *host = GDTSafeDestinationLabelComponent(components.host);
        if (host.length) {
            [parts addObject:host];
        }

        NSString *share = GDTSafeDestinationLabelComponent(components.URL.path);
        while ([share hasPrefix:@"/"]) {
            share = [share substringFromIndex:1];
        }
        if (!share.length) {
            share = GDTSafeDestinationLabelComponent(config[@"GDRIVE_BACKUP_NAS_MOUNT"].lastPathComponent);
        }
        NSString *subdirectory = GDTSafeDestinationLabelComponent(
            config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup");
        NSString *folder = share;
        if (subdirectory.length) {
            folder = folder.length ? [folder stringByAppendingPathComponent:subdirectory] : subdirectory;
        }
        if (folder.length) {
            [parts addObject:folder];
        }
    } else {
        NSString *destination = GDTBackupDestinationForConfig(config);
        NSString *volumeRoot = GDTBackupCapacityPathForConfig(config);
        NSString *volumeName = GDTSafeDestinationLabelComponent(volumeRoot.lastPathComponent);
        if (!volumeName.length) {
            volumeName = GDTSafeDestinationLabelComponent(destination.lastPathComponent);
        }
        if (volumeName.length) {
            [parts addObject:volumeName];
        }

        NSString *rootPrefix = volumeRoot.length ? [volumeRoot stringByAppendingString:@"/"] : @"";
        if (rootPrefix.length && [destination hasPrefix:rootPrefix]) {
            NSString *subpath = GDTSafeDestinationLabelComponent(
                [destination substringFromIndex:rootPrefix.length]);
            if (subpath.length) {
                [parts addObject:subpath];
            }
        }
    }

    return parts.count ? [parts componentsJoinedByString:@" · "] : T(language, @"overviewUnavailable");
}

static NSString *GDTLocalizedProgressPhase(NSString *phase, NSString *language) {
    NSArray<NSString *> *parts = [phase componentsSeparatedByString:@"/"];
    if (parts.count != 2 || ![parts[0] length] || ![parts[1] length]) {
        return @"";
    }
    return [NSString stringWithFormat:T(language, @"progressAreaFormat"),
        parts[0], parts[1]];
}

static NSString *GDTLocalizedProgressCount(NSString *rawCount, NSString *language) {
    if (![rawCount isKindOfClass:NSString.class] || !rawCount.length || rawCount.length > 18 ||
        [rawCount rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location
            != NSNotFound) {
        return nil;
    }
    NSDictionary<NSString *, NSString *> *localeIdentifiers = @{
        @"de": @"de_DE", @"en": @"en_US", @"fr": @"fr_FR", @"es": @"es_ES",
        @"ja": @"ja_JP", @"yue": @"zh_HK", @"ko": @"ko_KR"
    };
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    formatter.locale = [NSLocale localeWithLocaleIdentifier:
        localeIdentifiers[language ?: @"en"] ?: @"en_US"];
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:rawCount];
    return [formatter stringFromNumber:number];
}

static BOOL GDTProgressMetricMatches(NSString *value, NSString *pattern,
                                     NSUInteger maximumLength) {
    if (![value isKindOfClass:NSString.class] || !value.length ||
        value.length > maximumLength) {
        return NO;
    }
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:pattern options:0 error:nil];
    return [expression firstMatchInString:value options:0
        range:NSMakeRange(0, value.length)] != nil;
}

static BOOL GDTProgressTransferPairIsSafe(NSString *transferred, NSString *speed) {
    return GDTProgressMetricMatches(transferred,
        @"^[0-9]+([.][0-9]+)? ([KMGTPE]i)?B$", 32) &&
        GDTProgressMetricMatches(speed,
        @"^[0-9]+([.][0-9]+)? ([KMGTPE]i)?B/s$", 34);
}

static BOOL GDTProgressTransferIsPositive(NSString *transferred) {
    NSRange separator = [transferred rangeOfString:@" "];
    if (separator.location == NSNotFound) return NO;
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:
        [transferred substringToIndex:separator.location]];
    return ![number isEqualToNumber:NSDecimalNumber.notANumber] &&
        [number compare:NSDecimalNumber.zero] == NSOrderedDescending;
}

static NSString *GDTLocalizedProgressDetail(
    NSDictionary<NSString *, NSString *> *progress, NSString *language) {
    NSString *detail = progress[@"detail"];
    if (detail.length) return detail;

    NSString *transferred = progress[@"transferred"];
    NSString *speed = progress[@"speed"];
    if (GDTProgressTransferPairIsSafe(transferred, speed) &&
        GDTProgressTransferIsPositive(transferred)) {
        return [NSString stringWithFormat:T(language, @"progressTransferredFormat"),
            transferred, speed];
    }

    NSString *checked = GDTLocalizedProgressCount(progress[@"checked"], language);
    NSString *listed = GDTLocalizedProgressCount(progress[@"listed"], language);
    if (checked.length && listed.length) {
        return [NSString stringWithFormat:T(language, @"progressCheckedListedFormat"),
            checked, listed];
    }
    return progress[@"phase"].length
        ? T(language, @"progressChecking") : T(language, @"progressPreparing");
}

static NSTimeInterval GDTBackupNotificationTimestamp(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    long long timestamp = 0;
    if (![scanner scanLongLong:&timestamp] || !scanner.isAtEnd || timestamp <= 0) {
        return 0;
    }
    return (NSTimeInterval)timestamp;
}

static NSTimeInterval GDTCanonicalBackupNotificationTimestamp(id value) {
    NSTimeInterval timestamp = GDTBackupNotificationTimestamp(value);
    if (timestamp <= 0 || ![value isKindOfClass:NSString.class]) return 0;
    NSString *canonical = [NSString stringWithFormat:@"%.0f", timestamp];
    return [(NSString *)value isEqualToString:canonical] ? timestamp : 0;
}

static NSTimeInterval GDTBackupSuccessIdentifierTimestamp(
    NSString *profileID, NSString *identifier) {
    NSArray<NSString *> *safeIdentifiers = [GDTBackupNotificationPolicy
        successNotificationIdentifiersForProfileID:profileID
                              candidateIdentifiers:identifier.length ? @[identifier] : @[]];
    if (safeIdentifiers.count != 1) return 0;
    return GDTCanonicalBackupNotificationTimestamp(
        [identifier componentsSeparatedByString:@"."].lastObject);
}

static BOOL GDTBackupSuccessRequestMatches(
    NSString *profileID, NSString *identifier, NSString *categoryIdentifier,
    NSDictionary *userInfo, NSTimeInterval *timestamp) {
    NSTimeInterval identifierTimestamp =
        GDTBackupSuccessIdentifierTimestamp(profileID, identifier);
    NSString *metadataProfileID = [userInfo[@"profileID"] isKindOfClass:NSString.class]
        ? userInfo[@"profileID"] : @"";
    NSTimeInterval metadataTimestamp =
        GDTCanonicalBackupNotificationTimestamp(userInfo[@"eventTimestamp"]);
    if (identifierTimestamp <= 0 ||
        ![categoryIdentifier isEqualToString:@"GDT_BACKUP_SUCCESS"] ||
        ![metadataProfileID isEqualToString:profileID] ||
        metadataTimestamp != identifierTimestamp) {
        return NO;
    }
    if (timestamp) *timestamp = identifierTimestamp;
    return YES;
}

static BOOL GDTBackupSuccessAcceptedState(
    NSUserDefaults *defaults, NSString *profileID, NSString *stateKey,
    NSString *timestampKey, NSString *identifierKey, NSTimeInterval *timestamp,
    NSString * __autoreleasing *identifier) {
    NSDictionary *state = [defaults dictionaryForKey:stateKey];
    NSNumber *stateTimestamp = [state[@"timestamp"] isKindOfClass:NSNumber.class]
        ? state[@"timestamp"] : nil;
    NSString *stateIdentifier = [state[@"identifier"] isKindOfClass:NSString.class]
        ? state[@"identifier"] : nil;
    NSTimeInterval identifierTimestamp =
        GDTBackupSuccessIdentifierTimestamp(profileID, stateIdentifier);
    if (stateTimestamp && identifierTimestamp > 0 &&
        stateTimestamp.doubleValue == identifierTimestamp) {
        if (timestamp) *timestamp = identifierTimestamp;
        if (identifier) *identifier = stateIdentifier;
        return YES;
    }

    NSString *legacyIdentifier = [defaults stringForKey:identifierKey];
    NSTimeInterval legacyTimestamp = [defaults doubleForKey:timestampKey];
    identifierTimestamp =
        GDTBackupSuccessIdentifierTimestamp(profileID, legacyIdentifier);
    if (legacyTimestamp > 0 && identifierTimestamp > 0 &&
        legacyTimestamp == identifierTimestamp) {
        if (timestamp) *timestamp = identifierTimestamp;
        if (identifier) *identifier = legacyIdentifier;
    } else {
        if (timestamp) *timestamp = 0;
        if (identifier) *identifier = nil;
    }
    return NO;
}

static void GDTPersistBackupSuccessAcceptedState(
    NSUserDefaults *defaults, NSString *stateKey, NSString *timestampKey,
    NSString *identifierKey, NSTimeInterval timestamp, NSString *identifier) {
    [defaults setObject:@{
        @"timestamp": @(timestamp),
        @"identifier": identifier
    } forKey:stateKey];
    [defaults setDouble:timestamp forKey:timestampKey];
    [defaults setObject:identifier forKey:identifierKey];
}

static NSUInteger GDTBackupNotificationDecisionStage(
    NSDictionary<NSString *, NSString *> *decision) {
    if (decision[@"supersedesIdentifier"].length) return 3;
    if ([decision[@"kind"] isEqualToString:@"retry-running"]) return 2;
    return 1;
}

static BOOL GDTBackupNotificationDecisionCanReplaceQueued(
    NSDictionary<NSString *, NSString *> *candidate,
    NSDictionary<NSString *, NSString *> *queued) {
    NSTimeInterval candidateOrigin =
        GDTBackupNotificationTimestamp(candidate[@"issueOriginTimestamp"]);
    NSTimeInterval queuedOrigin =
        GDTBackupNotificationTimestamp(queued[@"issueOriginTimestamp"]);
    if (candidateOrigin != queuedOrigin) return candidateOrigin > queuedOrigin;

    // A delayed refresh may observe retry-running after the terminal result.
    // Preserve the furthest known lifecycle stage for one canonical origin.
    return GDTBackupNotificationDecisionStage(candidate) >=
        GDTBackupNotificationDecisionStage(queued);
}

static BOOL GDTBackupNotificationAcceptedState(
    NSUserDefaults *defaults, NSString *stateKey, NSString *originKey,
    NSTimeInterval *acceptedOrigin, NSUInteger *acceptedStage) {
    NSDictionary *state = [defaults dictionaryForKey:stateKey];
    NSNumber *originValue = [state[@"origin"] isKindOfClass:NSNumber.class]
        ? state[@"origin"] : nil;
    NSNumber *stageValue = [state[@"stage"] isKindOfClass:NSNumber.class]
        ? state[@"stage"] : nil;
    NSTimeInterval origin = originValue.doubleValue;
    NSUInteger stage = stageValue.unsignedIntegerValue;
    BOOL hasAuthoritativeState = origin > 0 && stage >= 1 && stage <= 3;
    if (!hasAuthoritativeState) {
        NSTimeInterval legacyOrigin = [defaults doubleForKey:originKey];
        origin = MAX(origin > 0 ? origin : 0, legacyOrigin);
        // Without an atomic pair, a stage can belong to an older origin.
        // Its identifier and revision must establish the stage instead.
        stage = 0;
    }
    *acceptedOrigin = origin;
    *acceptedStage = stage;
    return hasAuthoritativeState;
}

static void GDTPersistBackupNotificationAcceptedState(
    NSUserDefaults *defaults, NSString *stateKey, NSString *originKey,
    NSString *stageKey, NSTimeInterval origin, NSUInteger stage) {
    [defaults setObject:@{
        @"origin": @(origin),
        @"stage": @(stage)
    } forKey:stateKey];
    [defaults setDouble:origin forKey:originKey];
    [defaults setInteger:(NSInteger)stage forKey:stageKey];
}

static NSUInteger GDTBackupNotificationLegacyAcceptedStage(
    NSUserDefaults *defaults, NSString *profileID, NSString *identifierKey,
    NSString *revisionKey, NSTimeInterval acceptedOrigin) {
    NSString *identifier = [defaults stringForKey:identifierKey];
    NSArray<NSString *> *safeIdentifiers = [GDTBackupNotificationPolicy
        failureNotificationIdentifiersForProfileID:profileID
                              candidateIdentifiers:identifier.length
                                  ? @[identifier] : @[]];
    if (safeIdentifiers.count != 1 || acceptedOrigin <= 0) return 3;

    NSString *failureSuffix = [NSString stringWithFormat:
        @".failure.%.0f", acceptedOrigin];
    if ([identifier hasSuffix:failureSuffix]) {
        NSString *revision = [defaults stringForKey:revisionKey];
        if (!revision.length) return 1;
        NSString *runningPrefix = @"retry-running.";
        NSTimeInterval runningTimestamp = [revision hasPrefix:runningPrefix]
            ? GDTBackupNotificationTimestamp(
                [revision substringFromIndex:runningPrefix.length]) : 0;
        NSString *canonicalRevision = [NSString stringWithFormat:
            @"retry-running.%.0f", runningTimestamp];
        if (runningTimestamp > acceptedOrigin &&
            [revision isEqualToString:canonicalRevision]) {
            return 2;
        }
        return 3;
    }

    NSString *missedSuffix = [NSString stringWithFormat:
        @".missed.%.0f", acceptedOrigin];
    if ([identifier hasSuffix:missedSuffix] &&
        ![defaults stringForKey:revisionKey].length) {
        return 1;
    }
    return 3;
}

static void GDTAdvanceBackupNotificationAcceptedState(
    NSUserDefaults *defaults, NSString *stateKey, NSString *originKey,
    NSString *stageKey, NSTimeInterval candidateOrigin,
    NSUInteger candidateStage) {
    NSTimeInterval acceptedOrigin = 0;
    NSUInteger acceptedStage = 0;
    GDTBackupNotificationAcceptedState(
        defaults, stateKey, originKey, &acceptedOrigin, &acceptedStage);
    BOOL advances = candidateOrigin > acceptedOrigin ||
        (candidateOrigin == acceptedOrigin && candidateStage > acceptedStage);
    BOOL matches = candidateOrigin == acceptedOrigin &&
        candidateStage == acceptedStage;
    if (!advances && !matches) return;

    NSTimeInterval nextOrigin = advances ? candidateOrigin : acceptedOrigin;
    NSUInteger nextStage = advances ? candidateStage : acceptedStage;
    GDTPersistBackupNotificationAcceptedState(
        defaults, stateKey, originKey, stageKey, nextOrigin, nextStage);
}

@implementation AppDelegate

- (NSUserDefaults *)backupNotificationDefaultsStore {
    return NSUserDefaults.standardUserDefaults;
}

- (NSString *)backupNotificationDefaultsKeyForProfileID:(NSString *)profileID suffix:(NSString *)suffix {
    NSString *safeProfileID = profileID.length ? profileID : @"legacy";
    return [NSString stringWithFormat:@"GDTBackupNotification.%@.%@", safeProfileID, suffix];
}

- (NSDictionary<NSString *, NSString *> *)notificationMonitoringConfigForConfig:
    (NSDictionary<NSString *, NSString *> *)config now:(NSDate *)now {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    NSString *profileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSMutableDictionary<NSString *, NSString *> *monitoredConfig = [config mutableCopy];
    NSString *failureMonitorKey =
        [self backupNotificationDefaultsKeyForProfileID:profileID suffix:@"monitorStartedAt"];
    BOOL failureNotificationsEnabled =
        ![config[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"];
    if (!automaticSchedule || !failureNotificationsEnabled) {
        // Re-enabling later starts a fresh monitoring window instead of
        // reporting deadlines that occurred while alerts were intentionally off.
        [defaults removeObjectForKey:failureMonitorKey];
    } else {
        NSTimeInterval startedAt = [defaults doubleForKey:failureMonitorKey];
        if (startedAt <= 0) {
            startedAt = now.timeIntervalSince1970;
            [defaults setDouble:startedAt forKey:failureMonitorKey];
        }
        monitoredConfig[@"GDRIVE_BACKUP_NOTIFICATION_MONITOR_STARTED_AT"] =
            [NSString stringWithFormat:@"%.0f", startedAt];
    }

    NSString *successMonitorKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                            suffix:@"successMonitorStartedAt"];
    BOOL routineSuccessNotificationsEnabled =
        [config[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"1"];
    if (!automaticSchedule || !routineSuccessNotificationsEnabled) {
        [defaults removeObjectForKey:successMonitorKey];
    } else {
        NSTimeInterval startedAt = ceil([defaults doubleForKey:successMonitorKey]);
        if (startedAt <= 0) {
            // Event timestamps are integral seconds. Rounding activation up
            // makes a sub-second opt-in fail closed for a run already ending.
            startedAt = ceil(now.timeIntervalSince1970);
        }
        [defaults setDouble:startedAt forKey:successMonitorKey];
        monitoredConfig[@"GDRIVE_BACKUP_SUCCESS_NOTIFICATION_MONITOR_STARTED_AT"] =
            [NSString stringWithFormat:@"%.0f", startedAt];
    }
    return monitoredConfig;
}

- (NSSet<UNNotificationCategory *> *)appNotificationCategories {
    UNNotificationAction *openAction = [UNNotificationAction
        actionWithIdentifier:@"GDT_OPEN_BACKUP_OVERVIEW"
                       title:T(self.language ?: @"en", @"overviewOpen")
                     options:UNNotificationActionOptionForeground];
    UNNotificationCategory *backupCategory = [UNNotificationCategory
        categoryWithIdentifier:@"GDT_BACKUP_ALERT"
                       actions:@[openAction]
             intentIdentifiers:@[]
                       options:UNNotificationCategoryOptionCustomDismissAction];
    UNNotificationCategory *successCategory = [UNNotificationCategory
        categoryWithIdentifier:@"GDT_BACKUP_SUCCESS"
                       actions:@[openAction]
             intentIdentifiers:@[]
                       options:UNNotificationCategoryOptionNone];

    UNNotificationAction *setupExternalVolume = [UNNotificationAction
        actionWithIdentifier:@"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP"
                       title:T(self.language ?: @"en",
                               @"unknownExternalVolumeSetupAction")
                     options:UNNotificationActionOptionForeground];
    UNNotificationAction *ignoreExternalVolume = [UNNotificationAction
        actionWithIdentifier:@"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE"
                       title:T(self.language ?: @"en",
                               @"unknownExternalVolumeIgnoreAction")
                     options:UNNotificationActionOptionNone];
    UNNotificationCategory *unknownExternalVolumeCategory =
        [UNNotificationCategory
            categoryWithIdentifier:@"GDT_UNKNOWN_EXTERNAL_VOLUME"
                            actions:@[setupExternalVolume, ignoreExternalVolume]
                  intentIdentifiers:@[]
                            options:UNNotificationCategoryOptionNone];
    UNNotificationAction *openUpdate = [UNNotificationAction
        actionWithIdentifier:@"GDT_UPDATE_OPEN" title:T(self.language ?: @"en", @"updateOpenRelease")
        options:UNNotificationActionOptionNone];
    UNNotificationAction *laterUpdate = [UNNotificationAction
        actionWithIdentifier:@"GDT_UPDATE_LATER" title:T(self.language ?: @"en", @"updateLater")
        options:UNNotificationActionOptionNone];
    UNNotificationCategory *updateCategory = [UNNotificationCategory
        categoryWithIdentifier:@"GDT_UPDATE_AVAILABLE" actions:@[openUpdate, laterUpdate]
        intentIdentifiers:@[] options:UNNotificationCategoryOptionCustomDismissAction];
    return [NSSet setWithObjects:backupCategory, successCategory,
            unknownExternalVolumeCategory, updateCategory, nil];
}

- (void)configureBackupNotificationsForConfig:(NSDictionary<NSString *, NSString *> *)config {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    center.delegate = self;
    [center setNotificationCategories:[self appNotificationCategories]];
    if (!automaticSchedule) {
        return;
    }

    // Startup configures categories and monitoring only. A permission sheet is
    // reserved for an explicit setup save, never for controller launch.
    (void)[self notificationMonitoringConfigForConfig:config now:[NSDate date]];
}

- (void)requestBackupNotificationAuthorizationIfNeededForConfig:
    (NSDictionary<NSString *, NSString *> *)config {
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    BOOL failureNotificationsEnabled =
        ![config[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"];
    BOOL routineSuccessNotificationsEnabled =
        [config[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"1"];
    if (!automaticSchedule ||
        (!failureNotificationsEnabled && !routineSuccessNotificationsEnabled)) {
        return;
    }

    [self requestNotificationAuthorizationAfterExplicitSetupSave];
}

- (void)requestNotificationAuthorizationAfterExplicitSetupSave {
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;
        [center requestAuthorizationWithOptions:
            UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                              completionHandler:^(BOOL granted, NSError *error) {
            (void)granted;
            (void)error;
        }];
    }];
}

- (void)requestUnknownExternalVolumeNotificationAuthorizationIfNeeded {
    [self requestNotificationAuthorizationAfterExplicitSetupSave];
}

- (NSString *)unknownExternalVolumeBootSessionID {
    if (self.unknownExternalVolumeBootSessionIDCache.length) {
        return self.unknownExternalVolumeBootSessionIDCache;
    }
    int status = 0;
    NSString *bootSessionID = [RunCommand(
        @"/usr/sbin/sysctl", @[@"-n", @"kern.bootsessionuuid"], nil, &status)
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (status == 0 && bootSessionID.length) {
        self.unknownExternalVolumeBootSessionIDCache =
            bootSessionID.uppercaseString;
    }
    return self.unknownExternalVolumeBootSessionIDCache ?: @"";
}

- (NSString *)unknownExternalVolumeAttachmentDefaultsKey {
    return @"GDTUnknownExternalVolume.AttachmentMarkers";
}

- (NSSet<NSString *> *)rememberedUnknownExternalVolumeUUIDsForDiskID:
    (NSString *)diskID {
    if (!diskID.length) return [NSSet set];
    NSDictionary *markers = [[self backupNotificationDefaultsStore]
        dictionaryForKey:[self unknownExternalVolumeAttachmentDefaultsKey]];
    NSDictionary *marker = [markers[diskID] isKindOfClass:NSDictionary.class]
        ? markers[diskID] : nil;
    NSString *savedBootSessionID =
        [marker[@"bootSessionID"] isKindOfClass:NSString.class]
            ? marker[@"bootSessionID"] : @"";
    NSString *currentBootSessionID =
        [self unknownExternalVolumeBootSessionID];
    if (!currentBootSessionID.length ||
        ![savedBootSessionID isEqualToString:currentBootSessionID]) {
        return [NSSet set];
    }

    NSMutableSet<NSString *> *volumeUUIDs = [NSMutableSet set];
    NSArray *savedVolumeUUIDs =
        [marker[@"volumeUUIDs"] isKindOfClass:NSArray.class]
            ? marker[@"volumeUUIDs"] : @[];
    for (id value in savedVolumeUUIDs) {
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [volumeUUIDs addObject:[value uppercaseString]];
        }
    }
    return volumeUUIDs;
}

- (void)rememberUnknownExternalAttachmentForDiskID:(NSString *)diskID
                                        volumeUUIDs:
    (NSArray<NSString *> *)volumeUUIDs {
    NSString *bootSessionID = [self unknownExternalVolumeBootSessionID];
    if (!diskID.length || !bootSessionID.length) return;
    NSMutableSet<NSString *> *normalized = [NSMutableSet set];
    for (id value in volumeUUIDs ?: @[]) {
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [normalized addObject:[value uppercaseString]];
        }
    }
    if (!normalized.count) return;

    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSMutableDictionary *markers =
        [[defaults dictionaryForKey:
            [self unknownExternalVolumeAttachmentDefaultsKey]] mutableCopy] ?:
            [NSMutableDictionary dictionary];
    markers[diskID] = @{
        @"bootSessionID": bootSessionID,
        @"volumeUUIDs": [normalized.allObjects
            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]
    };
    [defaults setObject:markers
                 forKey:[self unknownExternalVolumeAttachmentDefaultsKey]];
}

- (void)forgetUnknownExternalAttachmentForDiskID:(NSString *)diskID {
    if (!diskID.length) return;
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSMutableDictionary *markers =
        [[defaults dictionaryForKey:
            [self unknownExternalVolumeAttachmentDefaultsKey]] mutableCopy];
    if (!markers[diskID]) return;
    [markers removeObjectForKey:diskID];
    if (markers.count) {
        [defaults setObject:markers
                     forKey:[self unknownExternalVolumeAttachmentDefaultsKey]];
    } else {
        [defaults removeObjectForKey:
            [self unknownExternalVolumeAttachmentDefaultsKey]];
    }
}

- (void)forgetUnknownExternalAttachmentsExceptDiskIDs:
    (NSSet<NSString *> *)mountedDiskIDs {
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSDictionary *savedMarkers =
        [defaults dictionaryForKey:
            [self unknownExternalVolumeAttachmentDefaultsKey]];
    for (NSString *diskID in savedMarkers.allKeys ?: @[]) {
        if (![mountedDiskIDs containsObject:diskID]) {
            [self forgetUnknownExternalAttachmentForDiskID:diskID];
        }
    }
}

- (BOOL)timeSensitiveBackupNotificationsEnabled {
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return NO;

    CFErrorRef error = NULL;
    CFTypeRef value = SecTaskCopyValueForEntitlement(
        task,
        CFSTR("com.apple.developer.usernotifications.time-sensitive"),
        &error);
    BOOL enabled = value &&
        CFGetTypeID(value) == CFBooleanGetTypeID() &&
        CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    if (error) CFRelease(error);
    CFRelease(task);
    return enabled;
}

- (UNMutableNotificationContent *)backupNotificationContentForDecision:
    (NSDictionary<NSString *, NSString *> *)decision {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = T(self.language ?: @"en", decision[@"titleKey"]);
    content.body = T(self.language ?: @"en", decision[@"bodyKey"]);
    if ([decision[@"kind"] isEqualToString:@"success"]) {
        content.sound = nil;
        content.categoryIdentifier = @"GDT_BACKUP_SUCCESS";
        content.userInfo = @{
            @"profileID": decision[@"profileID"] ?: @"",
            @"eventTimestamp": decision[@"eventTimestamp"] ?: @""
        };
        if (@available(macOS 12.0, *)) {
            content.interruptionLevel = UNNotificationInterruptionLevelActive;
        }
        return content;
    }
    content.sound = UNNotificationSound.defaultSound;
    content.categoryIdentifier = @"GDT_BACKUP_ALERT";
    content.userInfo = @{
        @"profileID": decision[@"profileID"] ?: @"",
        @"issueOriginTimestamp": decision[@"issueOriginTimestamp"] ?: @""
    };
    if (@available(macOS 12.0, *)) {
        // A protected level without its signed entitlement can make delivery
        // fail. Ad-hoc builds keep the durable alert at the normal active level.
        content.interruptionLevel = [self timeSensitiveBackupNotificationsEnabled]
            ? UNNotificationInterruptionLevelTimeSensitive
            : UNNotificationInterruptionLevelActive;
    }
    return content;
}

- (UNMutableNotificationContent *)unknownExternalVolumeNotificationContentForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    NSString *name = GDTSafeDestinationLabelComponent(descriptor[@"name"]);
    if (!name.length) {
        name = T(self.language ?: @"en", @"externalVolume");
    }
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = T(self.language ?: @"en", @"unknownExternalVolumeTitle");
    content.body = [NSString stringWithFormat:
        T(self.language ?: @"en", @"unknownExternalVolumeBody"), name];
    content.categoryIdentifier = @"GDT_UNKNOWN_EXTERNAL_VOLUME";
    content.sound = nil;
    if (@available(macOS 12.0, *)) {
        content.interruptionLevel = UNNotificationInterruptionLevelPassive;
    }
    NSString *diskID = [descriptor[@"diskID"] isKindOfClass:NSString.class]
        ? descriptor[@"diskID"] : @"";
    NSString *volumeUUID = [descriptor[@"volumeUUID"] isKindOfClass:NSString.class]
        ? descriptor[@"volumeUUID"] : @"";
    NSMutableOrderedSet<NSString *> *attachmentVolumeUUIDs =
        [NSMutableOrderedSet orderedSet];
    NSArray *savedAttachmentVolumeUUIDs =
        [descriptor[@"attachmentVolumeUUIDs"] isKindOfClass:NSArray.class]
            ? descriptor[@"attachmentVolumeUUIDs"] : @[];
    for (id value in savedAttachmentVolumeUUIDs) {
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [attachmentVolumeUUIDs addObject:[value uppercaseString]];
        }
    }
    [attachmentVolumeUUIDs unionSet:
        [self rememberedUnknownExternalVolumeUUIDsForDiskID:diskID]];
    if (volumeUUID.length) {
        [attachmentVolumeUUIDs removeObject:volumeUUID.uppercaseString];
        [attachmentVolumeUUIDs insertObject:volumeUUID.uppercaseString
                                    atIndex:0];
    }
    content.userInfo = @{
        @"diskID": diskID,
        @"volumeUUID": volumeUUID,
        @"attachmentVolumeUUIDs": attachmentVolumeUUIDs.array
    };
    return content;
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    [self deliverUnknownExternalVolumeNotificationForDescriptor:descriptor
                                                     completion:^(BOOL delivered) {
        (void)delivered;
    }];
}

- (void)deliverUnknownExternalVolumeNotificationForDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                                   completion:
    (void (^)(BOOL delivered))completion {
    NSString *diskID = [descriptor[@"diskID"] isKindOfClass:NSString.class]
        ? descriptor[@"diskID"] : @"";
    NSString *volumeUUID = [descriptor[@"volumeUUID"] isKindOfClass:NSString.class]
        ? descriptor[@"volumeUUID"] : @"";
    if (!diskID.length || !volumeUUID.length) {
        completion(NO);
        return;
    }

    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized &&
            settings.authorizationStatus != UNAuthorizationStatusProvisional) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
            return;
        }
        UNMutableNotificationContent *content =
            [self unknownExternalVolumeNotificationContentForDescriptor:descriptor];
        NSString *identifier =
            [self unknownExternalVolumeNotificationIdentifierForDiskID:diskID
                                                             volumeUUID:volumeUUID];
        UNNotificationRequest *request = [UNNotificationRequest
            requestWithIdentifier:identifier content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error == nil);
            });
        }];
    }];
}

- (NSString *)unknownExternalVolumeNotificationIdentifierForDiskID:
    (NSString *)diskID volumeUUID:(NSString *)volumeUUID {
    return [NSString stringWithFormat:
        @"com.commcats.gdrivebackup.unknown-external.%@.%@",
        diskID, volumeUUID.uppercaseString];
}

- (void)removeUnknownExternalVolumeNotificationForDiskID:(NSString *)diskID
                                               volumeUUID:(NSString *)volumeUUID {
    if (!diskID.length || !volumeUUID.length) return;
    NSString *identifier =
        [self unknownExternalVolumeNotificationIdentifierForDiskID:diskID
                                                         volumeUUID:volumeUUID];
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
    [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
}

- (void)removeUnknownExternalVolumeNotificationForDiskID:(NSString *)diskID {
    if (!diskID.length) return;
    NSMutableSet<NSString *> *volumeUUIDs = [NSMutableSet set];
    NSString *notifiedUUID =
        self.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID];
    NSString *pendingUUID =
        self.pendingUnknownExternalVolumeUUIDsByDiskID[diskID];
    if (notifiedUUID.length) [volumeUUIDs addObject:notifiedUUID];
    if (pendingUUID.length) [volumeUUIDs addObject:pendingUUID];
    for (NSString *volumeUUID in volumeUUIDs) {
        [self removeUnknownExternalVolumeNotificationForDiskID:diskID
                                                     volumeUUID:volumeUUID];
    }
}

- (void)addBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                              toCenter:(UNUserNotificationCenter *)center
                            completion:(void (^)(BOOL delivered))completion {
    UNMutableNotificationContent *content =
        [self backupNotificationContentForDecision:decision];
    UNNotificationRequest *request = [UNNotificationRequest
        requestWithIdentifier:decision[@"identifier"] content:content trigger:nil];
    [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        completion(error == nil);
    }];
}

- (void)deliverBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision
                                completion:(void (^)(BOOL delivered))completion {
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional) {
            [self addBackupNotificationDecision:decision toCenter:center completion:completion];
            return;
        }
        // Delivery never creates a consent sheet. Setup is the sole explicit
        // interaction that may ask for notification permission.
        completion(NO);
    }];
}

- (void)addCurrentBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
                              capturedActiveIssueTimestamp:
    (NSTimeInterval)capturedActiveIssueTimestamp
                                           toCenter:(UNUserNotificationCenter *)center
                                         completion:(void (^)(BOOL delivered))completion {
    void (^addIfCurrent)(void) = ^{
        if (capturedActiveIssueTimestamp >= 0 &&
            ![self isBackupSuccessDecisionCurrent:decision
                           capturedActiveIssueTimestamp:capturedActiveIssueTimestamp]) {
            completion(NO);
            return;
        }
        [self addBackupNotificationDecision:decision toCenter:center completion:completion];
    };
    if (NSThread.isMainThread) {
        addIfCurrent();
    } else {
        dispatch_async(dispatch_get_main_queue(), addIfCurrent);
    }
}

- (UNUserNotificationCenter *)backupNotificationCenter {
    // Both delivery paths share this boundary so tests can verify that
    // background work stays passive while Setup owns notification consent.
    return UNUserNotificationCenter.currentNotificationCenter;
}

- (void)deliverBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
                             capturedActiveIssueTimestamp:
    (NSTimeInterval)capturedActiveIssueTimestamp
                                          completion:(void (^)(BOOL delivered))completion {
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional) {
            [self addCurrentBackupSuccessNotificationDecision:decision
                                      capturedActiveIssueTimestamp:capturedActiveIssueTimestamp
                                                     toCenter:center completion:completion];
            return;
        }
        completion(NO);
    }];
}

- (void)processBackupNotificationDecision:(NSDictionary<NSString *, NSString *> *)decision {
    NSDictionary<NSString *, NSString *> *deliveryDecision = [decision copy];
    NSString *identifier = deliveryDecision[@"identifier"];
    NSString *profileID = deliveryDecision[@"profileID"];
    NSTimeInterval issueOriginTimestamp =
        GDTBackupNotificationTimestamp(deliveryDecision[@"issueOriginTimestamp"]);
    if (!identifier.length || !profileID.length ||
        !deliveryDecision[@"titleKey"].length ||
        !deliveryDecision[@"bodyKey"].length || issueOriginTimestamp <= 0 ||
        [GDTBackupNotificationPolicy
            failureNotificationIdentifiersForProfileID:profileID
                                  candidateIdentifiers:@[identifier]].count != 1) {
        return;
    }
    NSString *identifierKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                        suffix:@"lastDeliveredIdentifier"];
    NSString *revisionKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                      suffix:@"lastDeliveredRevision"];
    NSString *deliveredKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"deliveredFailureIdentifiers"];
    NSString *dismissedKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"dismissedIssueAt"];
    NSString *acceptedOriginKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"latestDeliveredIssueAt"];
    NSString *acceptedStageKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"latestDeliveredIssueStage"];
    NSString *acceptedStateKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"latestDeliveredIssueState"];
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    if (issueOriginTimestamp <= [defaults doubleForKey:dismissedKey]) {
        return;
    }
    NSUInteger decisionStage =
        GDTBackupNotificationDecisionStage(deliveryDecision);
    NSTimeInterval acceptedOriginTimestamp = 0;
    NSUInteger acceptedStage = 0;
    BOOL hasAuthoritativeAcceptedState = GDTBackupNotificationAcceptedState(
        defaults, acceptedStateKey, acceptedOriginKey,
        &acceptedOriginTimestamp, &acceptedStage);
    if (!hasAuthoritativeAcceptedState && acceptedOriginTimestamp > 0) {
        // Legacy fields distinguish an in-place preliminary/running update
        // from a terminal replacement. Ambiguous partial state stays terminal.
        NSUInteger legacyStage = GDTBackupNotificationLegacyAcceptedStage(
            defaults, profileID, identifierKey, revisionKey,
            acceptedOriginTimestamp);
        acceptedStage = legacyStage;
        GDTPersistBackupNotificationAcceptedState(
            defaults, acceptedStateKey, acceptedOriginKey, acceptedStageKey,
            acceptedOriginTimestamp, acceptedStage);
    }
    if (acceptedOriginTimestamp > 0 &&
        (issueOriginTimestamp < acceptedOriginTimestamp ||
         (issueOriginTimestamp == acceptedOriginTimestamp &&
          decisionStage < acceptedStage))) {
        return;
    }

    NSString *revision = [deliveryDecision[@"revision"] isKindOfClass:NSString.class]
        ? deliveryDecision[@"revision"] : @"";
    BOOL sameIdentifier =
        [[defaults stringForKey:identifierKey] isEqualToString:identifier];
    BOOL alreadyDelivered = revision.length
        ? sameIdentifier &&
            [[defaults stringForKey:revisionKey] isEqualToString:revision]
        : sameIdentifier;
    if (alreadyDelivered) {
        // Replay repairs a lifecycle watermark if acceptance was interrupted
        // after its identifier was saved but before the stage was advanced.
        GDTAdvanceBackupNotificationAcceptedState(
            defaults, acceptedStateKey, acceptedOriginKey, acceptedStageKey,
            issueOriginTimestamp, decisionStage);
        [self retireSupersededBackupNotificationForDecision:deliveryDecision];
        return;
    }
    if (!self.pendingBackupNotificationIdentifiers) {
        self.pendingBackupNotificationIdentifiers = [NSMutableSet set];
    }
    NSString *pendingKey = [NSString stringWithFormat:@"%@\n%@", identifier, revision];
    if ([self.pendingBackupNotificationIdentifiers containsObject:pendingKey]) return;

    if (!self.pendingBackupNotificationKeysByProfileID) {
        self.pendingBackupNotificationKeysByProfileID = [NSMutableDictionary dictionary];
    }
    NSString *inFlightKey =
        self.pendingBackupNotificationKeysByProfileID[profileID];
    if (inFlightKey.length) {
        NSDictionary<NSString *, NSString *> *inFlightDecision =
            self.inFlightBackupNotificationDecisionsByProfileID[profileID];
        if (inFlightDecision &&
            !GDTBackupNotificationDecisionCanReplaceQueued(
                deliveryDecision, inFlightDecision)) {
            return;
        }
        if (!self.queuedBackupNotificationDecisionsByProfileID) {
            self.queuedBackupNotificationDecisionsByProfileID =
                [NSMutableDictionary dictionary];
        }
        NSDictionary<NSString *, NSString *> *previousQueued =
            self.queuedBackupNotificationDecisionsByProfileID[profileID];
        if (previousQueued &&
            !GDTBackupNotificationDecisionCanReplaceQueued(
                deliveryDecision, previousQueued)) {
            return;
        }
        if (previousQueued) {
            NSString *previousRevision =
                [previousQueued[@"revision"] isKindOfClass:NSString.class]
                    ? previousQueued[@"revision"] : @"";
            NSString *previousPendingKey = [NSString stringWithFormat:@"%@\n%@",
                previousQueued[@"identifier"] ?: @"", previousRevision];
            [self.pendingBackupNotificationIdentifiers
                removeObject:previousPendingKey];
        }
        // Notification Center may accept same-identifier updates out of order.
        // One in-flight request per profile makes visible content ordering match
        // the controller's durable revision ordering.
        self.queuedBackupNotificationDecisionsByProfileID[profileID] =
            deliveryDecision;
        [self.pendingBackupNotificationIdentifiers addObject:pendingKey];
        return;
    }

    [self.pendingBackupNotificationIdentifiers addObject:pendingKey];
    self.pendingBackupNotificationKeysByProfileID[profileID] = pendingKey;
    if (!self.inFlightBackupNotificationDecisionsByProfileID) {
        self.inFlightBackupNotificationDecisionsByProfileID =
            [NSMutableDictionary dictionary];
    }
    self.inFlightBackupNotificationDecisionsByProfileID[profileID] =
        deliveryDecision;
    NSUInteger deliveryGeneration =
        self.backupNotificationGenerationsByProfileID[profileID]
            .unsignedIntegerValue;

    __weak typeof(self) weakSelf = self;
    [self deliverBackupNotificationDecision:deliveryDecision
                                  completion:^(BOOL delivered) {
        void (^finish)(void) = ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.pendingBackupNotificationIdentifiers removeObject:pendingKey];
            if ([strongSelf.pendingBackupNotificationKeysByProfileID[profileID]
                    isEqualToString:pendingKey]) {
                [strongSelf.pendingBackupNotificationKeysByProfileID
                    removeObjectForKey:profileID];
                [strongSelf.inFlightBackupNotificationDecisionsByProfileID
                    removeObjectForKey:profileID];
            }
            if (delivered) {
                NSUserDefaults *store = [strongSelf backupNotificationDefaultsStore];
                NSUInteger currentGeneration =
                    strongSelf.backupNotificationGenerationsByProfileID[profileID]
                        .unsignedIntegerValue;
                if (currentGeneration != deliveryGeneration ||
                    issueOriginTimestamp <= [store doubleForKey:dismissedKey]) {
                    [strongSelf removeExactBackupNotificationIdentifiers:@[identifier]
                                                             forProfileID:profileID];
                } else {
                    // The monotonic watermark goes first so a replay cannot
                    // deduplicate an identifier whose accepted stage was lost.
                    GDTAdvanceBackupNotificationAcceptedState(
                        store, acceptedStateKey, acceptedOriginKey,
                        acceptedStageKey,
                        issueOriginTimestamp, decisionStage);
                    [store setObject:identifier forKey:identifierKey];
                    if (revision.length) {
                        [store setObject:revision forKey:revisionKey];
                    } else {
                        [store removeObjectForKey:revisionKey];
                    }
                    NSMutableArray<NSString *> *identifiers =
                        [[store stringArrayForKey:deliveredKey] mutableCopy] ?:
                            [NSMutableArray array];
                    if (![identifiers containsObject:identifier]) {
                        [identifiers addObject:identifier];
                        [store setObject:identifiers forKey:deliveredKey];
                    }
                    [strongSelf retireSupersededBackupNotificationForDecision:
                        deliveryDecision];
                    NSString *activeAtKey = [strongSelf
                        backupNotificationDefaultsKeyForProfileID:profileID
                                                           suffix:@"activeIssueAt"];
                    if ([store doubleForKey:activeAtKey] == issueOriginTimestamp) {
                        [store setObject:identifier forKey:[strongSelf
                            backupNotificationDefaultsKeyForProfileID:profileID
                                                               suffix:@"activeIssueIdentifier"]];
                    }
                }
            }

            NSDictionary<NSString *, NSString *> *queuedDecision =
                strongSelf.queuedBackupNotificationDecisionsByProfileID[profileID];
            if (queuedDecision) {
                [strongSelf.queuedBackupNotificationDecisionsByProfileID
                    removeObjectForKey:profileID];
                NSString *queuedRevision =
                    [queuedDecision[@"revision"] isKindOfClass:NSString.class]
                        ? queuedDecision[@"revision"] : @"";
                NSString *queuedKey = [NSString stringWithFormat:@"%@\n%@",
                    queuedDecision[@"identifier"] ?: @"", queuedRevision];
                [strongSelf.pendingBackupNotificationIdentifiers
                    removeObject:queuedKey];
                [strongSelf processBackupNotificationDecision:queuedDecision];
            }
        };
        if (NSThread.isMainThread) {
            finish();
        } else {
            dispatch_async(dispatch_get_main_queue(), finish);
        }
    }];
}

- (BOOL)isBackupSuccessDecisionSourceCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    NSDictionary<NSString *, NSString *> *baseConfig = GDTReadConfigDictionary();
    NSString *profileID = decision[@"profileID"] ?: @"";
    NSString *currentProfileID = baseConfig[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    if (!profileID.length || ![profileID isEqualToString:currentProfileID]) {
        return NO;
    }

    NSDate *now = [NSDate date];
    NSDictionary<NSString *, NSString *> *config =
        [self notificationMonitoringConfigForConfig:baseConfig now:now];
    NSString *summaryPath = GDTBackupSummaryPathForConfig(config);
    NSDictionary<NSString *, NSString *> *summary =
        GDTReadBackupSummaryAtPath(summaryPath);
    NSString *status = GDTBackupSummaryStatusForValues(summary);
    NSDictionary<NSString *, NSString *> *currentDecision =
        [GDTBackupNotificationPolicy successDecisionForConfig:config
                                                      summary:summary
                                                       status:status
                                         activeIssueTimestamp:capturedActiveIssueTimestamp
                                                          now:now];
    return currentDecision && [currentDecision isEqualToDictionary:decision];
}

- (BOOL)isBackupSuccessDecisionCurrent:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    NSString *profileID = decision[@"profileID"];
    NSString *identifier = decision[@"identifier"];
    NSTimeInterval eventTimestamp =
        GDTCanonicalBackupNotificationTimestamp(decision[@"eventTimestamp"]);
    if (!profileID.length || !identifier.length || eventTimestamp <= 0 ||
        GDTBackupSuccessIdentifierTimestamp(profileID, identifier) != eventTimestamp) {
        return NO;
    }

    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *activeIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                         suffix:@"activeIssueAt"];
    NSString *dismissedIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                            suffix:@"dismissedIssueAt"];
    NSString *latestIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                         suffix:@"latestDeliveredIssueAt"];
    NSString *latestIssueStateKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                              suffix:@"latestDeliveredIssueState"];
    NSTimeInterval latestAcceptedIssueTimestamp = 0;
    NSUInteger latestAcceptedIssueStage = 0;
    GDTBackupNotificationAcceptedState(
        defaults, latestIssueStateKey, latestIssueKey,
        &latestAcceptedIssueTimestamp, &latestAcceptedIssueStage);
    (void)latestAcceptedIssueStage;
    NSTimeInterval dismissedIssueTimestamp =
        [defaults doubleForKey:dismissedIssueKey];
    NSTimeInterval newestIssueTimestamp = MAX(
        dismissedIssueTimestamp,
        MAX([defaults doubleForKey:activeIssueKey], latestAcceptedIssueTimestamp));
    if (newestIssueTimestamp >= eventTimestamp) return NO;

    NSString *bodyKey = decision[@"bodyKey"] ?: @"";
    BOOL recovery = [@[@"backupNotificationRecoverySuccessBody",
                       @"backupNotificationRetrySuccessBody"] containsObject:bodyKey];
    if (recovery && (capturedActiveIssueTimestamp <= 0 ||
                     dismissedIssueTimestamp >= capturedActiveIssueTimestamp)) {
        // A recovery refers to the issue captured before the background read.
        // A later acknowledgement must not be overwritten by that stale snapshot.
        return NO;
    }

    // Settings and the durable summary can change while Notification Center
    // callbacks are pending. Recreate the policy decision from those sources
    // at every delivery boundary instead of accepting an obsolete snapshot.
    return [self isBackupSuccessDecisionSourceCurrent:decision
                          capturedActiveIssueTimestamp:capturedActiveIssueTimestamp];
}

- (NSTimeInterval)reconcileBackupSuccessNotificationsForProfileID:
    (NSString *)profileID
                                      deliveredNotifications:
    (NSArray<UNNotification *> *)deliveredNotifications
                                            pendingRequests:
    (NSArray<UNNotificationRequest *> *)pendingRequests {
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *stateKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                    suffix:@"latestDeliveredSuccessState"];
    NSString *timestampKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                        suffix:@"lastDeliveredSuccessAt"];
    NSString *identifierKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                         suffix:@"lastDeliveredSuccessIdentifier"];
    NSTimeInterval acceptedTimestamp = 0;
    NSString *acceptedIdentifier = nil;
    GDTBackupSuccessAcceptedState(defaults, profileID, stateKey, timestampKey,
                                  identifierKey, &acceptedTimestamp,
                                  &acceptedIdentifier);

    NSMutableArray<NSDictionary<NSString *, id> *> *deliveredCandidates =
        [NSMutableArray array];
    for (UNNotification *notification in deliveredNotifications ?: @[]) {
        UNNotificationRequest *request = notification.request;
        NSTimeInterval candidateTimestamp = 0;
        if (!GDTBackupSuccessRequestMatches(
                profileID, request.identifier, request.content.categoryIdentifier ?: @"",
                [request.content.userInfo isKindOfClass:NSDictionary.class]
                    ? request.content.userInfo : @{}, &candidateTimestamp)) {
            continue;
        }
        [deliveredCandidates addObject:@{
            @"identifier": request.identifier,
            @"timestamp": @(candidateTimestamp)
        }];
        if (candidateTimestamp > acceptedTimestamp) {
            acceptedTimestamp = candidateTimestamp;
            acceptedIdentifier = request.identifier;
        }
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *pendingCandidates =
        [NSMutableArray array];
    for (UNNotificationRequest *request in pendingRequests ?: @[]) {
        NSTimeInterval candidateTimestamp = 0;
        if (!GDTBackupSuccessRequestMatches(
                profileID, request.identifier, request.content.categoryIdentifier ?: @"",
                [request.content.userInfo isKindOfClass:NSDictionary.class]
                    ? request.content.userInfo : @{}, &candidateTimestamp)) {
            continue;
        }
        [pendingCandidates addObject:@{
            @"identifier": request.identifier,
            @"timestamp": @(candidateTimestamp)
        }];
        if (candidateTimestamp > acceptedTimestamp) {
            acceptedTimestamp = candidateTimestamp;
            acceptedIdentifier = request.identifier;
        }
    }

    if (acceptedTimestamp > 0 && acceptedIdentifier.length) {
        GDTPersistBackupSuccessAcceptedState(
            defaults, stateKey, timestampKey, identifierKey,
            acceptedTimestamp, acceptedIdentifier);
    }

    NSMutableOrderedSet<NSString *> *deliveredRetirements =
        [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *pendingRetirements =
        [NSMutableOrderedSet orderedSet];
    for (NSDictionary<NSString *, id> *candidate in deliveredCandidates) {
        if ([candidate[@"timestamp"] doubleValue] < acceptedTimestamp) {
            [deliveredRetirements addObject:candidate[@"identifier"]];
        }
    }
    for (NSDictionary<NSString *, id> *candidate in pendingCandidates) {
        if ([candidate[@"timestamp"] doubleValue] < acceptedTimestamp) {
            [pendingRetirements addObject:candidate[@"identifier"]];
        }
    }
    if (deliveredRetirements.count) {
        [self removeDeliveredBackupNotificationIdentifiers:
            deliveredRetirements.array];
    }
    if (pendingRetirements.count) {
        [self removePendingBackupNotificationIdentifiers:pendingRetirements.array];
    }
    return acceptedTimestamp;
}

- (void)reconcileBackupSuccessNotificationsForProfileID:(NSString *)profileID
                                              completion:(void (^)(NSTimeInterval))completion {
    __weak typeof(self) weakSelf = self;
    // Requests move from pending to delivered. Reading pending first means a
    // transition during reconciliation is visible in at least one snapshot.
    [self enumeratePendingBackupNotificationRequestsWithCompletion:
        ^(NSArray<UNNotificationRequest *> *pendingRequests) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf enumerateDeliveredBackupNotificationsWithCompletion:
            ^(NSArray<UNNotification *> *deliveredNotifications) {
            void (^finish)(void) = ^{
                typeof(self) innerSelf = weakSelf;
                if (!innerSelf) return;
                NSTimeInterval timestamp = [innerSelf
                    reconcileBackupSuccessNotificationsForProfileID:profileID
                                            deliveredNotifications:deliveredNotifications
                                                  pendingRequests:pendingRequests];
                if (completion) completion(timestamp);
            };
            if (NSThread.isMainThread) {
                finish();
            } else {
                dispatch_async(dispatch_get_main_queue(), finish);
            }
        }];
    }];
}

- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision {
    // Direct callers have no refresh snapshot; production supplies one below
    // so it can revalidate the current issue after asynchronous reconciliation.
    [self processBackupSuccessNotificationDecision:decision
                          capturedActiveIssueTimestamp:-1];
}

- (void)processBackupSuccessNotificationDecision:
    (NSDictionary<NSString *, NSString *> *)decision
         capturedActiveIssueTimestamp:(NSTimeInterval)capturedActiveIssueTimestamp {
    NSDictionary<NSString *, NSString *> *deliveryDecision = [decision copy];
    NSString *identifier = deliveryDecision[@"identifier"];
    NSString *profileID = deliveryDecision[@"profileID"];
    NSTimeInterval eventTimestamp =
        GDTCanonicalBackupNotificationTimestamp(deliveryDecision[@"eventTimestamp"]);
    if (!identifier.length || !profileID.length ||
        ![deliveryDecision[@"kind"] isEqualToString:@"success"] ||
        !deliveryDecision[@"titleKey"].length || !deliveryDecision[@"bodyKey"].length ||
        eventTimestamp <= 0 ||
        GDTBackupSuccessIdentifierTimestamp(profileID, identifier) != eventTimestamp) {
        return;
    }

    if (!self.pendingBackupSuccessIdentifiers) {
        self.pendingBackupSuccessIdentifiers = [NSMutableSet set];
    }
    if ([self.pendingBackupSuccessIdentifiers containsObject:identifier]) return;
    [self.pendingBackupSuccessIdentifiers addObject:identifier];

    __weak typeof(self) weakSelf = self;
    [self reconcileBackupSuccessNotificationsForProfileID:profileID
                                                completion:^(NSTimeInterval acceptedTimestamp) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf ||
            ![strongSelf.pendingBackupSuccessIdentifiers containsObject:identifier]) {
            return;
        }
        if (eventTimestamp <= acceptedTimestamp) {
            [strongSelf.pendingBackupSuccessIdentifiers removeObject:identifier];
            return;
        }
        if (capturedActiveIssueTimestamp >= 0 &&
            ![strongSelf isBackupSuccessDecisionCurrent:deliveryDecision
                               capturedActiveIssueTimestamp:capturedActiveIssueTimestamp]) {
            [strongSelf.pendingBackupSuccessIdentifiers removeObject:identifier];
            return;
        }

        [strongSelf deliverBackupSuccessNotificationDecision:deliveryDecision
                                 capturedActiveIssueTimestamp:capturedActiveIssueTimestamp
                                                    completion:^(BOOL delivered) {
            void (^finish)(void) = ^{
                typeof(self) innerSelf = weakSelf;
                if (!innerSelf) return;
                [innerSelf.pendingBackupSuccessIdentifiers removeObject:identifier];
                if (!delivered) return;

                if (capturedActiveIssueTimestamp >= 0 &&
                    ![innerSelf isBackupSuccessDecisionCurrent:deliveryDecision
                                       capturedActiveIssueTimestamp:
                        capturedActiveIssueTimestamp]) {
                    [innerSelf removeDeliveredBackupNotificationIdentifiers:@[identifier]];
                    [innerSelf removePendingBackupNotificationIdentifiers:@[identifier]];
                    return;
                }

                NSUserDefaults *defaults = [innerSelf backupNotificationDefaultsStore];
                NSString *stateKey = [innerSelf
                    backupNotificationDefaultsKeyForProfileID:profileID
                                                        suffix:@"latestDeliveredSuccessState"];
                NSString *timestampKey = [innerSelf
                    backupNotificationDefaultsKeyForProfileID:profileID
                                                        suffix:@"lastDeliveredSuccessAt"];
                NSString *identifierKey = [innerSelf
                    backupNotificationDefaultsKeyForProfileID:profileID
                                                        suffix:@"lastDeliveredSuccessIdentifier"];
                NSTimeInterval currentTimestamp = 0;
                GDTBackupSuccessAcceptedState(
                    defaults, profileID, stateKey, timestampKey, identifierKey,
                    &currentTimestamp, nil);
                if (eventTimestamp <= currentTimestamp) {
                    [innerSelf removeDeliveredBackupNotificationIdentifiers:@[identifier]];
                    [innerSelf removePendingBackupNotificationIdentifiers:@[identifier]];
                    return;
                }

                // Persist one coherent success state before touching prior
                // requests; a restart can then reconcile an interrupted cleanup.
                GDTPersistBackupSuccessAcceptedState(
                    defaults, stateKey, timestampKey, identifierKey,
                    eventTimestamp, identifier);
                // Only Notification Center metadata can authorize retirement:
                // a matching identifier alone may belong to a different kind.
                [innerSelf reconcileBackupSuccessNotificationsForProfileID:profileID
                                                                  completion:nil];
            };
            if (NSThread.isMainThread) {
                finish();
            } else {
                dispatch_async(dispatch_get_main_queue(), finish);
            }
        }];
    }];
}

- (void)removeExactBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                      forProfileID:(NSString *)profileID {
    NSArray<NSString *> *safeIdentifiers =
        [GDTBackupNotificationPolicy
            failureNotificationIdentifiersForProfileID:profileID
                                  candidateIdentifiers:identifiers];
    if (!safeIdentifiers.count) return;
    [self removeDeliveredBackupNotificationIdentifiers:safeIdentifiers];
    [self removePendingBackupNotificationIdentifiers:safeIdentifiers];
}

- (void)removeDeliveredBackupNotificationIdentifiers:
    (NSArray<NSString *> *)identifiers {
    [UNUserNotificationCenter.currentNotificationCenter
        removeDeliveredNotificationsWithIdentifiers:identifiers];
}

- (void)removePendingBackupNotificationIdentifiers:
    (NSArray<NSString *> *)identifiers {
    [UNUserNotificationCenter.currentNotificationCenter
        removePendingNotificationRequestsWithIdentifiers:identifiers];
}

- (void)retireSupersededBackupNotificationForDecision:
    (NSDictionary<NSString *, NSString *> *)decision {
    NSString *profileID = decision[@"profileID"];
    NSString *identifier = decision[@"identifier"];
    NSString *supersededIdentifier = decision[@"supersedesIdentifier"];
    if (!profileID.length || !identifier.length ||
        !supersededIdentifier.length ||
        [identifier isEqualToString:supersededIdentifier]) {
        return;
    }
    NSArray<NSString *> *safeSuperseded =
        [GDTBackupNotificationPolicy
            failureNotificationIdentifiersForProfileID:profileID
                                  candidateIdentifiers:@[supersededIdentifier]];
    if (safeSuperseded.count != 1) return;

    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *deliveredKey =
        [self backupNotificationDefaultsKeyForProfileID:profileID
                                                 suffix:@"deliveredFailureIdentifiers"];
    NSMutableArray<NSString *> *identifiers =
        [[defaults stringArrayForKey:deliveredKey] mutableCopy] ?:
        [NSMutableArray array];
    [identifiers removeObject:supersededIdentifier];
    if (![identifiers containsObject:identifier]) {
        [identifiers addObject:identifier];
    }
    [defaults setObject:identifiers forKey:deliveredKey];
    [self removeExactBackupNotificationIdentifiers:safeSuperseded
                                       forProfileID:profileID];
}

- (void)enumerateDeliveredBackupNotificationsWithCompletion:
    (void (^)(NSArray<UNNotification *> *notifications))completion {
    [UNUserNotificationCenter.currentNotificationCenter
        getDeliveredNotificationsWithCompletionHandler:completion];
}

- (void)enumeratePendingBackupNotificationRequestsWithCompletion:
    (void (^)(NSArray<UNNotificationRequest *> *requests))completion {
    [UNUserNotificationCenter.currentNotificationCenter
        getPendingNotificationRequestsWithCompletionHandler:completion];
}

- (void)removeBackupNotificationIdentifiers:(NSArray<NSString *> *)identifiers
                                forProfileID:(NSString *)profileID
                 throughIssueOriginTimestamp:(NSTimeInterval)cutoff {
    [self enumerateDeliveredBackupNotificationsWithCompletion:
        ^(NSArray<UNNotification *> *notifications) {
        NSMutableOrderedSet<NSString *> *candidateOrder =
            [NSMutableOrderedSet orderedSet];
        NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *candidatesByID =
            [NSMutableDictionary dictionary];
        for (id value in identifiers ?: @[]) {
            if (![value isKindOfClass:NSString.class] || ![value length]) continue;
            NSString *identifier = value;
            [candidateOrder addObject:identifier];
            candidatesByID[identifier] = @{@"identifier": identifier};
        }
        for (UNNotification *notification in notifications ?: @[]) {
            NSString *identifier = notification.request.identifier;
            if (!identifier.length) continue;
            UNNotificationContent *content = notification.request.content;
            NSString *category = content.categoryIdentifier ?: @"";
            NSDictionary *userInfo = [content.userInfo isKindOfClass:NSDictionary.class]
                ? content.userInfo : @{};
            NSMutableDictionary<NSString *, id> *candidate =
                [@{@"identifier": identifier} mutableCopy];
            if (category.length || userInfo.count) {
                candidate[@"categoryIdentifier"] = category;
                candidate[@"userInfo"] = userInfo;
            }
            [candidateOrder addObject:identifier];
            // Notification Center is authoritative for a currently delivered
            // identifier; its metadata must not be bypassed by a legacy entry.
            candidatesByID[identifier] = candidate;
        }
        NSMutableArray<NSDictionary<NSString *, id> *> *candidates =
            [NSMutableArray arrayWithCapacity:candidateOrder.count];
        for (NSString *identifier in candidateOrder) {
            [candidates addObject:candidatesByID[identifier]];
        }
        NSArray<NSString *> *safeIdentifiers =
            [GDTBackupNotificationPolicy
                failureNotificationIdentifiersForProfileID:profileID
                             throughIssueOriginTimestamp:cutoff
                                  candidateNotifications:candidates];
        if (!safeIdentifiers.count) return;
        [self removeDeliveredBackupNotificationIdentifiers:safeIdentifiers];
        [self removePendingBackupNotificationIdentifiers:safeIdentifiers];
    }];
}

- (void)clearBackupFailureNotificationsForConfig:
    (NSDictionary<NSString *, NSString *> *)config
    summary:(NSDictionary<NSString *, NSString *> *)summary
    status:(NSString *)status {
    NSString *trigger = summary[@"trigger"] ?: @"";
    NSTimeInterval finishedAt = [summary[@"finished_at"] doubleValue];
    if (![status isEqualToString:@"success"] ||
        ![@[@"schedule", @"schedule-retry"] containsObject:trigger] ||
        finishedAt <= 0) {
        return;
    }
    NSString *profileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *deliveredKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"deliveredFailureIdentifiers"];
    NSString *latestIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                        suffix:@"latestDeliveredIssueAt"];
    NSString *latestIssueStageKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"latestDeliveredIssueStage"];
    NSString *latestIssueStateKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"latestDeliveredIssueState"];
    NSString *activeIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                        suffix:@"activeIssueAt"];
    NSString *dismissedIssueKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                           suffix:@"dismissedIssueAt"];
    NSTimeInterval latestAcceptedIssueAt = 0;
    NSUInteger latestAcceptedIssueStage = 0;
    GDTBackupNotificationAcceptedState(
        defaults, latestIssueStateKey, latestIssueKey,
        &latestAcceptedIssueAt, &latestAcceptedIssueStage);
    NSTimeInterval latestIssueAt = MAX(
        latestAcceptedIssueAt,
        MAX([defaults doubleForKey:activeIssueKey],
            [defaults doubleForKey:dismissedIssueKey]));
    if (latestIssueAt > 0 && finishedAt <= latestIssueAt) {
        return;
    }
    if (!self.backupNotificationGenerationsByProfileID) {
        self.backupNotificationGenerationsByProfileID =
            [NSMutableDictionary dictionary];
    }
    NSUInteger generation =
        self.backupNotificationGenerationsByProfileID[profileID]
            .unsignedIntegerValue;
    self.backupNotificationGenerationsByProfileID[profileID] = @(generation + 1);

    NSDictionary<NSString *, NSString *> *queuedDecision =
        self.queuedBackupNotificationDecisionsByProfileID[profileID];
    if (queuedDecision) {
        NSString *queuedRevision =
            [queuedDecision[@"revision"] isKindOfClass:NSString.class]
                ? queuedDecision[@"revision"] : @"";
        NSString *queuedKey = [NSString stringWithFormat:@"%@\n%@",
            queuedDecision[@"identifier"] ?: @"", queuedRevision];
        [self.pendingBackupNotificationIdentifiers removeObject:queuedKey];
        [self.queuedBackupNotificationDecisionsByProfileID
            removeObjectForKey:profileID];
    }
    NSMutableArray<NSString *> *identifiers =
        [[defaults stringArrayForKey:deliveredKey] mutableCopy] ?: [NSMutableArray array];
    NSString *lastKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                  suffix:@"lastDeliveredIdentifier"];
    NSString *legacyIdentifier = [defaults stringForKey:lastKey];
    if (legacyIdentifier.length && ![identifiers containsObject:legacyIdentifier]) {
        [identifiers addObject:legacyIdentifier];
    }
    [self removeBackupNotificationIdentifiers:identifiers
                                  forProfileID:profileID
                   throughIssueOriginTimestamp:finishedAt];
    [defaults removeObjectForKey:deliveredKey];
    [defaults removeObjectForKey:lastKey];
    [defaults removeObjectForKey:[self backupNotificationDefaultsKeyForProfileID:profileID
                                                                           suffix:@"lastDeliveredRevision"]];
    [defaults removeObjectForKey:latestIssueKey];
    [defaults removeObjectForKey:latestIssueStageKey];
    [defaults removeObjectForKey:latestIssueStateKey];
    [defaults removeObjectForKey:dismissedIssueKey];
    [defaults removeObjectForKey:activeIssueKey];
    [defaults removeObjectForKey:[self backupNotificationDefaultsKeyForProfileID:profileID
                                                                           suffix:@"activeIssueKind"]];
    [defaults removeObjectForKey:[self backupNotificationDefaultsKeyForProfileID:profileID
                                                                           suffix:@"activeIssueIdentifier"]];
}

- (NSString *)automaticRetrySummaryPathForProfileID:(NSString *)profileID {
    if (!profileID.length) return @"";
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *configuredProfileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    if (![configuredProfileID isEqualToString:profileID]) return @"";
    return GDTBackupSummaryPathForConfig(config);
}

- (NSDictionary<NSString *, NSString *> *)automaticRetrySummaryAtPath:(NSString *)path {
    return path.length ? GDTReadBackupSummaryAtPath(path) : @{};
}

- (NSDictionary<NSString *, NSString *> *)automaticRetryDecisionForSummary:
    (NSDictionary<NSString *, NSString *> *)summary
                                                               summaryPath:(NSString *)summaryPath
                                                                 profileID:(NSString *)profileID {
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *configuredProfileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    if (![configuredProfileID isEqualToString:profileID] ||
        ![GDTBackupSummaryPathForConfig(config) isEqualToString:summaryPath]) {
        return nil;
    }
    NSString *status = GDTBackupSummaryStatusForValues(summary);
    return [GDTAutomaticRetryPolicy decisionForConfig:config
                                               summary:summary
                                                status:status
                                                   now:[NSDate date]];
}

- (NSDictionary<NSString *, NSString *> *)currentAutomaticRetryDecision {
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSDictionary<NSString *, NSString *> *summary = GDTReadBackupSummaryAtPath(
        GDTBackupSummaryPathForConfig(config));
    NSString *status = GDTBackupSummaryStatusForValues(summary);
    return [GDTAutomaticRetryPolicy decisionForConfig:config
                                               summary:summary
                                                status:status
                                                   now:[NSDate date]];
}

- (NSString *)automaticRetryLockPath {
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *path = config[@"GDRIVE_BACKUP_LOCK"];
    if (!path.length) {
        path = NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_LOCK"];
    }
    if (!path.length) {
        path = [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Logs/gdrive-backup.lock"];
    }

    NSString *home = NSHomeDirectory();
    if ([path isEqualToString:@"$HOME"] || [path isEqualToString:@"${HOME}"]) {
        path = home;
    } else if ([path hasPrefix:@"$HOME/"]) {
        path = [home stringByAppendingPathComponent:[path substringFromIndex:6]];
    } else if ([path hasPrefix:@"${HOME}/"]) {
        path = [home stringByAppendingPathComponent:[path substringFromIndex:8]];
    } else {
        path = path.stringByExpandingTildeInPath;
    }
    return path.isAbsolutePath ? path.stringByStandardizingPath : @"";
}

- (BOOL)automaticRetryLockIsAvailable {
    NSString *path = [self automaticRetryLockPath];
    if (!path.length) return NO;

    int descriptor;
    do {
        descriptor = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    } while (descriptor < 0 && errno == EINTR);
    if (descriptor < 0) {
        // A missing lock file means no backup has acquired it yet. Any race
        // after this observation is closed by the engine's own exclusive lock.
        return errno == ENOENT;
    }

    int lockStatus;
    do {
        lockStatus = flock(descriptor, LOCK_SH | LOCK_NB);
    } while (lockStatus != 0 && errno == EINTR);
    if (lockStatus == 0) {
        (void)flock(descriptor, LOCK_UN);
    }
    (void)close(descriptor);
    return lockStatus == 0;
}

- (BOOL)automaticRetrySummary:(NSDictionary<NSString *, NSString *> *)summary
              confirmsDecision:(NSDictionary<NSString *, NSString *> *)decision {
    NSString *status = GDTBackupSummaryStatusForValues(summary);
    if (![@[@"success", @"failure", @"cancelled"] containsObject:status] ||
        ![summary[@"trigger"] isEqualToString:@"schedule-retry"] ||
        ![summary[@"target"] isEqualToString:@"nas"] ||
        ![summary[@"retry_attempt"] isEqualToString:decision[@"attempt"]] ||
        ![summary[@"retry_origin_started_at"]
            isEqualToString:decision[@"originStartedAt"]]) {
        return NO;
    }
    NSTimeInterval origin =
        GDTCanonicalBackupNotificationTimestamp(decision[@"originStartedAt"]);
    NSTimeInterval started =
        GDTCanonicalBackupNotificationTimestamp(summary[@"started_at"]);
    return origin > 0 && started > origin;
}

- (NSTimeInterval)automaticRetryOriginForIdentifier:(NSString *)identifier
                                          profileID:(NSString *)profileID {
    if (!identifier.length || !profileID.length) return 0;
    NSString *prefix = [NSString stringWithFormat:
        @"%@.automatic-retry.", profileID];
    if (![identifier hasPrefix:prefix]) return 0;
    return GDTCanonicalBackupNotificationTimestamp(
        [identifier substringFromIndex:prefix.length]);
}

- (void)processAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision {
    NSString *identifier = decision[@"identifier"];
    NSString *profileID = decision[@"profileID"];
    if (!identifier.length || !profileID.length ||
        !decision[@"originStartedAt"].length ||
        ![decision[@"attempt"] isEqualToString:@"1"] ||
        ![decision[@"trigger"] isEqualToString:@"schedule-retry"]) {
        return;
    }

    NSTimeInterval decisionOrigin =
        GDTCanonicalBackupNotificationTimestamp(decision[@"originStartedAt"]);
    if (decisionOrigin <= 0 ||
        [self automaticRetryOriginForIdentifier:identifier profileID:profileID] !=
            decisionOrigin) {
        return;
    }

    NSDictionary<NSString *, NSString *> *currentDecision =
        [self currentAutomaticRetryDecision];
    if (![currentDecision[@"identifier"] isEqualToString:identifier] ||
        ![currentDecision[@"profileID"] isEqualToString:profileID] ||
        ![currentDecision[@"originStartedAt"] isEqualToString:decision[@"originStartedAt"]] ||
        ![currentDecision[@"attempt"] isEqualToString:decision[@"attempt"]] ||
        ![currentDecision[@"trigger"] isEqualToString:decision[@"trigger"]]) {
        return;
    }

    NSString *summaryPath = [self automaticRetrySummaryPathForProfileID:profileID];
    if (!summaryPath.length) return;
    NSDictionary<NSString *, NSString *> *currentSummary =
        [self automaticRetrySummaryAtPath:summaryPath];
    NSDictionary<NSString *, NSString *> *latestDecision =
        [self automaticRetryDecisionForSummary:currentSummary
                                    summaryPath:summaryPath
                                      profileID:profileID];
    if (![latestDecision[@"identifier"] isEqualToString:identifier] ||
        ![latestDecision[@"profileID"] isEqualToString:profileID] ||
        ![latestDecision[@"originStartedAt"]
            isEqualToString:decision[@"originStartedAt"]] ||
        ![latestDecision[@"attempt"] isEqualToString:decision[@"attempt"]] ||
        ![latestDecision[@"trigger"] isEqualToString:decision[@"trigger"]]) {
        return;
    }
    NSString *key = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                              suffix:@"lastAutomaticRetryIdentifier"];
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    if ([[defaults stringForKey:key] isEqualToString:identifier] &&
        [self automaticRetrySummary:currentSummary confirmsDecision:decision]) {
        return;
    }

    NSString *existingIdentifier = [defaults stringForKey:key];
    if (existingIdentifier.length && ![existingIdentifier isEqualToString:identifier]) {
        NSTimeInterval existingOrigin =
            [self automaticRetryOriginForIdentifier:existingIdentifier profileID:profileID];
        if (existingOrigin <= 0 || existingOrigin > decisionOrigin) return;
    }

    if ([self.automaticRetryIdentifiersInFlight containsObject:identifier] ||
        ![self automaticRetryLockIsAvailable]) {
        return;
    }
    if (!self.automaticRetryIdentifiersInFlight) {
        self.automaticRetryIdentifiersInFlight = [NSMutableSet set];
    }
    [self.automaticRetryIdentifiersInFlight addObject:identifier];

    NSDictionary<NSString *, NSString *> *launchedDecision = [decision copy];
    __weak typeof(self) weakSelf = self;
    BOOL launched = [self launchAutomaticRetryDecision:launchedDecision
                                            completion:^(NSInteger status) {
        (void)status;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.automaticRetryIdentifiersInFlight removeObject:identifier];

        NSDictionary<NSString *, NSString *> *summary =
            [strongSelf automaticRetrySummaryAtPath:summaryPath];
        NSUserDefaults *currentDefaults = [strongSelf backupNotificationDefaultsStore];
        NSString *existingIdentifier = [currentDefaults stringForKey:key];
        BOOL claimMayAdvance = !existingIdentifier.length ||
            [existingIdentifier isEqualToString:identifier];
        if (!claimMayAdvance) {
            NSTimeInterval existingOrigin = [strongSelf
                automaticRetryOriginForIdentifier:existingIdentifier
                                          profileID:launchedDecision[@"profileID"]];
            NSTimeInterval launchedOrigin = GDTCanonicalBackupNotificationTimestamp(
                launchedDecision[@"originStartedAt"]);
            // A late completion may advance an older profile marker, but it
            // must never roll a newer controller decision backwards.
            claimMayAdvance = existingOrigin > 0 && existingOrigin < launchedOrigin;
        }
        if (claimMayAdvance &&
            [strongSelf automaticRetrySummary:summary confirmsDecision:launchedDecision]) {
            [currentDefaults setObject:identifier forKey:key];
        }
        [strongSelf refreshOverviewStatus:nil];
    }];
    if (!launched) {
        [self.automaticRetryIdentifiersInFlight removeObject:identifier];
    }
}

- (NSString *)backupAlertStatusForConfig:(NSDictionary<NSString *, NSString *> *)config
                                  summary:(NSDictionary<NSString *, NSString *> *)summary
                                rawStatus:(NSString *)rawStatus
                                 decision:(NSDictionary<NSString *, NSString *> *)decision {
    NSString *profileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *kindKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                  suffix:@"activeIssueKind"];
    NSString *timeKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                  suffix:@"activeIssueAt"];
    NSString *identifierKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                        suffix:@"activeIssueIdentifier"];
    NSString *dismissedKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"dismissedIssueAt"];
    NSTimeInterval dismissedAt = [defaults doubleForKey:dismissedKey];
    NSTimeInterval activeSince = [defaults doubleForKey:timeKey];
    if (activeSince > 0 && activeSince <= dismissedAt) {
        [defaults removeObjectForKey:kindKey];
        [defaults removeObjectForKey:timeKey];
        [defaults removeObjectForKey:identifierKey];
        activeSince = 0;
    }

    NSTimeInterval decisionOrigin =
        GDTBackupNotificationTimestamp(decision[@"issueOriginTimestamp"]);
    if ([decision[@"profileID"] isEqualToString:profileID] &&
        [@[@"failure", @"missed"] containsObject:decision[@"kind"]] &&
        decisionOrigin > dismissedAt && decision[@"identifier"].length &&
        decisionOrigin >= activeSince) {
        if (decisionOrigin > activeSince || activeSince <= 0) {
            [defaults setObject:decision[@"kind"] forKey:kindKey];
            [defaults setDouble:decisionOrigin forKey:timeKey];
            [defaults setObject:decision[@"identifier"] forKey:identifierKey];
            activeSince = decisionOrigin;
        } else if (![defaults stringForKey:identifierKey].length) {
            [defaults setObject:decision[@"identifier"] forKey:identifierKey];
        }
    }

    NSTimeInterval retryOrigin =
        GDTBackupNotificationTimestamp(summary[@"retry_origin_started_at"]);
    NSTimeInterval retryStarted =
        GDTBackupNotificationTimestamp(summary[@"started_at"]);
    BOOL retryRunning = [rawStatus isEqualToString:@"running"] &&
        [summary[@"trigger"] isEqualToString:@"schedule-retry"] &&
        [summary[@"retry_attempt"] isEqualToString:@"1"] &&
        retryOrigin > 0 && retryStarted > retryOrigin &&
        [decision[@"profileID"] isEqualToString:profileID] &&
        [decision[@"kind"] isEqualToString:@"retry-running"] &&
        decisionOrigin == retryOrigin && decision[@"identifier"].length;
    if (retryRunning) return @"retry-running";

    NSString *activeKind = [defaults stringForKey:kindKey];
    activeSince = [defaults doubleForKey:timeKey];
    if (![@[@"failure", @"missed"] containsObject:activeKind] || activeSince <= 0) {
        return rawStatus;
    }
    NSTimeInterval finishedAt = [summary[@"finished_at"] doubleValue];
    BOOL automaticSuccess = [@[@"schedule", @"schedule-retry"]
        containsObject:(summary[@"trigger"] ?: @"")];
    if ([rawStatus isEqualToString:@"success"] && automaticSuccess &&
        finishedAt > activeSince) {
        [defaults removeObjectForKey:kindKey];
        [defaults removeObjectForKey:timeKey];
        [defaults removeObjectForKey:identifierKey];
        return rawStatus;
    }
    return activeKind;
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    (void)center;
    completionHandler([self presentationOptionsForNotificationCategoryIdentifier:
        notification.request.content.categoryIdentifier]);
}

- (UNNotificationPresentationOptions)presentationOptionsForNotificationCategoryIdentifier:
    (NSString *)categoryIdentifier {
    if ([categoryIdentifier isEqualToString:@"GDT_UPDATE_AVAILABLE"]) {
        return UNNotificationPresentationOptionList;
    }
    if ([categoryIdentifier isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME"] ||
        [categoryIdentifier isEqualToString:@"GDT_BACKUP_SUCCESS"]) {
        return UNNotificationPresentationOptionBanner |
            UNNotificationPresentationOptionList;
    }
    return UNNotificationPresentationOptionBanner |
        UNNotificationPresentationOptionList |
        UNNotificationPresentationOptionSound;
}

- (BOOL)isWritableExternalAPFSDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    NSString *path = [descriptor[@"path"] isKindOfClass:NSString.class]
        ? [descriptor[@"path"] stringByStandardizingPath] : @"";
    BOOL safeMountRoot = [path hasPrefix:@"/Volumes/"] &&
        path.pathComponents.count == 3;
    return [self isUnknownExternalVolumeDescriptorEligible:descriptor] &&
        ![descriptor[@"isBackupVolume"] boolValue] &&
        safeMountRoot &&
        [descriptor[@"isWritable"] boolValue] &&
        [descriptor[@"filesystem"] isKindOfClass:NSString.class] &&
        [descriptor[@"filesystem"] caseInsensitiveCompare:@"apfs"] ==
            NSOrderedSame;
}

- (void)revalidateUnknownExternalVolumeCandidatesForUserInfo:(NSDictionary *)userInfo
                                                  completion:
    (void (^)(NSArray<NSDictionary<NSString *, id> *> *descriptors))completion {
    NSString *diskID = [userInfo[@"diskID"] isKindOfClass:NSString.class]
        ? userInfo[@"diskID"] : @"";
    NSString *volumeUUID = [userInfo[@"volumeUUID"] isKindOfClass:NSString.class]
        ? [userInfo[@"volumeUUID"] uppercaseString] : @"";
    if (!diskID.length || !volumeUUID.length) {
        completion(@[]);
        return;
    }
    NSMutableSet<NSString *> *attachmentVolumeUUIDs =
        [NSMutableSet setWithObject:volumeUUID];
    NSArray *savedAttachmentVolumeUUIDs =
        [userInfo[@"attachmentVolumeUUIDs"] isKindOfClass:NSArray.class]
            ? userInfo[@"attachmentVolumeUUIDs"] : @[];
    for (id value in savedAttachmentVolumeUUIDs) {
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [attachmentVolumeUUIDs addObject:[value uppercaseString]];
        }
    }
    [attachmentVolumeUUIDs unionSet:
        [self rememberedUnknownExternalVolumeUUIDsForDiskID:diskID]];

    NSMutableOrderedSet<NSString *> *candidatePaths =
        [NSMutableOrderedSet orderedSet];
    for (NSDictionary<NSString *, id> *descriptor in
         self.mountedExternalVolumeDescriptorsByPath.allValues ?: @[]) {
        if ([descriptor[@"diskID"] isEqualToString:diskID] &&
            [attachmentVolumeUUIDs containsObject:
                [descriptor[@"volumeUUID"] uppercaseString]]) {
            NSString *path = descriptor[@"path"];
            if (path.length) {
                [candidatePaths addObject:path.stringByStandardizingPath];
            }
        }
    }
    for (NSString *path in
         [self mountedVolumePathsForUnknownExternalVolumeRevalidation]) {
        if (path.length) {
            [candidatePaths addObject:path.stringByStandardizingPath];
        }
    }
    [self revalidateUnknownExternalVolumePaths:candidatePaths.array
                                       atIndex:0
                                matchingDiskID:diskID
                                   volumeUUIDs:attachmentVolumeUUIDs
                           offeredVolumeUUID:volumeUUID
                              validDescriptors:[NSMutableArray array]
                                    completion:completion];
}

- (NSArray<NSString *> *)mountedVolumePathsForUnknownExternalVolumeRevalidation {
    NSArray<NSURL *> *mountedURLs = [NSFileManager.defaultManager
        mountedVolumeURLsIncludingResourceValuesForKeys:nil options:0] ?: @[];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in mountedURLs) {
        if (!url.isFileURL) continue;
        NSString *path = url.path.stringByStandardizingPath;
        if ([path hasPrefix:@"/Volumes/"] && path.pathComponents.count == 3) {
            [paths addObject:path];
        }
    }
    return paths;
}

- (void)deliveredUnknownExternalVolumeUUIDsByDiskIDWithCompletion:
    (void (^)(NSDictionary<NSString *, NSString *> *volumeUUIDsByDiskID))completion {
    [UNUserNotificationCenter.currentNotificationCenter
        getDeliveredNotificationsWithCompletionHandler:
            ^(NSArray<UNNotification *> *notifications) {
        NSMutableDictionary<NSString *, NSString *> *delivered =
            [NSMutableDictionary dictionary];
        for (UNNotification *notification in notifications) {
            UNNotificationContent *content = notification.request.content;
            if (![content.categoryIdentifier
                    isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME"]) {
                continue;
            }
            NSString *diskID =
                [content.userInfo[@"diskID"] isKindOfClass:NSString.class]
                    ? content.userInfo[@"diskID"] : @"";
            NSString *volumeUUID =
                [content.userInfo[@"volumeUUID"] isKindOfClass:NSString.class]
                    ? [content.userInfo[@"volumeUUID"] uppercaseString] : @"";
            if (diskID.length && volumeUUID.length && !delivered[diskID]) {
                delivered[diskID] = volumeUUID;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(delivered);
        });
    }];
}

- (void)reconcilePrimedExternalVolumeDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors
    deliveredVolumeUUIDsByDiskID:
    (NSDictionary<NSString *, NSString *> *)deliveredVolumeUUIDsByDiskID {
    NSSet<NSString *> *knownUUIDs = [self configuredExternalVolumeUUIDs];
    NSMutableDictionary<NSString *,
        NSMutableArray<NSDictionary<NSString *, id> *> *> *groups =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *descriptor in descriptors) {
        NSString *path = descriptor[@"path"];
        if (!path.length) continue;
        self.mountedExternalVolumeDescriptorsByPath[path] = descriptor;
    }
    // Mount notifications continue while the startup snapshot is being
    // inspected. Grouping the complete live cache preserves any second disk
    // that arrived during that window and prevents its attachment marker from
    // being mistaken for stale startup state.
    for (NSDictionary<NSString *, id> *descriptor in
         self.mountedExternalVolumeDescriptorsByPath.allValues ?: @[]) {
        NSString *diskID = descriptor[@"diskID"];
        if (!diskID.length) continue;
        if (!groups[diskID]) groups[diskID] = [NSMutableArray array];
        [groups[diskID] addObject:descriptor];
    }

    for (NSString *diskID in groups) {
        NSArray<NSDictionary<NSString *, id> *> *diskDescriptors =
            [self mountedExternalDescriptorsForDiskID:diskID];
        NSMutableArray<NSString *> *attachmentVolumeUUIDs =
            [NSMutableArray array];
        BOOL knownDisk = NO;
        for (NSDictionary<NSString *, id> *descriptor in diskDescriptors) {
            NSString *volumeUUID = [descriptor[@"volumeUUID"] uppercaseString];
            if (volumeUUID.length) {
                [attachmentVolumeUUIDs addObject:volumeUUID];
            }
            if ([knownUUIDs containsObject:volumeUUID]) {
                knownDisk = YES;
            }
        }
        NSString *deliveredUUID =
            [deliveredVolumeUUIDsByDiskID[diskID] uppercaseString];
        if (knownDisk) {
            [self.knownExternalDiskIDs addObject:diskID];
            [self forgetUnknownExternalAttachmentForDiskID:diskID];
            [self.unknownExternalVolumeTimersByDiskID[diskID] invalidate];
            [self.unknownExternalVolumeTimersByDiskID removeObjectForKey:diskID];
            [self.unknownExternalVolumeRetryTimersByDiskID[diskID] invalidate];
            [self.unknownExternalVolumeRetryTimersByDiskID
                removeObjectForKey:diskID];
            NSMutableSet<NSString *> *noticeUUIDs = [NSMutableSet set];
            NSString *notifiedUUID =
                self.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID];
            NSString *pendingUUID =
                self.pendingUnknownExternalVolumeUUIDsByDiskID[diskID];
            if (deliveredUUID.length) [noticeUUIDs addObject:deliveredUUID];
            if (notifiedUUID.length) [noticeUUIDs addObject:notifiedUUID];
            if (pendingUUID.length) [noticeUUIDs addObject:pendingUUID];
            for (NSString *noticeUUID in noticeUUIDs) {
                [self removeUnknownExternalVolumeNotificationForDiskID:diskID
                                                             volumeUUID:noticeUUID];
            }
            [self.pendingUnknownExternalDiskIDs removeObject:diskID];
            [self.pendingUnknownExternalVolumeUUIDsByDiskID
                removeObjectForKey:diskID];
            [self.notifiedUnknownExternalDiskIDs removeObject:diskID];
            [self.notifiedUnknownExternalVolumeUUIDsByDiskID
                removeObjectForKey:diskID];
            [self.unknownExternalVolumeDeliveryAttemptsByDiskID
                removeObjectForKey:diskID];
            continue;
        }
        NSDictionary *deliveredDescriptor = deliveredUUID.length
            ? [self mountedExternalDescriptorForDiskID:diskID
                                            volumeUUID:deliveredUUID]
            : nil;
        NSSet<NSString *> *rememberedVolumeUUIDs =
            [self rememberedUnknownExternalVolumeUUIDsForDiskID:diskID];
        NSString *rememberedMountedUUID = @"";
        for (NSString *volumeUUID in attachmentVolumeUUIDs) {
            if ([rememberedVolumeUUIDs containsObject:volumeUUID]) {
                rememberedMountedUUID = volumeUUID;
                break;
            }
        }
        if (deliveredDescriptor) {
            [self.notifiedUnknownExternalDiskIDs addObject:diskID];
            self.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID] =
                deliveredUUID;
            [self rememberUnknownExternalAttachmentForDiskID:diskID
                                                 volumeUUIDs:
                attachmentVolumeUUIDs];
        } else if (rememberedMountedUUID.length) {
            // A person may already have dismissed or ignored the banner. The
            // marker prevents a controller restart from presenting it again
            // while the same physical attachment remains connected.
            [self.notifiedUnknownExternalDiskIDs addObject:diskID];
            self.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID] =
                deliveredUUID.length ? deliveredUUID : rememberedMountedUUID;
        } else {
            if (deliveredUUID.length) {
                [self removeUnknownExternalVolumeNotificationForDiskID:diskID
                                                             volumeUUID:deliveredUUID];
            }
            [self processMountedVolumeDescriptor:diskDescriptors.firstObject];
        }
    }

    for (NSString *diskID in deliveredVolumeUUIDsByDiskID) {
        if (!groups[diskID]) {
            [self removeUnknownExternalVolumeNotificationForDiskID:diskID
                volumeUUID:deliveredVolumeUUIDsByDiskID[diskID]];
            [self forgetUnknownExternalAttachmentForDiskID:diskID];
        }
    }
    [self forgetUnknownExternalAttachmentsExceptDiskIDs:
        [NSSet setWithArray:groups.allKeys]];
}

- (void)primeMountedExternalVolumeCache {
    if (!self.mountedExternalVolumeDescriptorsByPath) {
        self.mountedExternalVolumeDescriptorsByPath =
            [NSMutableDictionary dictionary];
    }
    if (!self.mountedExternalVolumeInspectionTokensByPath) {
        self.mountedExternalVolumeInspectionTokensByPath =
            [NSMutableDictionary dictionary];
    }
    if (!self.knownExternalDiskIDs) {
        self.knownExternalDiskIDs = [NSMutableSet set];
    }
    if (!self.notifiedUnknownExternalDiskIDs) {
        self.notifiedUnknownExternalDiskIDs = [NSMutableSet set];
    }
    if (!self.notifiedUnknownExternalVolumeUUIDsByDiskID) {
        self.notifiedUnknownExternalVolumeUUIDsByDiskID =
            [NSMutableDictionary dictionary];
    }
    __weak typeof(self) weakSelf = self;
    [self deliveredUnknownExternalVolumeUUIDsByDiskIDWithCompletion:
        ^(NSDictionary<NSString *, NSString *> *delivered) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSArray<NSString *> *paths =
            [strongSelf mountedVolumePathsForUnknownExternalVolumeRevalidation];
        if (!paths.count) {
            [strongSelf reconcilePrimedExternalVolumeDescriptors:@[]
                                   deliveredVolumeUUIDsByDiskID:delivered];
            return;
        }
        __block NSUInteger remaining = paths.count;
        NSMutableArray<NSDictionary<NSString *, id> *> *descriptors =
            [NSMutableArray array];
        for (NSString *path in paths) {
            NSString *inspectionToken = NSUUID.UUID.UUIDString;
            strongSelf.mountedExternalVolumeInspectionTokensByPath[path] =
                inspectionToken;
            [strongSelf inspectMountedVolumeAtPath:path
                                       completion:
                ^(NSDictionary<NSString *, id> *descriptor) {
                typeof(self) innerSelf = weakSelf;
                if (innerSelf &&
                    [innerSelf.mountedExternalVolumeInspectionTokensByPath[path]
                        isEqualToString:inspectionToken]) {
                    [innerSelf.mountedExternalVolumeInspectionTokensByPath
                        removeObjectForKey:path];
                    if ([innerSelf
                            isUnknownExternalVolumeDescriptorEligible:descriptor]) {
                        innerSelf.mountedExternalVolumeDescriptorsByPath[path] =
                            descriptor;
                        [descriptors addObject:descriptor];
                    }
                }
                remaining--;
                if (innerSelf && remaining == 0) {
                    NSMutableArray<NSDictionary<NSString *, id> *> *
                        liveDescriptors = [NSMutableArray array];
                    for (NSDictionary<NSString *, id> *candidate in descriptors) {
                        NSDictionary<NSString *, id> *current =
                            innerSelf.mountedExternalVolumeDescriptorsByPath[
                                candidate[@"path"]];
                        BOOL sameVolume =
                            [current[@"diskID"] isEqualToString:
                                candidate[@"diskID"]] &&
                            [[current[@"volumeUUID"] uppercaseString]
                                isEqualToString:
                                    [candidate[@"volumeUUID"] uppercaseString]];
                        if (sameVolume) {
                            [liveDescriptors addObject:current];
                        }
                    }
                    [innerSelf reconcilePrimedExternalVolumeDescriptors:liveDescriptors
                                           deliveredVolumeUUIDsByDiskID:delivered];
                }
            }];
        }
    }];
}

- (void)revalidateUnknownExternalVolumePaths:(NSArray<NSString *> *)paths
                                     atIndex:(NSUInteger)index
                              matchingDiskID:(NSString *)diskID
                                 volumeUUIDs:(NSSet<NSString *> *)volumeUUIDs
                          offeredVolumeUUID:(NSString *)offeredVolumeUUID
                           validDescriptors:
    (NSMutableArray<NSDictionary<NSString *, id> *> *)validDescriptors
                                  completion:
    (void (^)(NSArray<NSDictionary<NSString *, id> *> *descriptors))completion {
    if (index >= paths.count) {
        [validDescriptors sortUsingComparator:
            ^NSComparisonResult(NSDictionary<NSString *, id> *left,
                                NSDictionary<NSString *, id> *right) {
            NSString *leftName = GDTSafeDestinationLabelComponent(left[@"name"]);
            NSString *rightName = GDTSafeDestinationLabelComponent(right[@"name"]);
            NSComparisonResult nameOrder = [leftName compare:rightName
                                                       options:NSCaseInsensitiveSearch];
            if (nameOrder != NSOrderedSame) return nameOrder;
            return [left[@"path"] compare:right[@"path"]
                                   options:NSCaseInsensitiveSearch];
        }];
        BOOL offeredVolumeStillAvailable = NO;
        for (NSDictionary<NSString *, id> *descriptor in validDescriptors) {
            if ([[descriptor[@"volumeUUID"] uppercaseString]
                    isEqualToString:offeredVolumeUUID]) {
                offeredVolumeStillAvailable = YES;
                break;
            }
        }
        // The notification is a capability for one observed attachment. If the
        // offered volume vanished, a sibling must never inherit that click.
        completion(offeredVolumeStillAvailable ? validDescriptors.copy : @[]);
        return;
    }
    NSString *path = paths[index];
    __weak typeof(self) weakSelf = self;
    [self inspectMountedVolumeAtPath:path
                         completion:^(NSDictionary<NSString *, id> *current) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil);
            return;
        }
        BOOL matches =
            [strongSelf isWritableExternalAPFSDescriptor:current] &&
            [current[@"diskID"] isEqualToString:diskID] &&
            [volumeUUIDs containsObject:
                [current[@"volumeUUID"] uppercaseString]];
        if (matches) {
            [validDescriptors addObject:current];
        }
        [strongSelf revalidateUnknownExternalVolumePaths:paths
                                                 atIndex:index + 1
                                          matchingDiskID:diskID
                                             volumeUUIDs:volumeUUIDs
                                     offeredVolumeUUID:offeredVolumeUUID
                                        validDescriptors:validDescriptors
                                              completion:completion];
    }];
}

- (void)revalidateSelectedUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor
                                               completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    NSString *expectedPath = [descriptor[@"path"] isKindOfClass:NSString.class]
        ? [descriptor[@"path"] stringByStandardizingPath] : @"";
    NSString *expectedDiskID = [descriptor[@"diskID"] isKindOfClass:NSString.class]
        ? descriptor[@"diskID"] : @"";
    NSString *expectedVolumeUUID =
        [descriptor[@"volumeUUID"] isKindOfClass:NSString.class]
            ? [descriptor[@"volumeUUID"] uppercaseString] : @"";
    BOOL safeIdentity = expectedPath.length && expectedDiskID.length &&
        expectedVolumeUUID.length && [expectedPath hasPrefix:@"/Volumes/"] &&
        expectedPath.pathComponents.count == 3;
    if (!safeIdentity) {
        completion(nil);
        return;
    }

    [self inspectMountedVolumeAtPath:expectedPath
                         completion:^(NSDictionary<NSString *, id> *current) {
        NSString *currentPath = [current[@"path"] isKindOfClass:NSString.class]
            ? [current[@"path"] stringByStandardizingPath] : @"";
        BOOL exactIdentity = [self isWritableExternalAPFSDescriptor:current] &&
            [currentPath isEqualToString:expectedPath] &&
            [current[@"diskID"] isEqualToString:expectedDiskID] &&
            [[current[@"volumeUUID"] uppercaseString]
                isEqualToString:expectedVolumeUUID];
        completion(exactIdentity ? current : nil);
    }];
}

- (NSArray<NSString *> *)unknownExternalVolumeChoiceLabelsForDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *descriptor in descriptors) {
        NSString *name = GDTSafeDestinationLabelComponent(descriptor[@"name"]);
        NSString *path = [descriptor[@"path"] isKindOfClass:NSString.class]
            ? [descriptor[@"path"] stringByStandardizingPath] : @"";
        NSString *mountLabel = GDTSafeDestinationLabelComponent(path.lastPathComponent);
        if (!name.length) name = T(self.language ?: @"en", @"externalVolume");
        if (!mountLabel.length) mountLabel = name;
        [labels addObject:[NSString stringWithFormat:
            T(self.language ?: @"en", @"unknownExternalVolumeChoiceLabelFormat"),
            name, mountLabel]];
    }
    return labels;
}

- (void)chooseUnknownExternalVolumeFromDescriptors:
    (NSArray<NSDictionary<NSString *, id> *> *)descriptors
                                         completion:
    (void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    if (descriptors.count < 2) {
        completion(nil);
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(self.language ?: @"en", @"unknownExternalVolumeChooseTitle");
    alert.informativeText = T(self.language ?: @"en", @"unknownExternalVolumeChooseBody");
    NSPopUpButton *popup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(0, 0, 420, 28) pullsDown:NO];
    NSArray<NSString *> *labels =
        [self unknownExternalVolumeChoiceLabelsForDescriptors:descriptors];
    [popup addItemWithTitle:
        T(self.language ?: @"en", @"unknownExternalVolumeChoosePlaceholder")];
    popup.lastItem.representedObject = nil;
    for (NSUInteger index = 0; index < descriptors.count; index++) {
        [popup addItemWithTitle:labels[index]];
        popup.lastItem.representedObject = descriptors[index];
    }
    [popup selectItemAtIndex:0];
    alert.accessoryView = popup;
    [alert addButtonWithTitle:
        T(self.language ?: @"en", @"unknownExternalVolumeChooseAction")];
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancel")];
    NSButton *confirmationButton = alert.buttons.firstObject;
    confirmationButton.enabled = NO;
    GDTExplicitPopUpChoiceController *choiceController =
        [[GDTExplicitPopUpChoiceController alloc] init];
    choiceController.popup = popup;
    choiceController.confirmationButton = confirmationButton;
    popup.target = choiceController;
    popup.action = @selector(choiceDidChange:);
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] != NSAlertFirstButtonReturn ||
        !choiceController.hasExplicitSelection ||
        !confirmationButton.enabled) {
        completion(nil);
        return;
    }
    NSDictionary<NSString *, id> *selected =
        [popup.selectedItem.representedObject isKindOfClass:NSDictionary.class]
            ? popup.selectedItem.representedObject : nil;
    completion(selected);
}

- (void)presentSetupForUnknownExternalVolumeDescriptor:
    (NSDictionary<NSString *, id> *)descriptor {
    [self showSetupWindow];
    NSString *path = [descriptor[@"path"] isKindOfClass:NSString.class]
        ? [descriptor[@"path"] stringByStandardizingPath] : @"";
    NSString *volumeUUID = [descriptor[@"volumeUUID"] isKindOfClass:NSString.class]
        ? [descriptor[@"volumeUUID"] uppercaseString] : @"";
    NSString *name = GDTSafeDestinationLabelComponent(descriptor[@"name"]);
    BOOL supported = [self isWritableExternalAPFSDescriptor:descriptor] &&
        volumeUUID.length;
    if (!supported) {
        self.setupContextStatusText =
            T(self.language ?: @"en", @"unknownExternalVolumeUnsupported");
        self.statusField.stringValue = self.setupContextStatusText;
        return;
    }

    self.configuredAPFSVolumePath = path;
    self.configuredAPFSVolumeUUID = volumeUUID;
    [self updateDestinationPreview];
    [self invalidateSetupHealth:nil];
    self.setupContextStatusText = [NSString stringWithFormat:
        T(self.language ?: @"en", @"unknownExternalVolumeReviewSetup"),
        name.length ? name : path.lastPathComponent];
    self.statusField.stringValue = self.setupContextStatusText;
}

- (void)presentUnknownExternalVolumeUnavailable {
    [self showSetupWindow];
    self.setupContextStatusText =
        T(self.language ?: @"en", @"unknownExternalVolumeUnavailable");
    self.statusField.stringValue = self.setupContextStatusText;
}

- (void)handleUnknownExternalVolumeActionIdentifier:(NSString *)actionIdentifier
                                           userInfo:(NSDictionary *)userInfo {
    if ([actionIdentifier isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE"]) {
        return;
    }
    if (![actionIdentifier isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME_SETUP"] &&
        ![actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^processAction)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        [strongSelf revalidateUnknownExternalVolumeCandidatesForUserInfo:userInfo
                                                              completion:
            ^(NSArray<NSDictionary<NSString *, id> *> *descriptors) {
            if (!descriptors.count) {
                [strongSelf presentUnknownExternalVolumeUnavailable];
                return;
            }
            if (descriptors.count == 1) {
                [strongSelf presentSetupForUnknownExternalVolumeDescriptor:
                    descriptors[0]];
                return;
            }
            [strongSelf chooseUnknownExternalVolumeFromDescriptors:descriptors
                                                        completion:
                ^(NSDictionary<NSString *, id> *selectedDescriptor) {
                if (!selectedDescriptor) return;
                [strongSelf
                    revalidateSelectedUnknownExternalVolumeDescriptor:
                        selectedDescriptor
                    completion:^(NSDictionary<NSString *, id> *currentDescriptor) {
                    if (!currentDescriptor) {
                        [strongSelf presentUnknownExternalVolumeUnavailable];
                        return;
                    }
                    [strongSelf presentSetupForUnknownExternalVolumeDescriptor:
                        currentDescriptor];
                }];
            }];
        }];
    };
    if (NSThread.isMainThread) {
        processAction();
    } else {
        dispatch_async(dispatch_get_main_queue(), processAction);
    }
}

- (void)handleBackupNotificationActionIdentifier:(NSString *)actionIdentifier
                              categoryIdentifier:(NSString *)categoryIdentifier
                                        userInfo:(NSDictionary *)userInfo
                          notificationIdentifier:(NSString *)notificationIdentifier {
    BOOL dismissAction =
        [actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier];
    BOOL openAction = [actionIdentifier isEqualToString:@"GDT_OPEN_BACKUP_OVERVIEW"];
    if (![categoryIdentifier isEqualToString:@"GDT_BACKUP_ALERT"] ||
        (!dismissAction && !openAction)) {
        return;
    }

    if (openAction) {
        void (^showOverview)(void) = ^{
            self.updateConsentRequested = NO;
            [self showOverviewWindow];
            [self refreshOverviewStatus:nil];
        };
        if (NSThread.isMainThread) {
            showOverview();
        } else {
            dispatch_async(dispatch_get_main_queue(), showOverview);
        }
    }

    NSString *profileID = [userInfo[@"profileID"] isKindOfClass:NSString.class]
        ? userInfo[@"profileID"] : @"";
    NSString *originValue =
        [userInfo[@"issueOriginTimestamp"] isKindOfClass:NSString.class]
            ? userInfo[@"issueOriginTimestamp"] : @"";
    NSTimeInterval issueOriginTimestamp =
        GDTBackupNotificationTimestamp(originValue);
    NSString *profilePrefix = [NSString stringWithFormat:
        @"com.commcats.gdrivebackup.%@.", profileID];
    NSArray<NSString *> *safeIdentifiers =
        [GDTBackupNotificationPolicy
            failureNotificationIdentifiersForProfileID:profileID
                                  candidateIdentifiers:@[notificationIdentifier ?: @""]];
    if (!profileID.length || issueOriginTimestamp <= 0 ||
        ![originValue isEqualToString:
            [NSString stringWithFormat:@"%.0f", issueOriginTimestamp]] ||
        ![notificationIdentifier hasPrefix:profilePrefix] ||
        safeIdentifiers.count != 1) {
        return;
    }

    NSUserDefaults *defaults = [self backupNotificationDefaultsStore];
    NSString *dismissedKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"dismissedIssueAt"];
    [defaults setDouble:MAX(issueOriginTimestamp,
                            [defaults doubleForKey:dismissedKey])
                 forKey:dismissedKey];

    NSString *activeAtKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                     suffix:@"activeIssueAt"];
    NSString *activeIDKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                     suffix:@"activeIssueIdentifier"];
    if ([defaults doubleForKey:activeAtKey] == issueOriginTimestamp &&
        [[defaults stringForKey:activeIDKey]
            isEqualToString:notificationIdentifier]) {
        [defaults removeObjectForKey:activeAtKey];
        [defaults removeObjectForKey:activeIDKey];
        [defaults removeObjectForKey:[self
            backupNotificationDefaultsKeyForProfileID:profileID
                                               suffix:@"activeIssueKind"]];
    }

    NSString *deliveredKey = [self backupNotificationDefaultsKeyForProfileID:profileID
                                                                       suffix:@"deliveredFailureIdentifiers"];
    NSMutableArray<NSString *> *delivered =
        [[defaults stringArrayForKey:deliveredKey] mutableCopy] ?:
            [NSMutableArray array];
    [delivered removeObject:notificationIdentifier];
    if (delivered.count) {
        [defaults setObject:delivered forKey:deliveredKey];
    } else {
        [defaults removeObjectForKey:deliveredKey];
    }
    NSString *lastIdentifierKey = [self
        backupNotificationDefaultsKeyForProfileID:profileID
                                           suffix:@"lastDeliveredIdentifier"];
    if ([[defaults stringForKey:lastIdentifierKey]
            isEqualToString:notificationIdentifier]) {
        [defaults removeObjectForKey:lastIdentifierKey];
        [defaults removeObjectForKey:[self
            backupNotificationDefaultsKeyForProfileID:profileID
                                               suffix:@"lastDeliveredRevision"]];
    }
    [self removeExactBackupNotificationIdentifiers:safeIdentifiers
                                       forProfileID:profileID];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self userNotificationCenter:center didReceiveNotificationResponse:response
                withCompletionHandler:completionHandler];
        });
        return;
    }
    // Notification activation must never consume an earlier deferred overview
    // consent intent, even when another category opens a window or setup panel.
    self.updateConsentRequested = NO;
    NSString *action = response.actionIdentifier;
    NSString *category = response.notification.request.content.categoryIdentifier;
    if ([category isEqualToString:@"GDT_UPDATE_AVAILABLE"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleUpdateNotificationAction:action
                userInfo:response.notification.request.content.userInfo ?: @{}
                identifier:response.notification.request.identifier ?: @""];
            completionHandler();
        });
        return;
    }
    if ([category isEqualToString:@"GDT_UNKNOWN_EXTERNAL_VOLUME"]) {
        NSString *identifier = response.notification.request.identifier;
        if (identifier.length) {
            [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
            [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
        }
        [self handleUnknownExternalVolumeActionIdentifier:action
                                                 userInfo:
            response.notification.request.content.userInfo ?: @{}];
        completionHandler();
        return;
    }
    if ([action isEqualToString:UNNotificationDismissActionIdentifier] ||
        [action isEqualToString:@"GDT_OPEN_BACKUP_OVERVIEW"]) {
        [self handleBackupNotificationActionIdentifier:action
                                    categoryIdentifier:category
                                              userInfo:
            response.notification.request.content.userInfo ?: @{}
                                notificationIdentifier:
            response.notification.request.identifier ?: @""];
        if ([action isEqualToString:UNNotificationDismissActionIdentifier] ||
            [category isEqualToString:@"GDT_BACKUP_ALERT"]) {
            completionHandler();
            return;
        }
    }
    if ([action isEqualToString:UNNotificationDefaultActionIdentifier] ||
        [action isEqualToString:@"GDT_OPEN_BACKUP_OVERVIEW"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.updateConsentRequested = NO;
            [self showOverviewWindow];
            [self refreshOverviewStatus:nil];
        });
    }
    completionHandler();
}

- (void)prepareProfileStore {
    if (NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_CONFIG"].length) {
        return;
    }
    NSString *root = NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_CONFIG_DIR"];
    if (!root.length) {
        root = [NSHomeDirectory() stringByAppendingPathComponent:@".config/gdrive-tiger-backup"];
    }
    GDTProfileStore *store = [[GDTProfileStore alloc] initWithConfigDirectory:root];
    NSError *error = nil;
    if ([store migrateLegacyConfigAtPath:[root stringByAppendingPathComponent:@"config"]
                                   error:&error]) {
        self.profileStore = store;
    }
}

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

- (BOOL)shouldForegroundProgressForArguments:(NSArray<NSString *> *)arguments {
    return [arguments containsObject:@"--foreground"];
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
    NSDictionary<NSString *, NSString *> *summary = GDTReadBackupSummaryAtPath(summaryPath);
    NSString *status = GDTBackupSummaryStatusForValues(summary);
    return [self overviewSnapshotForConfig:config
                                   summary:summary
                                    status:status
                                  progress:nil
                                       now:now
                                  calendar:calendar];
}

- (NSDictionary<NSString *, NSString *> *)overviewSnapshotForConfig:(NSDictionary<NSString *, NSString *> *)config
                                                              summary:(NSDictionary<NSString *, NSString *> *)summary
                                                               status:(NSString *)status
                                                                  now:(NSDate *)now
                                                             calendar:(NSCalendar *)calendar {
    return [self overviewSnapshotForConfig:config
                                   summary:summary
                                    status:status
                                  progress:nil
                                       now:now
                                  calendar:calendar];
}

- (NSDictionary<NSString *, NSString *> *)overviewSnapshotForConfig:(NSDictionary<NSString *, NSString *> *)config
                                                              summary:(NSDictionary<NSString *, NSString *> *)summary
                                                               status:(NSString *)status
                                                             progress:(NSDictionary<NSString *, NSString *> *)progress
                                                                  now:(NSDate *)now
                                                             calendar:(NSCalendar *)calendar {
    NSString *language = self.language ?: @"en";
    NSString *trigger = summary[@"trigger"] ?: @"";
    BOOL retryRunning = [status isEqualToString:@"running"] &&
        [trigger isEqualToString:@"schedule-retry"];
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
    if (retryRunning) {
        lastRun = T(language, @"automaticRetryRunning");
    }

    NSString *timestamp = [status isEqualToString:@"running"] || [status isEqualToString:@"interrupted"]
        ? summary[@"started_at"] : summary[@"finished_at"];
    NSString *lastRunDetail = @"";
    if (timestamp.longLongValue > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.longLongValue];
        lastRunDetail = [[self overviewDateFormatterWithCalendar:calendar] stringFromDate:date] ?: @"";
    }

    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticBackupsPaused = [config[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"];
    NSString *nextRun = nil;
    if (automaticBackupsPaused) {
        nextRun = T(language, @"automaticBackupsPaused");
    } else if ([schedule isEqualToString:@"daily"]) {
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

    NSString *target = GDTBackupTargetOverviewText(config, language);

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
        @"trigger": trigger,
        @"retryRunning": retryRunning ? @"1" : @"0",
        @"progressVisible": retryRunning ? @"1" : @"0",
        @"progressLabel": retryRunning ? T(language, @"automaticRetryRunning") : @"",
        @"progressPhase": retryRunning
            ? GDTLocalizedProgressPhase(progress[@"phase"], language) : @"",
        @"progressPercent": retryRunning ? (progress[@"percent"] ?: @"") : @"",
        @"progressDetail": retryRunning
            ? GDTLocalizedProgressDetail(progress, language) : @"",
        @"lastRun": lastRun ?: @"",
        @"lastRunDetail": lastRunDetail,
        @"nextRun": nextRun ?: T(language, @"overviewUnavailable"),
        @"automaticBackupsPaused": automaticBackupsPaused ? @"1" : @"0",
        @"target": target,
        @"storage": storage
    };
}

- (void)applyOverviewSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                       toView:(TigerOverviewView *)view {
    NSString *status = snapshot[@"status"] ?: @"unknown";
    if (![status isEqualToString:@"running"] && !self.adHocRunChoice) {
        self.overviewLaunchPending = NO;
    }
    view.language = self.language ?: @"en";
    view.lastRunText = snapshot[@"lastRun"] ?: @"";
    view.lastRunDetail = snapshot[@"lastRunDetail"] ?: @"";
    view.nextRunText = snapshot[@"nextRun"] ?: @"";
    view.targetText = snapshot[@"target"] ?: @"";
    view.storageText = snapshot[@"storage"] ?: @"";
    view.status = status;
    view.progressSummary = snapshot[@"progressLabel"] ?: @"";
    view.progressPhaseLabel.stringValue = snapshot[@"progressPhase"] ?: @"";
    view.progressPhaseLabel.accessibilityLabel = view.progressPhaseLabel.stringValue;
    view.progressDetail = snapshot[@"progressDetail"] ?: @"";
    NSString *progressPercent = snapshot[@"progressPercent"] ?: @"";
    view.progressPercent = progressPercent.length ? progressPercent.doubleValue : -1.0;
    view.progressVisible = [snapshot[@"progressVisible"] isEqualToString:@"1"];
    view.backupButton.enabled = !self.overviewLaunchPending && ![status isEqualToString:@"running"];
    [self refreshAdHocPicker];
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
    if ([snapshot[@"retryRunning"] isEqualToString:@"1"]) {
        NSMutableArray<NSString *> *progressParts = [NSMutableArray arrayWithObject:
            T(language, @"automaticRetryRunningShort")];
        if ([snapshot[@"progressPhase"] length]) {
            [progressParts addObject:snapshot[@"progressPhase"]];
        }
        NSString *progressPercent = snapshot[@"progressPercent"] ?: @"";
        NSString *progressDetail = snapshot[@"progressDetail"] ?: @"";
        if (progressPercent.length) {
            [progressParts addObject:[NSString stringWithFormat:@"%@ %%",
                progressPercent]];
        } else if (progressDetail.length) {
            [progressParts addObject:progressDetail];
        }
        NSMenuItem *retryProgressItem = [[NSMenuItem alloc]
            initWithTitle:[progressParts componentsJoinedByString:@" · "]
                   action:nil
            keyEquivalent:@""];
        retryProgressItem.enabled = NO;
        [menu addItem:retryProgressItem];
    }
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
    BOOL automaticBackupsPaused = [snapshot[@"automaticBackupsPaused"] isEqualToString:@"1"];
    NSMenuItem *pause = [[NSMenuItem alloc]
        initWithTitle:T(language, automaticBackupsPaused
            ? @"resumeAutomaticBackups" : @"pauseAutomaticBackups")
                 action:@selector(toggleAutomaticBackupsPaused:)
          keyEquivalent:@""];
    pause.target = self;
    [menu addItem:pause];
    NSMenuItem *restore = [[NSMenuItem alloc] initWithTitle:T(language, @"restoreTitle")
                                                      action:@selector(showRestoreBrowser:)
                                               keyEquivalent:@""];
    restore.target = self;
    [menu addItem:restore];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:T(language, @"overviewSettings")
                                                       action:@selector(showBackupSetup:)
                                                keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];
    NSMenuItem *diagnostics = [[NSMenuItem alloc] initWithTitle:T(language, @"diagnosticsTitle")
                                                          action:@selector(showDiagnostics:)
                                                   keyEquivalent:@""];
    diagnostics.target = self;
    [menu addItem:diagnostics];
    NSMenuItem *update = [[NSMenuItem alloc]
        initWithTitle:T(language, self.updateChecking ? @"updateChecking" : @"updateCheck")
                 action:@selector(checkForUpdates:)
          keyEquivalent:@""];
    update.target = self;
    update.enabled = !self.updateChecking;
    [menu addItem:update];
    [self appendAutomaticUpdateItemsToMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:T(language, @"quitMenu") action:@selector(terminate:) keyEquivalent:@"q"];
    return menu;
}

- (void)toggleAutomaticBackupsPaused:(id)sender {
    (void)sender;
    NSDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    BOOL paused = [config[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"];
    NSError *error = nil;
    if (!GDTWriteConfigUpdates(@{@"GDRIVE_BACKUP_PAUSED": paused ? @"0" : @"1"}, &error)) {
        [NSApp presentError:error ?: [NSError errorWithDomain:@"com.commcats.gdrivebackup"
                                                         code:1 userInfo:nil]];
        return;
    }
    [self refreshOverviewStatus:nil];
}

- (void)updateStatusItemPresentationForSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot {
    NSDictionary<NSString *, NSString *> *symbols = @{
        @"success": @"externaldrive.fill.badge.checkmark",
        @"failure": @"exclamationmark.triangle.fill",
        @"missed": @"exclamationmark.triangle.fill",
        @"cancelled": @"stop.circle.fill",
        @"running": @"arrow.triangle.2.circlepath",
        @"retry-running": @"arrow.triangle.2.circlepath",
        @"interrupted": @"exclamationmark.circle.fill",
        @"unknown": @"externaldrive.fill"
    };
    NSString *status = snapshot[@"alertStatus"] ?: snapshot[@"status"] ?: @"unknown";
    NSString *symbolName = symbols[status] ?: symbols[@"unknown"];
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                               accessibilityDescription:@"GDrive Backup Tiger"];
    BOOL warning = [@[@"failure", @"missed", @"interrupted"] containsObject:status];
    if (warning) {
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.systemRedColor]];
    }
    image.template = !warning;
    self.statusItem.button.image = image;
    NSString *spokenStatus = [status isEqualToString:@"missed"]
        ? T(self.language ?: @"en", @"backupNotificationMissedTitle")
        : ([status isEqualToString:@"failure"]
            ? T(self.language ?: @"en", @"failed")
            : ([status isEqualToString:@"retry-running"]
                ? T(self.language ?: @"en", @"automaticRetryRunning")
                : snapshot[@"lastRun"]));
    self.statusItem.button.accessibilityLabel = [NSString stringWithFormat:@"GDrive Backup Tiger — %@",
        spokenStatus ?: T(self.language ?: @"en", @"overviewStatusUnknown")];
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
    [self automaticUpdateTick];
    if (self.overviewRefreshInFlight) return;
    self.overviewRefreshInFlight = YES;
    NSUInteger updateConsentGeneration = self.updateConsentGeneration;
    NSDictionary<NSString *, NSString *> *baseConfig = GDTReadConfigDictionary();
    NSString *summaryPath = GDTBackupSummaryPathForConfig(baseConfig);
    NSCalendar *calendar = NSCalendar.autoupdatingCurrentCalendar;
    NSDate *now = [NSDate date];
    NSDictionary<NSString *, NSString *> *config =
        [self notificationMonitoringConfigForConfig:baseConfig now:now];
    NSString *notificationProfileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
    NSTimeInterval activeIssueTimestamp = [[self backupNotificationDefaultsStore]
        doubleForKey:[self backupNotificationDefaultsKeyForProfileID:notificationProfileID
                                                               suffix:@"activeIssueAt"]];
    NSDictionary *manualChoice = self.adHocRunChoice;
    NSString *manualSummaryPath = self.adHocSummaryPath;
    BOOL manualPending = self.overviewLaunchPending;
    NSTimeInterval manualStartedAt = self.adHocRunStartedAt;
    NSUInteger manualGeneration = self.adHocGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSDictionary<NSString *, NSString *> *summary = GDTReadBackupSummaryAtPath(summaryPath);
        NSString *status = GDTBackupSummaryStatusForValues(summary);
        NSString *progressPath = GDTBackupProgressPathForSummaryPath(summaryPath);
        NSDictionary<NSString *, NSString *> *rawProgress =
            GDTReadBackupProgressAtPath(progressPath);
        NSString *profileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
        NSDictionary<NSString *, NSString *> *progress = rawProgress
            ? GDTValidatedBackupProgressForValues(rawProgress, summary, status,
                profileID, now.timeIntervalSince1970)
            : nil;
        NSDictionary<NSString *, NSString *> *snapshot =
            [strongSelf overviewSnapshotForConfig:config summary:summary status:status
                                          progress:progress now:now calendar:calendar];
        NSDictionary<NSString *, NSString *> *notificationDecision =
            [GDTBackupNotificationPolicy decisionForConfig:config summary:summary
                                                    status:status now:now calendar:calendar];
        NSDictionary<NSString *, NSString *> *successDecision =
            [GDTBackupNotificationPolicy successDecisionForConfig:config summary:summary
                                                           status:status
                                             activeIssueTimestamp:activeIssueTimestamp
                                                              now:now];
        NSDictionary<NSString *, NSString *> *retryDecision =
            [GDTAutomaticRetryPolicy decisionForConfig:config summary:summary
                                                status:status now:now];
        NSDictionary *manualSnapshot = nil;
        if (manualChoice && GDTShouldDisplayManualRun(manualStartedAt, summary, status, manualPending)) {
            NSDictionary *manualSummary = GDTReadBackupSummaryAtPath(manualSummaryPath);
            if ([manualSummary[@"started_at"] doubleValue] < manualStartedAt) manualSummary = @{};
            NSString *manualStatus = GDTBackupSummaryStatusForValues(manualSummary);
            if (!manualPending && !manualSummary.count) manualStatus = @"failure";
            if (manualPending && ![manualStatus isEqual:@"running"]) {
                manualStatus = @"running";
                manualSummary = @{@"trigger": @"manual"};
            }
            NSDictionary *manualConfig = manualChoice[@"config"];
            NSDictionary *manualProgress = GDTValidatedBackupProgressForValues(
                GDTReadBackupProgressAtPath(GDTBackupProgressPathForSummaryPath(manualSummaryPath)),
                manualSummary, manualStatus, manualConfig[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy",
                now.timeIntervalSince1970);
            NSMutableDictionary *display = [[strongSelf overviewSnapshotForConfig:config summary:manualSummary
                status:manualStatus progress:manualProgress now:now calendar:calendar] mutableCopy];
            BOOL running = [manualStatus isEqual:@"running"];
            display[@"progressVisible"] = running ? @"1" : @"0";
            display[@"progressLabel"] = [NSString stringWithFormat:GDTAdHocText(strongSelf.language, @"on"), manualChoice[@"label"]];
            display[@"lastRunDetail"] = [NSString stringWithFormat:@"%@ · %@", display[@"lastRunDetail"] ?: @"", manualChoice[@"label"]];
            display[@"progressPhase"] = GDTLocalizedProgressPhase(manualProgress[@"phase"], strongSelf.language);
            display[@"progressPercent"] = manualProgress[@"percent"] ?: @"";
            display[@"progressDetail"] = GDTLocalizedProgressDetail(manualProgress, strongSelf.language);
            manualSnapshot = display;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            innerSelf.overviewRefreshInFlight = NO;
            if (manualGeneration != innerSelf.adHocGeneration) {
                [innerSelf refreshOverviewStatus:nil];
                return;
            }
            NSDictionary<NSString *, NSString *> *currentConfig = GDTReadConfigDictionary();
            NSString *capturedProfileID = config[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
            NSString *currentProfileID = currentConfig[@"GDRIVE_BACKUP_PROFILE_ID"] ?: @"legacy";
            if (![capturedProfileID isEqualToString:currentProfileID]) {
                // A profile switch can finish while the summary is read off the
                // main thread. Discard that stale snapshot before it can update
                // the menu bar or deliver an alert for the previous profile.
                [innerSelf refreshOverviewStatus:nil];
                return;
            }
            BOOL successDecisionCurrent = successDecision &&
                [innerSelf isBackupSuccessDecisionCurrent:successDecision
                              capturedActiveIssueTimestamp:activeIssueTimestamp];
            NSMutableDictionary<NSString *, NSString *> *displaySnapshot = [snapshot mutableCopy];
            if (manualSnapshot && [innerSelf.adHocSummaryPath isEqual:manualSummaryPath]) {
                displaySnapshot = [manualSnapshot mutableCopy];
            }
            displaySnapshot[@"alertStatus"] = [innerSelf backupAlertStatusForConfig:config
                summary:summary rawStatus:status decision:notificationDecision];
            if (notificationDecision) {
                [innerSelf processBackupNotificationDecision:notificationDecision];
            }
            if (retryDecision) {
                [innerSelf processAutomaticRetryDecision:retryDecision];
            }
            [innerSelf clearBackupFailureNotificationsForConfig:config
                                                        summary:summary
                                                         status:status];
            if (successDecisionCurrent) {
                [innerSelf processBackupSuccessNotificationDecision:successDecision
                                      capturedActiveIssueTimestamp:activeIssueTimestamp];
            }
            [innerSelf acceptOverviewSnapshot:displaySnapshot
                     updateConsentGeneration:updateConsentGeneration];
            if ([innerSelf.window.contentView isKindOfClass:TigerOverviewView.class]) {
                [innerSelf applyOverviewSnapshot:displaySnapshot
                                          toView:(TigerOverviewView *)innerSelf.window.contentView];
            }
            if (innerSelf.statusItem) {
                innerSelf.statusItem.menu = [innerSelf statusMenuForSnapshot:displaySnapshot];
                innerSelf.statusItem.menu.delegate = innerSelf;
                [innerSelf updateStatusItemPresentationForSnapshot:displaySnapshot];
            }
            [innerSelf updateOverviewRefreshTimerForStatus:displaySnapshot[@"status"]];
        });
    });
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self refreshOverviewStatus:nil];
}

- (NSString *)volumeUUIDForPath:(NSString *)path {
    if (!path.length) {
        return @"";
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSString *volumeUUID = nil;
    if (![url getResourceValue:&volumeUUID forKey:NSURLVolumeUUIDStringKey error:nil] ||
        ![volumeUUID isKindOfClass:NSString.class]) {
        return @"";
    }
    return volumeUUID.uppercaseString;
}

- (NSSet<NSString *> *)configuredExternalVolumeUUIDs {
    NSMutableSet<NSString *> *volumeUUIDs = [NSMutableSet set];
    NSString *activeUUID = [[self savedSetupConfig][@"GDRIVE_BACKUP_VOLUME_UUID"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (activeUUID.length) {
        [volumeUUIDs addObject:activeUUID.uppercaseString];
    }
    for (NSDictionary<NSString *, NSString *> *profile in self.profileStore.profiles ?: @[]) {
        NSString *path = profile[@"configPath"];
        NSString *volumeUUID = [GDTReadConfigDictionaryAtPath(path)[@"GDRIVE_BACKUP_VOLUME_UUID"]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (volumeUUID.length) {
            [volumeUUIDs addObject:volumeUUID.uppercaseString];
        }
    }
    return volumeUUIDs;
}

- (NSDictionary<NSString *, id> *)externalVolumeDescriptorFromDiskutilInfo:
    (NSDictionary *)plist requestedPath:(NSString *)requestedPath {
    if (![plist isKindOfClass:NSDictionary.class]) return nil;
    NSString *normalizedRequest = requestedPath.stringByStandardizingPath;
    NSString *mountPoint = [plist[@"MountPoint"] isKindOfClass:NSString.class]
        ? [plist[@"MountPoint"] stringByStandardizingPath] : @"";
    if (!mountPoint.length || ![mountPoint isEqualToString:normalizedRequest]) {
        return nil;
    }

    NSString *filesystem = [plist[@"FilesystemType"] isKindOfClass:NSString.class]
        ? [plist[@"FilesystemType"] lowercaseString] : @"";
    BOOL networkFilesystem = [@[@"smbfs", @"afpfs", @"nfs", @"webdav", @"cifs"]
        containsObject:filesystem];
    NSString *volumeUUID = [plist[@"VolumeUUID"] isKindOfClass:NSString.class]
        ? [plist[@"VolumeUUID"] uppercaseString] : @"";
    NSString *diskID = @"";
    NSArray *physicalStores = [plist[@"APFSPhysicalStores"] isKindOfClass:NSArray.class]
        ? plist[@"APFSPhysicalStores"] : @[];
    NSDictionary *firstPhysicalStore =
        [physicalStores.firstObject isKindOfClass:NSDictionary.class]
            ? physicalStores.firstObject : nil;
    NSString *physicalStoreID =
        [firstPhysicalStore[@"APFSPhysicalStore"] isKindOfClass:NSString.class]
            ? firstPhysicalStore[@"APFSPhysicalStore"] : @"";
    if (physicalStoreID.length) {
        diskID = physicalStoreID;
    } else if ([plist[@"ParentWholeDisk"] isKindOfClass:NSString.class]) {
        diskID = plist[@"ParentWholeDisk"];
    }
    if (!diskID.length && [plist[@"DeviceIdentifier"] isKindOfClass:NSString.class]) {
        diskID = plist[@"DeviceIdentifier"];
    }
    if (diskID.length) {
        NSRegularExpression *expression = [NSRegularExpression
            regularExpressionWithPattern:@"^disk[0-9]+" options:0 error:nil];
        NSTextCheckingResult *match = [expression firstMatchInString:diskID
            options:0 range:NSMakeRange(0, diskID.length)];
        if (match) {
            diskID = [diskID substringWithRange:match.range];
        }
    }
    if (!diskID.length || !volumeUUID.length) return nil;

    NSString *name = [plist[@"VolumeName"] isKindOfClass:NSString.class]
        ? plist[@"VolumeName"] : normalizedRequest.lastPathComponent;
    BOOL isPhysical = ![plist[@"Internal"] boolValue] &&
        [plist[@"RemovableMediaOrExternalDevice"] boolValue] &&
        ![plist[@"SystemImage"] boolValue];
    NSNumber *writableVolume =
        [plist[@"WritableVolume"] isKindOfClass:NSNumber.class]
            ? plist[@"WritableVolume"] : nil;
    NSNumber *writable =
        [plist[@"Writable"] isKindOfClass:NSNumber.class]
            ? plist[@"Writable"] : nil;
    return @{
        @"path": mountPoint,
        @"name": name ?: @"",
        @"volumeUUID": volumeUUID,
        @"diskID": diskID,
        @"isLocal": @(!networkFilesystem),
        @"isInternal": @([plist[@"Internal"] boolValue]),
        @"isPhysical": @(isPhysical),
        @"isSystemImage": @([plist[@"SystemImage"] boolValue]),
        @"isWritable": @(writableVolume ? writableVolume.boolValue
                                        : writable.boolValue),
        @"filesystem": filesystem
        ,@"mediaName": plist[@"GDTPhysicalMediaName"] ?: plist[@"MediaName"] ?: @"",
        @"isBackupVolume": plist[@"GDTAPFSBackupVolume"] ?: @NO,
        @"sizeBytes": plist[@"GDTPhysicalSize"] ?: plist[@"TotalSize"] ?: @0,
        @"connection": plist[@"BusProtocol"] ?: @""
    };
}

- (void)inspectMountedVolumeAtPath:(NSString *)path
                        completion:(void (^)(NSDictionary<NSString *, id> *descriptor))completion {
    NSString *requestedPath = path.stringByStandardizingPath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        NSString *output = RunCommand(@"/usr/sbin/diskutil",
                                      @[@"info", @"-plist", requestedPath], nil, &status);
        NSDictionary *plist = nil;
        if (status == 0 && output.length) {
            NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
            id value = data ? [NSPropertyListSerialization
                propertyListWithData:data options:NSPropertyListImmutable
                              format:nil error:nil] : nil;
            if ([value isKindOfClass:NSDictionary.class]) {
                plist = value;
            }
        }

        NSMutableDictionary *enriched = [plist mutableCopy];
        if ([plist[@"APFSContainerReference"] isKindOfClass:NSString.class]) {
            int roleStatus = 0;
            NSString *roleOutput = RunCommand(@"/usr/sbin/diskutil", @[@"apfs", @"list", @"-plist",
                plist[@"APFSContainerReference"]], nil, &roleStatus);
            NSData *roleData = [roleOutput dataUsingEncoding:NSUTF8StringEncoding];
            id topology = roleStatus == 0 && roleData ? [NSPropertyListSerialization
                propertyListWithData:roleData options:0 format:nil error:nil] : nil;
            BOOL roleKnown = NO;
            if ([topology isKindOfClass:NSDictionary.class]) {
                for (NSDictionary *container in topology[@"Containers"]) {
                    for (NSDictionary *volume in container[@"Volumes"]) {
                        if ([volume[@"DeviceIdentifier"] isEqual:plist[@"DeviceIdentifier"]]) {
                            roleKnown = YES;
                            enriched[@"GDTAPFSBackupVolume"] = @([volume[@"Roles"] containsObject:@"Backup"]);
                        }
                    }
                }
            }
            if (!roleKnown) enriched[@"WritableVolume"] = @NO;
        }
        NSDictionary *descriptor = [self externalVolumeDescriptorFromDiskutilInfo:plist requestedPath:requestedPath];
        if ([descriptor[@"isPhysical"] boolValue] && [descriptor[@"diskID"] length]) {
            int physicalStatus = 0;
            NSString *physicalOutput = RunCommand(@"/usr/sbin/diskutil",
                @[@"info", @"-plist", descriptor[@"diskID"]], nil, &physicalStatus);
            NSData *physicalData = [physicalOutput dataUsingEncoding:NSUTF8StringEncoding];
            id physical = physicalStatus == 0 && physicalData ? [NSPropertyListSerialization
                propertyListWithData:physicalData options:0 format:nil error:nil] : nil;
            if ([physical isKindOfClass:NSDictionary.class]) {
                enriched[@"GDTPhysicalMediaName"] = physical[@"MediaName"] ?: @"";
                enriched[@"GDTPhysicalSize"] = physical[@"TotalSize"] ?: @0;
                enriched[@"BusProtocol"] = physical[@"BusProtocol"] ?: @"";
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([self externalVolumeDescriptorFromDiskutilInfo:enriched
                                                        requestedPath:requestedPath]);
        });
    });
}

- (NSTimeInterval)unknownExternalVolumeNotificationDelay {
    // APFS containers commonly mount several sibling volumes in one burst.
    // Waiting briefly lets the configured backup UUID suppress notices for the
    // whole already-known physical disk.
    return 2.0;
}

- (BOOL)isUnknownExternalVolumeDescriptorEligible:
    (NSDictionary<NSString *, id> *)descriptor {
    return [descriptor[@"isLocal"] boolValue] &&
        ![descriptor[@"isInternal"] boolValue] &&
        [descriptor[@"isPhysical"] boolValue] &&
        ![descriptor[@"isSystemImage"] boolValue] &&
        [descriptor[@"diskID"] isKindOfClass:NSString.class] &&
        [descriptor[@"diskID"] length] &&
        [descriptor[@"volumeUUID"] isKindOfClass:NSString.class] &&
        [descriptor[@"volumeUUID"] length] &&
        [descriptor[@"path"] isKindOfClass:NSString.class] &&
        [descriptor[@"path"] length];
}

- (NSArray<NSDictionary<NSString *, id> *> *)mountedExternalDescriptorsForDiskID:
    (NSString *)diskID {
    NSMutableArray<NSDictionary<NSString *, id> *> *descriptors = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *descriptor in
         self.mountedExternalVolumeDescriptorsByPath.allValues ?: @[]) {
        if ([descriptor[@"diskID"] isEqualToString:diskID]) {
            [descriptors addObject:descriptor];
        }
    }
    [descriptors sortUsingComparator:
        ^NSComparisonResult(NSDictionary<NSString *, id> *left,
                            NSDictionary<NSString *, id> *right) {
        return [left[@"path"] compare:right[@"path"]
                              options:NSCaseInsensitiveSearch];
    }];
    return descriptors;
}

- (NSDictionary<NSString *, id> *)mountedExternalDescriptorForDiskID:
    (NSString *)diskID volumeUUID:(NSString *)volumeUUID {
    for (NSDictionary<NSString *, id> *descriptor in
         [self mountedExternalDescriptorsForDiskID:diskID]) {
        if ([[descriptor[@"volumeUUID"] uppercaseString]
                isEqualToString:volumeUUID.uppercaseString]) {
            return descriptor;
        }
    }
    return nil;
}

- (NSTimeInterval)unknownExternalVolumeNotificationRetryDelay {
    return 60.0;
}

- (void)scheduleUnknownExternalVolumeNotificationRetryForDiskID:
    (NSString *)diskID {
    if (!diskID.length || self.unknownExternalVolumeRetryTimersByDiskID[diskID]) {
        return;
    }
    if (!self.unknownExternalVolumeRetryTimersByDiskID) {
        self.unknownExternalVolumeRetryTimersByDiskID =
            [NSMutableDictionary dictionary];
    }
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:
        [self unknownExternalVolumeNotificationRetryDelay] repeats:NO
                                                   block:^(NSTimer *unused) {
        (void)unused;
        typeof(self) strongSelf = weakSelf;
        [strongSelf.unknownExternalVolumeRetryTimersByDiskID
            removeObjectForKey:diskID];
        [strongSelf finishUnknownExternalVolumeInspectionForDiskID:diskID];
    }];
    self.unknownExternalVolumeRetryTimersByDiskID[diskID] = timer;
}

- (void)finishUnknownExternalVolumeInspectionForDiskID:(NSString *)diskID {
    [self.unknownExternalVolumeTimersByDiskID removeObjectForKey:diskID];
    if ([self.knownExternalDiskIDs containsObject:diskID] ||
        [self.notifiedUnknownExternalDiskIDs containsObject:diskID] ||
        [self.pendingUnknownExternalDiskIDs containsObject:diskID]) {
        return;
    }
    NSArray<NSDictionary<NSString *, id> *> *descriptors =
        [self mountedExternalDescriptorsForDiskID:diskID];
    if (!descriptors.count) return;

    NSSet<NSString *> *knownUUIDs = [self configuredExternalVolumeUUIDs];
    for (NSDictionary<NSString *, id> *descriptor in descriptors) {
        if ([knownUUIDs containsObject:
                [descriptor[@"volumeUUID"] uppercaseString]]) {
            [self.knownExternalDiskIDs addObject:diskID];
            return;
        }
    }

    NSDictionary<NSString *, id> *preferred = nil;
    NSMutableArray<NSString *> *attachmentVolumeUUIDs =
        [NSMutableArray array];
    for (NSDictionary<NSString *, id> *descriptor in descriptors) {
        NSString *volumeUUID = [descriptor[@"volumeUUID"] uppercaseString];
        if (volumeUUID.length) {
            [attachmentVolumeUUIDs addObject:volumeUUID];
        }
    }
    for (NSDictionary<NSString *, id> *descriptor in descriptors) {
        if ([self isWritableExternalAPFSDescriptor:descriptor]) {
            preferred = descriptor;
            break;
        }
    }
    // Unsupported media are remembered in the passive mount cache only. They
    // never open UI, request permission, or advertise an unusable target.
    if (!preferred) return;
    if (!self.pendingUnknownExternalDiskIDs) {
        self.pendingUnknownExternalDiskIDs = [NSMutableSet set];
    }
    if (!self.pendingUnknownExternalVolumeUUIDsByDiskID) {
        self.pendingUnknownExternalVolumeUUIDsByDiskID =
            [NSMutableDictionary dictionary];
    }
    if (!self.notifiedUnknownExternalVolumeUUIDsByDiskID) {
        self.notifiedUnknownExternalVolumeUUIDsByDiskID =
            [NSMutableDictionary dictionary];
    }
    if (!self.unknownExternalVolumeDeliveryAttemptsByDiskID) {
        self.unknownExternalVolumeDeliveryAttemptsByDiskID =
            [NSMutableDictionary dictionary];
    }
    NSString *preferredUUID = [preferred[@"volumeUUID"] uppercaseString];
    NSMutableDictionary<NSString *, id> *notificationDescriptor =
        [preferred mutableCopy];
    notificationDescriptor[@"attachmentVolumeUUIDs"] =
        attachmentVolumeUUIDs;
    NSUInteger attempt =
        [self.unknownExternalVolumeDeliveryAttemptsByDiskID[diskID]
            unsignedIntegerValue] + 1;
    self.unknownExternalVolumeDeliveryAttemptsByDiskID[diskID] = @(attempt);
    [self.pendingUnknownExternalDiskIDs addObject:diskID];
    self.pendingUnknownExternalVolumeUUIDsByDiskID[diskID] = preferredUUID;
    __weak typeof(self) weakSelf = self;
    [self deliverUnknownExternalVolumeNotificationForDescriptor:
        notificationDescriptor
                                                     completion:^(BOOL delivered) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *pendingUUID =
            strongSelf.pendingUnknownExternalVolumeUUIDsByDiskID[diskID];
        if (![pendingUUID isEqualToString:preferredUUID]) {
            if (delivered) {
                [strongSelf removeUnknownExternalVolumeNotificationForDiskID:diskID
                                                                   volumeUUID:preferredUUID];
            }
            return;
        }
        [strongSelf.pendingUnknownExternalDiskIDs removeObject:diskID];
        [strongSelf.pendingUnknownExternalVolumeUUIDsByDiskID
            removeObjectForKey:diskID];
        BOOL sameAttachment = NO;
        for (NSDictionary<NSString *, id> *current in
             [strongSelf mountedExternalDescriptorsForDiskID:diskID]) {
            if ([attachmentVolumeUUIDs containsObject:
                    [current[@"volumeUUID"] uppercaseString]]) {
                sameAttachment = YES;
                break;
            }
        }
        if (delivered && sameAttachment &&
            ![strongSelf.knownExternalDiskIDs containsObject:diskID]) {
            [strongSelf.notifiedUnknownExternalDiskIDs addObject:diskID];
            strongSelf.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID] =
                preferredUUID;
            NSMutableSet<NSString *> *currentAttachmentVolumeUUIDs =
                [NSMutableSet setWithArray:attachmentVolumeUUIDs];
            for (NSDictionary<NSString *, id> *current in
                 [strongSelf mountedExternalDescriptorsForDiskID:diskID]) {
                NSString *currentUUID =
                    [current[@"volumeUUID"] uppercaseString];
                if (currentUUID.length) {
                    [currentAttachmentVolumeUUIDs addObject:currentUUID];
                }
            }
            [strongSelf rememberUnknownExternalAttachmentForDiskID:diskID
                                                        volumeUUIDs:
                currentAttachmentVolumeUUIDs.allObjects];
            [strongSelf.unknownExternalVolumeDeliveryAttemptsByDiskID
                removeObjectForKey:diskID];
        } else if (delivered) {
            [strongSelf removeUnknownExternalVolumeNotificationForDiskID:diskID
                                                               volumeUUID:preferredUUID];
        }
        if (!delivered && sameAttachment &&
            ![strongSelf.knownExternalDiskIDs containsObject:diskID] &&
            attempt < 2) {
            [strongSelf scheduleUnknownExternalVolumeNotificationRetryForDiskID:
                diskID];
        } else if (!sameAttachment) {
            [strongSelf.unknownExternalVolumeDeliveryAttemptsByDiskID
                removeObjectForKey:diskID];
            if ([strongSelf mountedExternalDescriptorsForDiskID:diskID].count &&
                ![strongSelf.knownExternalDiskIDs containsObject:diskID]) {
                [strongSelf finishUnknownExternalVolumeInspectionForDiskID:diskID];
            }
        }
    }];
}

- (void)processMountedVolumeDescriptor:(NSDictionary<NSString *, id> *)descriptor {
    if (![self isUnknownExternalVolumeDescriptorEligible:descriptor]) return;
    if (!self.mountedExternalVolumeDescriptorsByPath) {
        self.mountedExternalVolumeDescriptorsByPath = [NSMutableDictionary dictionary];
    }
    if (!self.unknownExternalVolumeTimersByDiskID) {
        self.unknownExternalVolumeTimersByDiskID = [NSMutableDictionary dictionary];
    }
    if (!self.knownExternalDiskIDs) {
        self.knownExternalDiskIDs = [NSMutableSet set];
    }
    if (!self.notifiedUnknownExternalDiskIDs) {
        self.notifiedUnknownExternalDiskIDs = [NSMutableSet set];
    }

    NSString *path = descriptor[@"path"];
    NSString *diskID = descriptor[@"diskID"];
    self.mountedExternalVolumeDescriptorsByPath[path] = descriptor;
    if ([[self configuredExternalVolumeUUIDs] containsObject:
            [descriptor[@"volumeUUID"] uppercaseString]]) {
        [self.knownExternalDiskIDs addObject:diskID];
        [self forgetUnknownExternalAttachmentForDiskID:diskID];
        [self.unknownExternalVolumeTimersByDiskID[diskID] invalidate];
        [self.unknownExternalVolumeTimersByDiskID removeObjectForKey:diskID];
        [self.unknownExternalVolumeRetryTimersByDiskID[diskID] invalidate];
        [self.unknownExternalVolumeRetryTimersByDiskID removeObjectForKey:diskID];
        [self.unknownExternalVolumeDeliveryAttemptsByDiskID removeObjectForKey:diskID];
        if ([self.notifiedUnknownExternalDiskIDs containsObject:diskID]) {
            [self removeUnknownExternalVolumeNotificationForDiskID:diskID];
            [self.notifiedUnknownExternalDiskIDs removeObject:diskID];
            [self.notifiedUnknownExternalVolumeUUIDsByDiskID removeObjectForKey:diskID];
        }
        return;
    }
    if ([self.notifiedUnknownExternalDiskIDs containsObject:diskID]) {
        NSSet<NSString *> *rememberedVolumeUUIDs =
            [self rememberedUnknownExternalVolumeUUIDsForDiskID:diskID];
        NSString *notifiedUUID =
            [self.notifiedUnknownExternalVolumeUUIDsByDiskID[diskID]
                uppercaseString];
        BOOL sameAttachment = NO;
        NSMutableSet<NSString *> *attachmentVolumeUUIDs =
            [rememberedVolumeUUIDs mutableCopy] ?: [NSMutableSet set];
        if (notifiedUUID.length) {
            [attachmentVolumeUUIDs addObject:notifiedUUID];
        }
        NSArray<NSDictionary<NSString *, id> *> *currentDescriptors =
            [self mountedExternalDescriptorsForDiskID:diskID];
        for (NSDictionary<NSString *, id> *current in currentDescriptors) {
            NSString *currentUUID = [current[@"volumeUUID"] uppercaseString];
            if ([attachmentVolumeUUIDs containsObject:currentUUID]) {
                sameAttachment = YES;
                break;
            }
        }
        if (sameAttachment) {
            for (NSDictionary<NSString *, id> *current in currentDescriptors) {
                NSString *currentUUID = [current[@"volumeUUID"] uppercaseString];
                if (currentUUID.length) {
                    [attachmentVolumeUUIDs addObject:currentUUID];
                }
            }
            [self rememberUnknownExternalAttachmentForDiskID:diskID
                                                 volumeUUIDs:
                attachmentVolumeUUIDs.allObjects];
        }
        return;
    }
    if ([self.knownExternalDiskIDs containsObject:diskID] ||
        [self.pendingUnknownExternalDiskIDs containsObject:diskID] ||
        [self.unknownExternalVolumeDeliveryAttemptsByDiskID[diskID]
            unsignedIntegerValue] >= 2 ||
        self.unknownExternalVolumeRetryTimersByDiskID[diskID] ||
        self.unknownExternalVolumeTimersByDiskID[diskID]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:
        [self unknownExternalVolumeNotificationDelay] repeats:NO
                                                   block:^(NSTimer *unused) {
        (void)unused;
        [weakSelf finishUnknownExternalVolumeInspectionForDiskID:diskID];
    }];
    self.unknownExternalVolumeTimersByDiskID[diskID] = timer;
}

- (void)loadConfiguredAPFSIdentityFromConfig:
    (NSDictionary<NSString *, NSString *> *)config {
    NSString *target = [config[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    NSString *configuredPath = config[@"GDRIVE_BACKUP_VOLUME"];
    NSString *volumeName = config[@"GDRIVE_BACKUP_VOLUME_NAME"];
    if (configuredPath.length) {
        self.configuredAPFSVolumePath = configuredPath;
    } else if ([target isEqualToString:@"apfs"]) {
        self.configuredAPFSVolumePath = [@"/Volumes"
            stringByAppendingPathComponent:
                (volumeName.length ? volumeName : @"GoogleDrive-Backup")];
    } else {
        // Opening and saving a NAS-only profile must not silently create a
        // same-name local mount trigger.
        self.configuredAPFSVolumePath = @"";
    }
    self.configuredAPFSVolumeUUID =
        [[config[@"GDRIVE_BACKUP_VOLUME_UUID"] ?: @""
            stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet]
            uppercaseString];
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
    NSString *configuredUUID =
        [config[@"GDRIVE_BACKUP_VOLUME_UUID"] stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (configuredUUID.length) {
        NSString *mountedUUID = [self volumeUUIDForPath:mountedPath];
        return mountedUUID.length &&
            [mountedUUID caseInsensitiveCompare:configuredUUID] == NSOrderedSame;
    }
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
    NSString *configuredUUID =
        [config[@"GDRIVE_BACKUP_VOLUME_UUID"] stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (configuredUUID.length &&
        [self mountedVolumePath:mountedPath matchesConfig:config]) {
        NSDate *now = [NSDate date];
        if (![self.lastMountTriggerPath isEqualToString:mountedPath] ||
            !self.lastMountTriggerDate ||
            [now timeIntervalSinceDate:self.lastMountTriggerDate] >= 15.0) {
            self.lastMountTriggerPath = mountedPath;
            self.lastMountTriggerDate = now;
            [self launchBackupWithArgument:@"--run" trigger:@"mount" assumeYes:NO];
        }
    }

    __weak typeof(self) weakSelf = self;
    if (!self.mountedExternalVolumeInspectionTokensByPath) {
        self.mountedExternalVolumeInspectionTokensByPath =
            [NSMutableDictionary dictionary];
    }
    NSString *inspectionToken = NSUUID.UUID.UUIDString;
    self.mountedExternalVolumeInspectionTokensByPath[mountedPath] =
        inspectionToken;
    [self inspectMountedVolumeAtPath:mountedPath
                         completion:^(NSDictionary<NSString *, id> *descriptor) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf ||
            ![strongSelf.mountedExternalVolumeInspectionTokensByPath[mountedPath]
                isEqualToString:inspectionToken]) {
            return;
        }
        [strongSelf.mountedExternalVolumeInspectionTokensByPath
            removeObjectForKey:mountedPath];
        [strongSelf processMountedVolumeDescriptor:descriptor];
    }];
}

- (void)workspaceVolumeDidUnmount:(NSNotification *)notification {
    [self refreshOverviewStatus:notification];
    NSURL *volumeURL = notification.userInfo[NSWorkspaceVolumeURLKey];
    if (![volumeURL isKindOfClass:NSURL.class] || !volumeURL.isFileURL) return;
    NSString *path = volumeURL.path.stringByStandardizingPath;
    [self.mountedExternalVolumeInspectionTokensByPath removeObjectForKey:path];
    NSDictionary<NSString *, id> *descriptor =
        self.mountedExternalVolumeDescriptorsByPath[path];
    NSString *diskID = descriptor[@"diskID"];
    if (!diskID.length) return;
    [self.mountedExternalVolumeDescriptorsByPath removeObjectForKey:path];
    NSArray<NSDictionary<NSString *, id> *> *remainingDescriptors =
        [self mountedExternalDescriptorsForDiskID:diskID];
    // The banner represents the physical attachment, not one APFS sibling.
    // Keeping it avoids a second presentation when only the selected volume
    // leaves; its UUID set lets an explicit action revalidate a remaining sibling.
    if (remainingDescriptors.count) return;

    [self.unknownExternalVolumeTimersByDiskID[diskID] invalidate];
    [self.unknownExternalVolumeTimersByDiskID removeObjectForKey:diskID];
    [self.unknownExternalVolumeRetryTimersByDiskID[diskID] invalidate];
    [self.unknownExternalVolumeRetryTimersByDiskID removeObjectForKey:diskID];
    if ([self.notifiedUnknownExternalDiskIDs containsObject:diskID] ||
        [self.pendingUnknownExternalDiskIDs containsObject:diskID]) {
        [self removeUnknownExternalVolumeNotificationForDiskID:diskID];
    }
    [self.pendingUnknownExternalDiskIDs removeObject:diskID];
    [self.pendingUnknownExternalVolumeUUIDsByDiskID removeObjectForKey:diskID];
    [self.unknownExternalVolumeDeliveryAttemptsByDiskID removeObjectForKey:diskID];
    [self.knownExternalDiskIDs removeObject:diskID];
    [self.notifiedUnknownExternalDiskIDs removeObject:diskID];
    [self.notifiedUnknownExternalVolumeUUIDsByDiskID removeObjectForKey:diskID];
    [self forgetUnknownExternalAttachmentForDiskID:diskID];
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

    NSSize size = NSMakeSize(620, 520);
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
    content.destinationHandler = ^{ [weakSelf adHocDestinationChanged]; };
    content.settingsHandler = ^{ [weakSelf showBackupSetup:nil]; };
    content.restoreHandler = ^{ [weakSelf showRestoreBrowser:nil]; };
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
    self.updateConsentRequested = YES;
    [self showOverviewWindow];
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayRestoreVersions:
    (NSArray<NSDictionary<NSString *, id> *> *)versions {
    NSDictionary<NSString *, NSString *> *localeIdentifiers = @{
        @"de": @"de_DE", @"en": @"en_US", @"fr": @"fr_FR", @"es": @"es_ES",
        @"ja": @"ja_JP", @"yue": @"zh_HK", @"ko": @"ko_KR"
    };
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:
        localeIdentifiers[self.language ?: @"en"] ?: @"en_US"];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    NSByteCountFormatter *sizeFormatter = [[NSByteCountFormatter alloc] init];
    sizeFormatter.countStyle = NSByteCountFormatterCountStyleFile;

    NSMutableArray<NSDictionary<NSString *, id> *> *display = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *version in versions) {
        NSMutableDictionary<NSString *, id> *record = [version mutableCopy];
        if ([version[@"kind"] isEqualToString:@"current"]) {
            record[@"displayDate"] = T(self.language ?: @"en", @"restoreCurrent");
        } else if ([version[@"date"] isKindOfClass:NSDate.class]) {
            record[@"displayDate"] = [dateFormatter stringFromDate:version[@"date"]] ?:
                T(self.language ?: @"en", @"restoreHistorical");
        } else {
            record[@"displayDate"] = T(self.language ?: @"en", @"restoreHistorical");
        }
        record[@"displaySize"] = [sizeFormatter stringFromByteCount:
            [version[@"size"] longLongValue]] ?: @"";
        [display addObject:record];
    }
    return display;
}

- (void)loadRestoreDirectory:(NSString *)relativePath {
    if (!self.restoreCatalog || !self.restoreView) {
        return;
    }
    NSUInteger generation = ++self.restoreLoadGeneration;
    self.restoreView.currentRelativePath = relativePath ?: @"";
    self.restoreView.loading = YES;
    GDTRestoreCatalog *catalog = self.restoreCatalog;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<NSDictionary<NSString *, id> *> *entries =
            [catalog childrenAtRelativePath:relativePath ?: @"" error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.restoreLoadGeneration) {
                return;
            }
            strongSelf.restoreView.loading = NO;
            strongSelf.restoreView.versions = @[];
            if (error) {
                strongSelf.restoreView.entries = @[];
                [strongSelf.restoreView showRestoreError:
                    T(strongSelf.language ?: @"en", @"restoreFailed")];
                return;
            }
            strongSelf.restoreView.entries = entries;
            strongSelf.restoreView.statusText = entries.count ? @"" :
                T(strongSelf.language ?: @"en", @"restoreEmpty");
        });
    });
}

- (void)loadRestoreVersionsForRelativePath:(NSString *)relativePath {
    if (!self.restoreCatalog || !self.restoreView) {
        return;
    }
    NSUInteger generation = ++self.restoreLoadGeneration;
    self.restoreView.loading = YES;
    GDTRestoreCatalog *catalog = self.restoreCatalog;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<NSDictionary<NSString *, id> *> *versions =
            [catalog versionsForRelativePath:relativePath error:&error];
        typeof(self) strongSelf = weakSelf;
        NSArray<NSDictionary<NSString *, id> *> *display = strongSelf
            ? [strongSelf displayRestoreVersions:versions] : @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf || generation != innerSelf.restoreLoadGeneration) {
                return;
            }
            innerSelf.restoreView.loading = NO;
            if (error) {
                innerSelf.restoreView.versions = @[];
                [innerSelf.restoreView showRestoreError:
                    T(innerSelf.language ?: @"en", @"restoreFailed")];
                return;
            }
            innerSelf.restoreView.versions = display;
            innerSelf.restoreView.statusText = display.count ? @"" :
                T(innerSelf.language ?: @"en", @"restoreNoVersions");
        });
    });
}

- (void)beginRestoreForVersion:(NSDictionary<NSString *, id> *)version {
    NSURL *sourceURL = [version[@"sourceURL"] isKindOfClass:NSURL.class]
        ? version[@"sourceURL"] : nil;
    NSString *remotePath = [version[@"remotePath"] isKindOfClass:NSString.class]
        ? version[@"remotePath"] : nil;
    NSString *sourceName = [version[@"name"] isKindOfClass:NSString.class]
        ? version[@"name"] : remotePath.lastPathComponent;
    if ((!sourceURL && !remotePath.length) || !sourceName.length ||
        !self.restoreWindow || !self.restoreCopier) {
        [self.restoreView showRestoreError:T(self.language ?: @"en", @"restoreFailed")];
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = T(self.language ?: @"en", @"restoreAction");
    panel.message = T(self.language ?: @"en", @"restoreChooseDestination");
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.restoreWindow completionHandler:^(NSModalResponse result) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || result != NSModalResponseOK || !panel.URL) {
            return;
        }
        strongSelf.restoreView.loading = YES;
        id copier = strongSelf.restoreCopier;
        NSURL *destinationDirectory = panel.URL;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            NSDictionary<NSString *, id> *restoreResult = nil;
            if (remotePath.length && [copier isKindOfClass:GDTCryptRestoreCopier.class]) {
                restoreResult = [(GDTCryptRestoreCopier *)copier
                    restoreRemotePath:remotePath name:sourceName
                    toDirectoryURL:destinationDirectory error:&error];
            } else if (sourceURL && [copier isKindOfClass:GDTRestoreCopier.class]) {
                restoreResult = [(GDTRestoreCopier *)copier
                    restoreSourceURL:sourceURL name:sourceName
                    toDirectoryURL:destinationDirectory error:&error];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) innerSelf = weakSelf;
                if (!innerSelf) {
                    return;
                }
                if (restoreResult) {
                    [innerSelf.restoreView showVerifiedDestinationURL:
                        restoreResult[@"destinationURL"] sha256:restoreResult[@"sha256"]];
                } else {
                    NSString *key = [error.domain isEqualToString:
                        @"com.commcats.gdrivebackup.restore"] && error.code == 4
                        ? @"restoreIntegrityFailed" : @"restoreFailed";
                    [innerSelf.restoreView showRestoreError:T(innerSelf.language ?: @"en", key)];
                }
            });
        });
    }];
}

- (void)showRestoreBrowser:(id)sender {
    (void)sender;
    if (self.restoreWindow.isVisible) {
        [self.restoreWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    NSDictionary<NSString *, NSString *> *config = [self savedSetupConfig];
    NSString *destination = GDTBackupDestinationForConfig(config);
    NSString *encryption = [config[@"GDRIVE_BACKUP_ENCRYPTION"] ?: @"none" lowercaseString];
    BOOL usesRcloneCrypt = [encryption isEqualToString:@"rclone-crypt"];
    NSString *cryptRemote = config[@"GDRIVE_BACKUP_CRYPT_REMOTE"] ?: @"";
    NSString *versionsSubdirectory = config[@"GDRIVE_BACKUP_VERSIONS_SUBDIR"] ?: @".gdrive-versions";
    NSURL *rootURL = destination.length
        ? [NSURL fileURLWithPath:destination isDirectory:YES] : nil;

    NSSize size = NSMakeSize(820, 560);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame :
        NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2,
                                 NSMidY(screenFrame) - size.height / 2);
    self.restoreWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered defer:NO];
    self.restoreWindow.title = T(self.language ?: @"en", @"restoreTitle");
    self.restoreWindow.minSize = NSMakeSize(720, 480);
    self.restoreWindow.releasedWhenClosed = NO;
    self.restoreWindow.delegate = self;
    self.restoreView = [[GDTRestoreBrowserView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    self.restoreView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.restoreView.language = self.language ?: @"en";
    self.restoreWindow.contentView = self.restoreView;

    __weak typeof(self) weakSelf = self;
    self.restoreView.backHandler = ^{
        NSString *path = weakSelf.restoreView.currentRelativePath ?: @"";
        NSString *parent = path.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:@"."]) parent = @"";
        [weakSelf loadRestoreDirectory:parent];
    };
    self.restoreView.browseHandler = ^(NSString *relativePath) {
        [weakSelf loadRestoreDirectory:relativePath];
    };
    self.restoreView.fileSelectionHandler = ^(NSString *relativePath) {
        [weakSelf loadRestoreVersionsForRelativePath:relativePath];
    };
    self.restoreView.restoreHandler = ^(NSDictionary<NSString *, id> *version) {
        [weakSelf beginRestoreForVersion:version];
    };
    self.restoreView.revealHandler = ^(NSURL *destinationURL) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[destinationURL]];
    };

    BOOL isDirectory = NO;
    if (!rootURL || (usesRcloneCrypt && !cryptRemote.length) ||
        ![NSFileManager.defaultManager fileExistsAtPath:rootURL.path
                                             isDirectory:&isDirectory] || !isDirectory) {
        self.restoreView.entries = @[];
        self.restoreView.statusText = T(self.language ?: @"en", @"restoreTargetUnavailable");
    } else {
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        if (usesRcloneCrypt) {
            self.restoreCatalog = [GDTCryptRestoreCatalog productionCatalogWithRemoteName:cryptRemote
                                                                      versionsSubdirectory:versionsSubdirectory];
            self.restoreCopier = [GDTCryptRestoreCopier productionCopierWithRemoteName:cryptRemote
                                                                           backupRootURL:rootURL
                                                                   versionsSubdirectory:versionsSubdirectory
                                                                             fileManager:fileManager];
        } else {
            self.restoreCatalog = [[GDTRestoreCatalog alloc] initWithBackupRootURL:rootURL
                                                                      fileManager:fileManager
                                                             versionsSubdirectory:versionsSubdirectory];
            self.restoreCopier = [[GDTRestoreCopier alloc] initWithBackupRootURL:rootURL
                                                                     fileManager:fileManager];
        }
        [self loadRestoreDirectory:@""];
    }
    [self.restoreWindow makeFirstResponder:self.restoreView.itemsTable];
    [self.restoreWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)diagnosticsServiceIsLoaded:(NSString *)label {
    if (!label.length ||
        [label rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return NO;
    }
    NSString *service = [NSString stringWithFormat:@"gui/%u/%@", getuid(), label];
    int status = 0;
    // launchctl may print user paths and environment values. Diagnostics need
    // only the exit status, so its output must never enter the support report.
    (void)RunCommand(@"/bin/launchctl", @[@"print", service], nil, &status);
    return status == 0;
}

- (NSDictionary<NSString *, id> *)diagnosticsAppInfo {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *osVersion = os.patchVersion > 0
        ? [NSString stringWithFormat:@"macOS %ld.%ld.%ld", (long)os.majorVersion,
            (long)os.minorVersion, (long)os.patchVersion]
        : [NSString stringWithFormat:@"macOS %ld.%ld", (long)os.majorVersion,
            (long)os.minorVersion];
#if defined(__arm64__)
    NSString *architecture = @"arm64";
#elif defined(__x86_64__)
    NSString *architecture = @"x86_64";
#else
    NSString *architecture = @"unknown";
#endif
    return @{
        @"version": version,
        @"build": build,
        @"osVersion": osVersion,
        @"architecture": architecture
    };
}

- (NSDictionary<NSString *, id> *)diagnosticsServiceState {
    return @{
        @"controllerLoaded": @([self diagnosticsServiceIsLoaded:@"com.commcats.gdrivebackup"]),
        @"scheduleLoaded": @([self diagnosticsServiceIsLoaded:@"com.commcats.gdrivebackup.schedule"])
    };
}

- (NSDictionary<NSString *, id> *)diagnosticsScriptState {
    NSString *path = @"/usr/local/bin/backup-google-drive.sh";
    BOOL installed = [NSFileManager.defaultManager fileExistsAtPath:path];
    return @{
        @"installed": @(installed),
        @"executable": @(installed && [NSFileManager.defaultManager isExecutableFileAtPath:path])
    };
}

- (void)completeDiagnosticsWithSnapshot:(NSDictionary<NSString *, id> *)snapshot
                                  report:(NSString *)report
                              generation:(NSUInteger)generation {
    if (generation != self.diagnosticsGeneration || !self.diagnosticsView) {
        return;
    }
    self.diagnosticsView.report = report ?: @"";
    self.diagnosticsView.loading = NO;
    [self.diagnosticsView applySnapshot:snapshot ?: @{}];
}

- (void)refreshDiagnostics {
    if (!self.diagnosticsView || self.diagnosticsView.loading) {
        return;
    }
    self.diagnosticsView.loading = YES;
    NSUInteger generation = ++self.diagnosticsGeneration;
    NSDictionary<NSString *, NSString *> *config = [[self savedSetupConfig] copy];
    NSDictionary<NSString *, NSString *> *summary =
        [GDTReadBackupSummaryAtPath(GDTBackupSummaryPathForConfig(config)) copy];
    NSDictionary<NSString *, id> *appInfo = [[self diagnosticsAppInfo] copy];
    GDTSetupHealthChecker *checker = [GDTSetupHealthChecker productionChecker];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary<NSString *, id> *health = [checker snapshotForConfig:config];
        NSDictionary<NSString *, id> *serviceState = [strongSelf diagnosticsServiceState];
        NSDictionary<NSString *, id> *scriptState = [strongSelf diagnosticsScriptState];
        NSDictionary<NSString *, id> *snapshot = [GDTDiagnosticsBuilder
            snapshotForConfig:config
                      summary:summary
                  setupHealth:health
                      appInfo:appInfo
                 serviceState:serviceState
                  scriptState:scriptState];
        NSString *report = [GDTDiagnosticsBuilder reportForSnapshot:snapshot];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf completeDiagnosticsWithSnapshot:snapshot
                                                report:report
                                            generation:generation];
        });
    });
}

- (void)copyDiagnosticsReport:(NSString *)report {
    if (!report.length) return;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:report forType:NSPasteboardTypeString];
    [self.diagnosticsView showFeedbackKey:@"diagnosticsCopied"];
}

- (BOOL)writeDiagnosticsReport:(NSString *)report
                         toURL:(NSURL *)url
                         error:(NSError **)error {
    if (!report.length || !url.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.diagnostics"
                                          code:1
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid diagnostics report destination."}];
        }
        return NO;
    }
    NSData *data = [report dataUsingEncoding:NSUTF8StringEncoding];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    if (![NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                         ofItemAtPath:url.path
                                                error:error]) {
        return NO;
    }
    return YES;
}

- (void)saveDiagnosticsReport:(NSString *)report {
    if (!report.length || !self.diagnosticsWindow) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"GDrive-Backup-Tiger-Diagnostics.txt";
    panel.canCreateDirectories = YES;
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.diagnosticsWindow completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        NSError *error = nil;
        if ([weakSelf writeDiagnosticsReport:report toURL:panel.URL error:&error]) {
            [weakSelf.diagnosticsView showFeedbackKey:@"diagnosticsSaved"];
        } else {
            [weakSelf.diagnosticsView showFeedbackKey:@"diagnosticsFailure"];
        }
    }];
}

- (void)showDiagnostics:(id)sender {
    (void)sender;
    if (!self.diagnosticsWindow) {
        NSSize size = NSMakeSize(680, 520);
        NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame :
            NSMakeRect(0, 0, 1200, 800);
        NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2,
                                     NSMidY(screenFrame) - size.height / 2);
        self.diagnosticsWindow = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered defer:NO];
        self.diagnosticsWindow.title = T(self.language ?: @"en", @"diagnosticsTitle");
        self.diagnosticsWindow.minSize = NSMakeSize(620, 500);
        self.diagnosticsWindow.releasedWhenClosed = NO;
        self.diagnosticsWindow.level = NSNormalWindowLevel;
        self.diagnosticsWindow.delegate = self;
        self.diagnosticsView = [[GDTDiagnosticsView alloc]
            initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
        self.diagnosticsView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.diagnosticsView.language = self.language ?: @"en";
        __weak typeof(self) weakSelf = self;
        self.diagnosticsView.refreshHandler = ^{ [weakSelf refreshDiagnostics]; };
        self.diagnosticsView.copyHandler = ^(NSString *report) {
            [weakSelf copyDiagnosticsReport:report];
        };
        self.diagnosticsView.saveHandler = ^(NSString *report) {
            [weakSelf saveDiagnosticsReport:report];
        };
        self.diagnosticsWindow.contentView = self.diagnosticsView;
    }
    self.diagnosticsWindow.title = T(self.language ?: @"en", @"diagnosticsTitle");
    self.diagnosticsView.language = self.language ?: @"en";
    [self.diagnosticsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshDiagnostics];
}

- (BOOL)openUpdateURL:(NSURL *)url {
    return [NSWorkspace.sharedWorkspace openURL:url];
}

- (GDTAutomaticUpdatePolicy *)updatePolicy {
    if (!self.automaticUpdatePolicy) {
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";
        self.automaticUpdatePolicy = [[GDTAutomaticUpdatePolicy alloc]
            initWithDefaults:NSUserDefaults.standardUserDefaults checker:[GDTUpdateChecker new]
            currentVersion:version];
        __weak typeof(self) weakSelf = self;
        self.automaticUpdatePolicy.stateChanged = ^{ [weakSelf automaticUpdateStateChanged]; };
    }
    return self.automaticUpdatePolicy;
}

- (BOOL)updateApplicationIsActive {
    return NSApp.isActive;
}

- (void)automaticUpdateTick {
    if (!self.overviewMode || self.confirmMode || self.setupMode || self.progressForegroundMode) return;
    for (NSString *identifier in [[self updatePolicy] takeObsoleteNoticeIdentifiers]) {
        [self removeUpdateNoticeIdentifier:identifier];
    }
    if (!self.updateAuthorizationGeneration.length) [[self updatePolicy] checkIfDue];
}

- (void)appendAutomaticUpdateItemsToMenu:(NSMenu *)menu {
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:T(self.language ?: @"en", @"updateSettings")
        action:@selector(showUpdatePreferences:) keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];
    NSString *version = [self updatePolicy].availableVersion;
    if (!version.length) return;
    NSMenuItem *available = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:T(self.language ?: @"en", @"updateAvailableMenu"), version]
        action:@selector(openOfficialReleasePage:) keyEquivalent:@""];
    available.target = self;
    [menu addItem:available];
}

- (NSAlert *)updatePreferencesAlertForConsent:(BOOL)consent {
    NSString *language = self.language ?: @"en";
    NSAlert *alert = [NSAlert new];
    alert.messageText = T(language, consent ? @"updateConsentTitle" : @"updateSettings");
    alert.informativeText = T(language, @"updatePrivacyMessage");
    if (consent) {
        [alert addButtonWithTitle:T(language, @"updateEnable")];
        [alert addButtonWithTitle:T(language, @"updateDecline")];
    } else {
        NSButton *checkbox = [NSButton checkboxWithTitle:T(language, @"updateAutomatic") target:nil action:nil];
        [checkbox sizeToFit];
        checkbox.state = [self updatePolicy].enabled ? NSControlStateValueOn : NSControlStateValueOff;
        alert.accessoryView = checkbox;
        [alert addButtonWithTitle:T(language, @"save")];
        [alert addButtonWithTitle:T(language, @"cancel")];
    }
    return alert;
}

- (void)presentUpdatePreferencesAlert:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    if (self.window.isVisible && !self.window.attachedSheet) {
        [alert beginSheetModalForWindow:self.window completionHandler:completion];
    } else {
        completion([alert runModal]);
    }
}

- (void)setUpdateConsentRequested:(BOOL)requested {
    _updateConsentRequested = requested;
    if (requested) {
        self.updateConsentGeneration++;
        self.updateConsentSnapshotGeneration = 0;
    }
}

- (void)acceptOverviewSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
       updateConsentGeneration:(NSUInteger)generation {
    self.lastOverviewSnapshot = snapshot;
    if (self.updateConsentRequested && generation != self.updateConsentGeneration) {
        // A read started before this overview intent or activation cannot prove
        // that backups are idle now. Keep the intent and request a current read.
        [self refreshOverviewStatus:nil];
        return;
    }
    self.updateConsentSnapshotGeneration = generation;
    [self maybeOfferUpdateConsent];
}

- (void)maybeOfferUpdateConsent {
    if (!self.updateConsentRequested || self.updateConsentOffered || self.updatePreferencesPresenting ||
        !self.updateConsentGeneration || self.updateConsentSnapshotGeneration != self.updateConsentGeneration ||
        [self updatePolicy].answered || !self.overviewMode || self.confirmMode || self.setupMode ||
        self.progressForegroundMode || !self.window.isVisible || ![self updateApplicationIsActive] ||
        self.window.attachedSheet || !self.lastOverviewSnapshot || self.overviewLaunchPending ||
        self.manualLaunchPending || self.automaticRetryIdentifiersInFlight.count ||
        [self.lastOverviewSnapshot[@"status"] isEqual:@"running"]) return;
    self.updateConsentOffered = YES;
    self.updateConsentRequested = NO;
    self.updatePreferencesPresenting = YES;
    __weak typeof(self) weakSelf = self;
    [self presentUpdatePreferencesAlert:[self updatePreferencesAlertForConsent:YES]
        completion:^(NSModalResponse response) {
            weakSelf.updatePreferencesPresenting = NO;
            if (response == NSAlertFirstButtonReturn) [weakSelf setAutomaticUpdatesEnabled:YES];
            else if (response == NSAlertSecondButtonReturn) [weakSelf setAutomaticUpdatesEnabled:NO];
        }];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (!self.updateConsentRequested || self.updateConsentOffered || [self updatePolicy].answered) return;
    self.updateConsentRequested = YES;
    [self refreshOverviewStatus:nil];
}

- (void)showUpdatePreferences:(id)sender {
    (void)sender;
    if (self.updatePreferencesPresenting || self.window.attachedSheet) return;
    NSAlert *alert = [self updatePreferencesAlertForConsent:NO];
    self.updatePreferencesPresenting = YES;
    __weak typeof(self) weakSelf = self;
    [self presentUpdatePreferencesAlert:alert completion:^(NSModalResponse response) {
        weakSelf.updatePreferencesPresenting = NO;
        if (response == NSAlertFirstButtonReturn) {
            [weakSelf setAutomaticUpdatesEnabled:((NSButton *)alert.accessoryView).state == NSControlStateValueOn];
        }
    }];
}

- (void)setAutomaticUpdatesEnabled:(BOOL)enabled {
    GDTAutomaticUpdatePolicy *policy = [self updatePolicy];
    BOOL explicitOptIn = enabled && !policy.enabled;
    [policy setEnabled:enabled];
    if (!enabled) self.updateAuthorizationGeneration = nil;
    if (explicitOptIn) {
        NSString *generation = policy.generation;
        self.updateAuthorizationGeneration = generation;
        UNUserNotificationCenter *center = [self backupNotificationCenter];
        __weak typeof(self) weakSelf = self;
        void (^finishAuthorization)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (![strongSelf.updateAuthorizationGeneration isEqual:generation]) return;
                strongSelf.updateAuthorizationGeneration = nil;
                [strongSelf automaticUpdateTick];
            });
        };
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!policy.enabled || ![policy.generation isEqual:generation]) return;
                if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) {
                    finishAuthorization();
                    return;
                }
                // Permission is app-wide; silent update content must not prevent
                // later backup alerts from using their existing sound behavior.
                [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                    completionHandler:^(BOOL granted, NSError *error) {
                        (void)granted; (void)error;
                        finishAuthorization();
                    }];
            });
        }];
    }
    [self automaticUpdateTick];
}

- (NSString *)updateNoticeIdentifierForVersion:(NSString *)version generation:(NSString *)generation {
    return [NSString stringWithFormat:@"com.commcats.gdrivebackup.update.%@.%@", generation, version];
}

- (void)removeUpdateNoticeIdentifier:(NSString *)identifier {
    if (!identifier.length) return;
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
    [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
}

- (void)automaticUpdateStateChanged {
    GDTAutomaticUpdatePolicy *policy = [self updatePolicy];
    for (NSString *identifier in [policy takeObsoleteNoticeIdentifiers]) [self removeUpdateNoticeIdentifier:identifier];
    [self buildMainMenu];
    if (self.statusItem && self.lastOverviewSnapshot) {
        self.statusItem.menu = [self statusMenuForSnapshot:self.lastOverviewSnapshot];
        self.statusItem.menu.delegate = self;
    }
    NSString *version = [policy claimNoticeVersion];
    if (!version) return;
    NSString *generation = policy.generation;
    NSString *identifier = [self updateNoticeIdentifierForVersion:version generation:generation];
    UNUserNotificationCenter *center = [self backupNotificationCenter];
    __weak typeof(self) weakSelf = self;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        void (^deliver)(void) = ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || ![policy acceptsNoticeVersion:version generation:generation] ||
                (settings.authorizationStatus != UNAuthorizationStatusAuthorized &&
                 settings.authorizationStatus != UNAuthorizationStatusProvisional)) return;
            UNMutableNotificationContent *content = [UNMutableNotificationContent new];
            content.title = T(strongSelf.language ?: @"en", @"updateAvailableTitle");
            content.body = [NSString stringWithFormat:T(strongSelf.language ?: @"en", @"updateNoticeMessage"), version];
            content.categoryIdentifier = @"GDT_UPDATE_AVAILABLE";
            content.interruptionLevel = UNNotificationInterruptionLevelPassive;
            content.userInfo = @{@"version": version, @"generation": generation};
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
            [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
                (void)error;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (![policy acceptsNoticeVersion:version generation:generation]) {
                        [weakSelf removeUpdateNoticeIdentifier:identifier];
                    }
                });
            }];
        };
        if (NSThread.isMainThread) deliver();
        else dispatch_async(dispatch_get_main_queue(), deliver);
    }];
}

- (void)handleUpdateNotificationAction:(NSString *)action userInfo:(NSDictionary *)info identifier:(NSString *)identifier {
    NSString *version = [info[@"version"] isKindOfClass:NSString.class] ? info[@"version"] : @"";
    NSString *generation = [info[@"generation"] isKindOfClass:NSString.class] ? info[@"generation"] : @"";
    if (![[self updatePolicy] acceptsNoticeVersion:version generation:generation] ||
        ![identifier isEqual:[self updateNoticeIdentifierForVersion:version generation:generation]]) return;
    BOOL open = [action isEqual:@"GDT_UPDATE_OPEN"] || [action isEqual:UNNotificationDefaultActionIdentifier];
    if (!open && ![action isEqual:@"GDT_UPDATE_LATER"] && ![action isEqual:UNNotificationDismissActionIdentifier]) return;
    [self removeUpdateNoticeIdentifier:identifier];
    if (open) [self openOfficialReleasePage:nil];
}

- (void)openOfficialReleasePage:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:
        @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"];
    [self openUpdateURL:url];
}

- (void)presentUpdateResult:(NSDictionary<NSString *, NSString *> *)result {
    NSString *language = self.language ?: @"en";
    NSString *status = result[@"status"] ?: @"unavailable";
    NSAlert *alert = [[NSAlert alloc] init];
    if ([status isEqualToString:@"updateAvailable"]) {
        alert.messageText = T(language, @"updateAvailableTitle");
        alert.informativeText = [NSString stringWithFormat:T(language, @"updateAvailableMessage"),
            result[@"version"] ?: @"?"];
        [alert addButtonWithTitle:T(language, @"updateOpenRelease")];
        [alert addButtonWithTitle:T(language, @"notNow")];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [self openOfficialReleasePage:nil];
        }
        return;
    }
    if ([status isEqualToString:@"current"]) {
        alert.messageText = T(language, @"updateCurrentTitle");
        alert.informativeText = [NSString stringWithFormat:T(language, @"updateCurrentMessage"),
            result[@"version"] ?: @"?"];
    } else {
        alert.messageText = T(language, @"updateUnavailableTitle");
        alert.informativeText = T(language, @"updateUnavailableMessage");
    }
    [alert addButtonWithTitle:T(language, @"done")];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

- (void)completeUpdateCheck:(NSDictionary<NSString *, NSString *> *)result {
    self.updateChecking = NO;
    [self buildMainMenu];
    if (self.statusItem) {
        NSDictionary<NSString *, NSString *> *snapshot = self.lastOverviewSnapshot ?: @{
            @"status": @"unknown",
            @"lastRun": T(self.language ?: @"en", @"overviewNeverRun"),
            @"lastRunDetail": @"",
            @"nextRun": T(self.language ?: @"en", @"overviewUnavailable"),
            @"target": T(self.language ?: @"en", @"overviewUnavailable"),
            @"storage": T(self.language ?: @"en", @"overviewUnavailable")
        };
        self.statusItem.menu = [self statusMenuForSnapshot:snapshot];
        self.statusItem.menu.delegate = self;
    }
    [self presentUpdateResult:result ?: @{ @"status": @"unavailable", @"reason": @"network" }];
}

- (void)checkForUpdates:(id)sender {
    if (self.updateChecking) return;
    self.updateChecking = YES;
    if ([sender isKindOfClass:NSMenuItem.class]) {
        NSMenuItem *item = sender;
        item.title = T(self.language ?: @"en", @"updateChecking");
        item.enabled = NO;
    }
    if (!self.updateChecker) self.updateChecker = [[GDTUpdateChecker alloc] init];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:
        @"CFBundleShortVersionString"] ?: @"0.0.0";
    __weak typeof(self) weakSelf = self;
    [self.updateChecker checkCurrentVersion:version completion:^(NSDictionary *result) {
        void (^finish)(void) = ^{
            [weakSelf completeUpdateCheck:result];
        };
        if (NSThread.isMainThread) {
            finish();
        } else {
            dispatch_async(dispatch_get_main_queue(), finish);
        }
    }];
}

- (void)showBackupSetup:(id)sender {
    (void)sender;
    [self showSetupWindow];
}

- (void)updateControllerActivationPolicy {
    if (!self.overviewMode) {
        return;
    }
    BOOL hasVisibleWindow = self.window.isVisible ||
        self.setupWindow.isVisible ||
        self.restoreWindow.isVisible ||
        self.diagnosticsWindow.isVisible;
    [NSApp setActivationPolicy:hasVisibleWindow
        ? NSApplicationActivationPolicyRegular
        : NSApplicationActivationPolicyAccessory];
}

#include "AdHocDestinationMethods.inc"

- (void)startOverviewBackup:(id)sender {
    (void)sender;
    if ([self.window.contentView isKindOfClass:TigerOverviewView.class]) {
        [self startAdHocBackup];
        return;
    }
    if (self.overviewLaunchPending) {
        return;
    }
    NSDictionary<NSString *, NSString *> *previousSnapshot = self.lastOverviewSnapshot;
    self.overviewLaunchPending = YES;
    NSMutableDictionary<NSString *, NSString *> *snapshot =
        [previousSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
    snapshot[@"status"] = @"running";
    snapshot[@"lastRun"] = T(self.language ?: @"en", @"statusBackupPreparing");
    snapshot[@"lastRunDetail"] = @"";
    self.lastOverviewSnapshot = snapshot;
    if ([self.window.contentView isKindOfClass:TigerOverviewView.class]) {
        [self applyOverviewSnapshot:snapshot toView:(TigerOverviewView *)self.window.contentView];
    }
    [self updateOverviewRefreshTimerForStatus:@"running"];
    if (![self launchBackupWithArgument:@"--run" assumeYes:YES]) {
        self.overviewLaunchPending = NO;
        self.lastOverviewSnapshot = previousSnapshot;
        if (previousSnapshot && [self.window.contentView isKindOfClass:TigerOverviewView.class]) {
            [self applyOverviewSnapshot:previousSnapshot toView:(TigerOverviewView *)self.window.contentView];
        }
        [self refreshOverviewStatus:nil];
        return;
    }
    snapshot[@"lastRun"] = T(self.language ?: @"en", @"statusBackupStarted");
    self.lastOverviewSnapshot = snapshot;
    if ([self.window.contentView isKindOfClass:TigerOverviewView.class]) {
        [self applyOverviewSnapshot:snapshot toView:(TigerOverviewView *)self.window.contentView];
    }
    [self handoffOverviewDockPresenceToManualProgress];
}

- (void)handoffOverviewDockPresenceToManualProgress {
    // Manual progress is a separate foreground process so its Dock icon can
    // reliably reactivate the small status window. The persistent controller
    // yields its own icon here to keep one coherent app presence in the Dock.
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
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

- (NSWindowCollectionBehavior)statusWindowCollectionBehavior {
    // Status UI belongs to the Space where it was requested. In particular it
    // must never become an auxiliary window of an unrelated fullscreen app.
    return NSWindowCollectionBehaviorManaged |
        NSWindowCollectionBehaviorFullScreenNone;
}

- (BOOL)statusWindowShouldHideOnDeactivate {
    // A mount-triggered confirmation never activates the app, so hiding it
    // while inactive would make the safety question impossible to answer.
    return !self.confirmMode;
}

- (BOOL)shouldShowProgressForTrigger:(NSString *)trigger
                   fromVisibleWindow:(BOOL)visibleWindow {
    BOOL foregroundTrigger = [trigger isEqualToString:@"manual"] ||
        [trigger isEqualToString:@"setup"];
    if (!foregroundTrigger || !visibleWindow) {
        return NO;
    }
    return self.setupMode || self.setupWindow.isVisible ||
        (self.overviewMode && !self.menubarOnlyMode);
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
    NSMenuItem *diagnosticsItem = [[NSMenuItem alloc]
        initWithTitle:T(self.language, @"diagnosticsTitle")
                 action:@selector(showDiagnostics:)
          keyEquivalent:@""];
    diagnosticsItem.target = self;
    [appMenu addItem:diagnosticsItem];
    NSMenuItem *updateItem = [[NSMenuItem alloc]
        initWithTitle:T(self.language ?: @"en", self.updateChecking ? @"updateChecking" : @"updateCheck")
                 action:@selector(checkForUpdates:)
          keyEquivalent:@""];
    updateItem.target = self;
    updateItem.enabled = !self.updateChecking;
    [appMenu addItem:updateItem];
    [self appendAutomaticUpdateItemsToMenu:appMenu];
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
    if (self.overviewMode) {
        [self configureBackupNotificationsForConfig:GDTReadConfigDictionary()];
        [self refreshOverviewStatus:nil];
    }
    [self rebuildSetupWindowPreservingVisibility];
}

- (NSString *)displayNameForProfile:(NSDictionary<NSString *, NSString *> *)profile {
    return [profile[@"id"] isEqualToString:@"default"] &&
        [profile[@"name"] isEqualToString:@"Default"]
        ? T(self.language ?: @"en", @"profileDefault")
        : profile[@"name"] ?: @"";
}

- (void)populateProfilePopup {
    [self.profilePopup removeAllItems];
    if (!self.profileStore) {
        [self.profilePopup addItemWithTitle:T(self.language ?: @"en", @"profileDefault")];
        self.profilePopup.enabled = NO;
        self.profileCreateButton.enabled = NO;
        self.profileRenameButton.enabled = NO;
        self.profileDeleteButton.enabled = NO;
        return;
    }
    self.profilePopup.enabled = YES;
    self.profileCreateButton.enabled = YES;
    self.profileRenameButton.enabled = YES;
    NSString *activeID = self.profileStore.activeProfileID;
    for (NSDictionary<NSString *, NSString *> *profile in self.profileStore.profiles) {
        [self.profilePopup addItemWithTitle:[self displayNameForProfile:profile]];
        self.profilePopup.lastItem.representedObject = profile[@"id"];
        if ([profile[@"id"] isEqualToString:activeID]) {
            [self.profilePopup selectItem:self.profilePopup.lastItem];
        }
    }
    self.profileDeleteButton.enabled = self.profileStore.profiles.count > 1;
}

- (void)installProfileControlsInContentView:(NSView *)contentView {
    NSTextField *label = [self label:T(self.language ?: @"en", @"profileLabel")
                                frame:NSMakeRect(34, 88, 124, 22)];
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    label.accessibilityLabel = label.stringValue;
    [contentView addSubview:label];

    self.profilePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 84, 300, 28)];
    self.profilePopup.target = self;
    self.profilePopup.action = @selector(profileSelectionChanged:);
    self.profilePopup.accessibilityRole = NSAccessibilityPopUpButtonRole;
    self.profilePopup.accessibilityLabel = T(self.language ?: @"en", @"profileLabel");
    [contentView addSubview:self.profilePopup];

    NSArray<NSArray *> *actions = @[
        @[@"+", @"profileCreate", NSStringFromSelector(@selector(createProfile:))],
        @[@"✎", @"profileRename", NSStringFromSelector(@selector(renameProfile:))],
        @[@"−", @"profileDelete", NSStringFromSelector(@selector(deleteProfile:))]
    ];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < actions.count; index++) {
        NSButton *button = [self button:actions[index][0]
                                  frame:NSMakeRect(474 + index * 46, 84, 40, 28)
                                 action:NSSelectorFromString(actions[index][2])];
        button.toolTip = T(self.language ?: @"en", actions[index][1]);
        button.accessibilityLabel = button.toolTip;
        button.accessibilityRole = NSAccessibilityButtonRole;
        [contentView addSubview:button];
        [buttons addObject:button];
    }
    self.profileCreateButton = buttons[0];
    self.profileRenameButton = buttons[1];
    self.profileDeleteButton = buttons[2];
    self.profilePopup.nextKeyView = self.profileCreateButton;
    self.profileCreateButton.nextKeyView = self.profileRenameButton;
    self.profileRenameButton.nextKeyView = self.profileDeleteButton;
    [self populateProfilePopup];
}

- (BOOL)activateProfileID:(NSString *)profileID
 discardingUnsavedChanges:(BOOL)discardingUnsavedChanges
                    error:(NSError **)error {
    NSString *currentID = self.profileStore.activeProfileID;
    if ([currentID isEqualToString:profileID]) return YES;
    if ([self hasUnsavedSetupChanges] && !discardingUnsavedChanges) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.commcats.gdrivebackup.profiles"
                                          code:6
                                      userInfo:@{NSLocalizedDescriptionKey:
                                          T(self.language ?: @"en", @"profileUnsavedSwitch")}];
        }
        return NO;
    }
    NSString *currentPath = [self.profileStore configPathForProfileID:currentID];
    NSDictionary<NSString *, NSString *> *currentConfig = currentPath.length
        ? GDTReadConfigDictionaryAtPath(currentPath) : @{};
    NSString *nextPath = [self.profileStore configPathForProfileID:profileID];
    NSDictionary<NSString *, NSString *> *nextConfig = nextPath.length
        ? GDTReadConfigDictionaryAtPath(nextPath) : @{};
    if (![self.profileStore selectProfileID:profileID error:error]) return NO;
    NSString *schedule = nextConfig[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual";
    NSError *scheduleError = nil;
    if (![self applySchedule:schedule error:&scheduleError]) {
        if (currentID.length) {
            [self.profileStore selectProfileID:currentID error:nil];
            [self applySchedule:currentConfig[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" error:nil];
        }
        if (error) *error = scheduleError;
        [self populateProfilePopup];
        return NO;
    }
    [self populateProfilePopup];
    self.statusField.stringValue = T(self.language ?: @"en", @"profileActivated");
    return YES;
}

- (BOOL)confirmDiscardingUnsavedChanges {
    if (![self hasUnsavedSetupChanges]) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(self.language ?: @"en", @"profileUnsavedSwitch");
    [alert addButtonWithTitle:T(self.language ?: @"en", @"discardChanges")];
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancel")];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)reloadSetupForActiveProfile {
    if (!self.setupWindow) return;
    self.setupContextStatusText = nil;
    [self rebuildSetupWindowPreservingVisibility];
}

- (void)profileSelectionChanged:(id)sender {
    (void)sender;
    NSString *profileID = self.profilePopup.selectedItem.representedObject;
    if ([profileID isEqualToString:self.profileStore.activeProfileID]) return;
    BOOL discard = [self confirmDiscardingUnsavedChanges];
    NSError *error = nil;
    if (!discard || ![self activateProfileID:profileID
                       discardingUnsavedChanges:discard error:&error]) {
        [self populateProfilePopup];
        if (error) self.statusField.stringValue = error.localizedDescription;
        return;
    }
    [self reloadSetupForActiveProfile];
}

- (NSString *)promptForProfileNameWithTitleKey:(NSString *)titleKey
                                   initialValue:(NSString *)initialValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(self.language ?: @"en", titleKey);
    alert.informativeText = T(self.language ?: @"en", @"profileNamePrompt");
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 26)];
    field.stringValue = initialValue ?: @"";
    alert.accessoryView = field;
    [alert addButtonWithTitle:T(self.language ?: @"en", @"done")];
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return field.stringValue;
}

- (void)createProfile:(id)sender {
    (void)sender;
    if (![self confirmDiscardingUnsavedChanges]) return;
    NSString *name = [self promptForProfileNameWithTitleKey:@"profileCreate" initialValue:@""];
    if (!name) return;
    NSString *activePath = self.profileStore.activeConfigPath;
    NSDictionary<NSString *, NSString *> *config = activePath.length
        ? GDTReadConfigDictionaryAtPath(activePath) : @{};
    NSError *error = nil;
    NSDictionary *profile = [self.profileStore createProfileNamed:name
                                                    copyingConfig:config error:&error];
    if (!profile || ![self activateProfileID:profile[@"id"]
                       discardingUnsavedChanges:YES error:&error]) {
        self.statusField.stringValue = error.localizedDescription ?: T(self.language, @"diagnosticsFailure");
        [self populateProfilePopup];
        return;
    }
    [self reloadSetupForActiveProfile];
}

- (void)renameProfile:(id)sender {
    (void)sender;
    NSString *activeID = self.profileStore.activeProfileID;
    NSDictionary *active = nil;
    for (NSDictionary *profile in self.profileStore.profiles) {
        if ([profile[@"id"] isEqualToString:activeID]) active = profile;
    }
    NSString *name = [self promptForProfileNameWithTitleKey:@"profileRename"
                                               initialValue:[self displayNameForProfile:active ?: @{}]];
    if (!name) return;
    NSError *error = nil;
    if (![self.profileStore renameProfileID:activeID name:name error:&error]) {
        self.statusField.stringValue = error.localizedDescription ?: T(self.language, @"diagnosticsFailure");
        return;
    }
    [self populateProfilePopup];
}

- (void)deleteProfile:(id)sender {
    (void)sender;
    NSArray<NSDictionary<NSString *, NSString *> *> *profiles = self.profileStore.profiles;
    if (profiles.count <= 1 || ![self confirmDiscardingUnsavedChanges]) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(self.language ?: @"en", @"profileDeleteConfirm");
    [alert addButtonWithTitle:T(self.language ?: @"en", @"profileDelete")];
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *oldID = self.profileStore.activeProfileID;
    NSDictionary *replacement = nil;
    for (NSDictionary *profile in profiles) {
        if (![profile[@"id"] isEqualToString:oldID]) {
            replacement = profile;
            break;
        }
    }
    NSError *error = nil;
    if (![self activateProfileID:replacement[@"id"]
             discardingUnsavedChanges:YES error:&error] ||
        ![self.profileStore deleteProfileID:oldID error:&error]) {
        self.statusField.stringValue = error.localizedDescription ?: T(self.language, @"diagnosticsFailure");
        [self populateProfilePopup];
        return;
    }
    [self reloadSetupForActiveProfile];
}

- (void)installSetupHealthViewInContentView:(NSView *)contentView {
    self.setupHealthView = [[TigerSetupHealthView alloc] initWithFrame:
        NSMakeRect(24, 132, MAX(580, NSWidth(contentView.bounds) - 48), 116)];
    self.setupHealthView.language = self.language ?: @"en";
    __weak typeof(self) weakSelf = self;
    self.setupHealthView.checkHandler = ^{
        [weakSelf runSetupHealthCheck:nil];
    };
    [contentView addSubview:self.setupHealthView];
}

- (void)rebuildSetupWindowPreservingVisibility {
    if (!self.setupWindow) {
        return;
    }
    NSWindow *previousWindow = self.setupWindow;
    BOOL shouldPresent = previousWindow.isVisible || previousWindow.isMiniaturized;
    self.mountedNASRefreshGeneration++;
    self.mountedNASRefreshInFlight = NO;
    self.setupHealthGeneration++;
    self.rebuildingSetupWindow = YES;
    previousWindow.delegate = nil;
    [previousWindow orderOut:nil];
    self.setupWindow = nil;
    if (shouldPresent) {
        [self showSetupWindow];
    }
    [previousWindow close];
    self.rebuildingSetupWindow = NO;
    if (!shouldPresent) {
        [self updateControllerActivationPolicy];
    }
}

- (void)showSetupWindow {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMainMenu];
    [NSApp setApplicationIconImage:CreateApplicationIcon()];

    if (self.setupWindow) {
        [self.setupWindow deminiaturize:nil];
        [self.setupWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }

    NSSize size = NSMakeSize(650, 720);
    NSRect screenFrame = NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame : NSMakeRect(0, 0, 1200, 800);
    NSPoint origin = NSMakePoint(NSMidX(screenFrame) - size.width / 2, NSMidY(screenFrame) - size.height / 2);

    self.setupWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.setupWindow.title = @"GDrive Backup Tiger";
    self.setupWindow.releasedWhenClosed = NO;
    self.setupWindow.delegate = self;
    self.setupWindow.level = NSNormalWindowLevel;
    self.setupWindow.collectionBehavior = NSWindowCollectionBehaviorManaged |
        NSWindowCollectionBehaviorFullScreenNone;

    TigerSetupView *content = [[TigerSetupView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.setupWindow.contentView = content;
    [self installProfileControlsInContentView:content];
    [self installSetupHealthViewInContentView:content];

    NSMutableDictionary<NSString *, NSString *> *config = GDTReadConfigDictionary();
    NSString *configuredTarget = [config[@"GDRIVE_BACKUP_TARGET"] lowercaseString];
    NSString *target = configuredTarget.length ? configuredTarget : @"apfs";
    BOOL preserveConfiguredAPFSTarget = [configuredTarget isEqualToString:@"apfs"];
    NSString *encryption = [config[@"GDRIVE_BACKUP_ENCRYPTION"] ?: @"none" lowercaseString];
    NSString *schedule = [config[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    [self loadConfiguredAPFSIdentityFromConfig:config];

    NSTextField *title = [self label:@"Google Drive Backup" frame:NSMakeRect(26, 16, 300, 22)];
    title.font = [NSFont fontWithName:@"Lucida Grande Bold" size:17] ?: [NSFont boldSystemFontOfSize:17];
    [content addSubview:title];

    NSTextField *subtitle = [self label:T(self.language, @"setupTitle") frame:NSMakeRect(26, 39, 420, 18)];
    subtitle.textColor = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    [content addSubview:subtitle];

    [content addSubview:[self label:T(self.language, @"targetType") frame:NSMakeRect(34, 276, 124, 22)]];
    self.targetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 272, 170, 28)];
    [self.targetPopup addItemWithTitle:T(self.language, @"externalVolume")];
    self.targetPopup.lastItem.representedObject = @"apfs";
    [self.targetPopup addItemWithTitle:T(self.language, @"nas")];
    self.targetPopup.lastItem.representedObject = @"nas";
    [self.targetPopup selectItemAtIndex:[target isEqualToString:@"nas"] ? 1 : 0];
    self.targetPopup.target = self;
    self.targetPopup.action = @selector(targetChanged:);
    [content addSubview:self.targetPopup];

    [content addSubview:[self label:T(self.language, @"destinationPreview") frame:NSMakeRect(34, 310, 124, 22)]];
    self.destinationPreviewField = [self fieldWithFrame:NSMakeRect(164, 306, 440, 26)];
    self.destinationPreviewField.editable = NO;
    self.destinationPreviewField.selectable = YES;
    self.destinationPreviewField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.destinationPreviewField.accessibilityRole = NSAccessibilityStaticTextRole;
    [content addSubview:self.destinationPreviewField];

    [content addSubview:[self label:T(self.language, @"encryptionLabel") frame:NSMakeRect(34, 342, 124, 22)]];
    self.encryptionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 338, 190, 28)];
    NSArray<NSArray<NSString *> *> *encryptionItems = @[
        @[T(self.language, @"encryptionNone"), @"none"],
        @[T(self.language, @"encryptionAPFS"), @"apfs"],
        @[T(self.language, @"encryptionRcloneCrypt"), @"rclone-crypt"]
    ];
    for (NSArray<NSString *> *item in encryptionItems) {
        [self.encryptionPopup addItemWithTitle:item[0]];
        self.encryptionPopup.lastItem.representedObject = item[1];
        if ([encryption isEqualToString:item[1]]) {
            [self.encryptionPopup selectItem:self.encryptionPopup.lastItem];
        }
    }
    self.encryptionPopup.target = self;
    self.encryptionPopup.action = @selector(setupControlChanged:);
    [content addSubview:self.encryptionPopup];

    self.cryptRemoteLabel = [self label:T(self.language, @"cryptRemoteLabel")
                                      frame:NSMakeRect(362, 342, 98, 22)];
    [content addSubview:self.cryptRemoteLabel];
    self.cryptRemoteField = [self fieldWithFrame:NSMakeRect(466, 338, 138, 26)];
    self.cryptRemoteField.stringValue = config[@"GDRIVE_BACKUP_CRYPT_REMOTE"] ?: @"";
    self.cryptRemoteField.delegate = self;
    self.cryptRemoteField.toolTip = T(self.language, @"encryptionRcloneTip");
    self.cryptRemoteField.accessibilityHelp = self.cryptRemoteField.toolTip;
    [content addSubview:self.cryptRemoteField];

    [content addSubview:[self label:T(self.language, @"mountedNas") frame:NSMakeRect(34, 376, 124, 22)]];
    self.mountedNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 372, 300, 28)];
    self.mountedNasPopup.target = self;
    self.mountedNasPopup.action = @selector(selectMountedNAS:);
    [content addSubview:self.mountedNasPopup];
    [content addSubview:[self button:T(self.language, @"refresh") frame:NSMakeRect(474, 372, 130, 28) action:@selector(refreshMountedNAS:)]];

    [content addSubview:[self label:T(self.language, @"nasUrl") frame:NSMakeRect(34, 414, 124, 22)]];
    self.nasURLField = [self fieldWithFrame:NSMakeRect(164, 410, 300, 26)];
    self.nasURLField.stringValue = config[@"GDRIVE_BACKUP_NAS_URL"] ?: @"";
    self.nasURLField.delegate = self;
    [content addSubview:self.nasURLField];
    [content addSubview:[self button:T(self.language, @"openFinder") frame:NSMakeRect(474, 409, 130, 28) action:@selector(openNASInFinder:)]];

    [content addSubview:[self label:T(self.language, @"nasMount") frame:NSMakeRect(34, 450, 124, 22)]];
    self.nasMountField = [self fieldWithFrame:NSMakeRect(164, 446, 300, 26)];
    self.nasMountField.stringValue = config[@"GDRIVE_BACKUP_NAS_MOUNT"] ?: @"";
    self.nasMountField.delegate = self;
    [content addSubview:self.nasMountField];

    [content addSubview:[self label:T(self.language, @"nasSubdir") frame:NSMakeRect(34, 486, 124, 22)]];
    self.nasSubdirField = [self fieldWithFrame:NSMakeRect(164, 482, 300, 26)];
    self.nasSubdirField.stringValue = config[@"GDRIVE_BACKUP_NAS_SUBDIR"] ?: @"GoogleDrive-Backup";
    self.nasSubdirField.delegate = self;
    [content addSubview:self.nasSubdirField];

    self.discoveredNasPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 518, 300, 28)];
    [self.discoveredNasPopup addItemWithTitle:@"Bonjour"];
    self.discoveredNasPopup.target = self;
    self.discoveredNasPopup.action = @selector(selectDiscoveredNAS:);
    [content addSubview:self.discoveredNasPopup];
    [content addSubview:[self button:T(self.language, @"discover") frame:NSMakeRect(474, 518, 130, 28) action:@selector(discoverNAS:)]];

    [content addSubview:[self label:T(self.language, @"schedule") frame:NSMakeRect(34, 580, 124, 22)]];
    self.schedulePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(164, 576, 300, 28)];
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
    self.schedulePopup.target = self;
    self.schedulePopup.action = @selector(setupControlChanged:);
    [content addSubview:self.schedulePopup];

    self.notificationCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(164, 608, 440, 24)];
    self.notificationCheckbox.buttonType = NSButtonTypeSwitch;
    self.notificationCheckbox.title = T(self.language, @"notifyBackupFailures");
    self.notificationCheckbox.state = [config[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"]
        ? NSControlStateValueOff : NSControlStateValueOn;
    self.notificationCheckbox.target = self;
    self.notificationCheckbox.action = @selector(setupControlChanged:);
    self.notificationCheckbox.accessibilityLabel = self.notificationCheckbox.title;
    [content addSubview:self.notificationCheckbox];

    self.successNotificationCheckbox = [[NSButton alloc]
        initWithFrame:NSMakeRect(164, 636, 440, 24)];
    self.successNotificationCheckbox.buttonType = NSButtonTypeSwitch;
    self.successNotificationCheckbox.title = T(self.language, @"notifyBackupSuccesses");
    self.successNotificationCheckbox.state =
        [config[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"1"]
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.successNotificationCheckbox.target = self;
    self.successNotificationCheckbox.action = @selector(setupControlChanged:);
    self.successNotificationCheckbox.accessibilityLabel =
        self.successNotificationCheckbox.title;
    [content addSubview:self.successNotificationCheckbox];
    [self updateNotificationControlAvailability];

    self.statusField = [self label:T(self.language, @"statusReady") frame:NSMakeRect(26, 678, 270, 20)];
    self.statusField.textColor = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    [content addSubview:self.statusField];

    NSButton *saveButton = [self button:T(self.language, @"save") frame:NSMakeRect(312, 673, 88, 30) action:@selector(saveSetup:)];
    self.setupDryRunButton = [self button:T(self.language, @"dryRun") frame:NSMakeRect(408, 673, 112, 30) action:@selector(startDryRun:)];
    self.setupDryRunButton.toolTip = T(self.language, @"dryRunTip");
    self.setupBackupButton = [self button:T(self.language, @"backupNow") frame:NSMakeRect(528, 673, 96, 30) action:@selector(startBackupNow:)];
    self.setupBackupButton.toolTip = T(self.language, @"backupNowTip");
    [content addSubview:saveButton];
    [content addSubview:self.setupDryRunButton];
    [content addSubview:self.setupBackupButton];
    [self updateSetupActionAvailability];

    [self.setupWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshMountedNASAllowingTargetAutoSelection:!preserveConfiguredAPFSTarget];
}

- (void)targetChanged:(id)sender {
    (void)sender;
    [self updateTargetControls];
}

- (void)setupControlChanged:(id)sender {
    (void)sender;
    [self updateEncryptionControls];
    [self updateDestinationPreview];
    [self updateNotificationControlAvailability];
    [self invalidateSetupHealth:nil];
}

- (void)updateNotificationControlAvailability {
    NSString *schedule = self.schedulePopup.selectedItem.representedObject ?: @"manual";
    BOOL automaticSchedule = [@[@"login", @"hourly", @"daily"] containsObject:schedule];
    self.notificationCheckbox.enabled = automaticSchedule;
    self.successNotificationCheckbox.enabled = automaticSchedule;
}

- (void)updateEncryptionControls {
    NSString *target = self.targetPopup.selectedItem.representedObject ?: @"apfs";
    NSString *encryption = self.encryptionPopup.selectedItem.representedObject ?: @"none";
    BOOL isAPFSTarget = [target isEqualToString:@"apfs"];
    BOOL usesRcloneCrypt = [encryption isEqualToString:@"rclone-crypt"];
    NSMenuItem *apfsItem = nil;
    for (NSMenuItem *item in self.encryptionPopup.itemArray) {
        if ([item.representedObject isEqualToString:@"apfs"]) {
            apfsItem = item;
            break;
        }
    }
    apfsItem.enabled = isAPFSTarget;
    self.cryptRemoteLabel.hidden = !usesRcloneCrypt;
    self.cryptRemoteField.hidden = !usesRcloneCrypt;
    self.cryptRemoteField.enabled = usesRcloneCrypt;
    self.encryptionPopup.toolTip = [encryption isEqualToString:@"apfs"]
        ? T(self.language ?: @"en", @"encryptionAPFSTip")
        : (usesRcloneCrypt ? T(self.language ?: @"en", @"encryptionRcloneTip") : @"");
    self.encryptionPopup.accessibilityHelp = self.encryptionPopup.toolTip;
}

- (void)updateTargetControls {
    [self updateEncryptionControls];
    [self updateDestinationPreview];
    [self invalidateSetupHealth:nil];
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
    [self invalidateSetupHealth:nil];
}

- (void)refreshMountedNAS:(id)sender {
    (void)sender;
    [self refreshMountedNASAllowingTargetAutoSelection:YES];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)mountedNetworkVolumes {
    return MountedNetworkVolumes();
}

- (void)completeMountedNetworkVolumeDiscovery:
    (NSArray<NSDictionary<NSString *, NSString *> *> *)volumes
    generation:(NSUInteger)generation
    allowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
    if (generation != self.mountedNASRefreshGeneration) {
        return;
    }
    self.mountedNASRefreshInFlight = NO;
    if (!self.setupWindow || !self.mountedNasPopup) {
        return;
    }
    [self applyMountedNetworkVolumes:volumes
         allowingTargetAutoSelection:allowAutomaticTargetSelection];
}

- (void)refreshMountedNASAllowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
    if (!self.mountedNasPopup || self.mountedNASRefreshInFlight) {
        return;
    }
    self.mountedNASRefreshInFlight = YES;
    NSUInteger generation = ++self.mountedNASRefreshGeneration;
    [self.mountedNasPopup removeAllItems];
    [self.mountedNasPopup addItemWithTitle:T(self.language, @"selectMountedVolume")];
    self.mountedNasPopup.lastItem.representedObject = @{};
    self.mountedNasPopup.enabled = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSArray<NSDictionary<NSString *, NSString *> *> *volumes =
            [strongSelf mountedNetworkVolumes];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            [innerSelf completeMountedNetworkVolumeDiscovery:volumes
                                                  generation:generation
                                allowingTargetAutoSelection:allowAutomaticTargetSelection];
        });
    });
}

- (void)applyMountedNetworkVolumes:
    (NSArray<NSDictionary<NSString *, NSString *> *> *)volumes
    allowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
    self.mountedNasPopup.enabled = YES;
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
    NSString *encryption = self.encryptionPopup.selectedItem.representedObject ?: @"none";
    NSMutableDictionary<NSString *, NSString *> *updates = [NSMutableDictionary dictionary];
    updates[@"GDRIVE_BACKUP_TARGET"] = target;
    updates[@"GDRIVE_BACKUP_SCHEDULE"] = schedule;
    updates[@"GDRIVE_BACKUP_ENCRYPTION"] = encryption;
    updates[@"GDRIVE_BACKUP_CRYPT_REMOTE"] = self.cryptRemoteField.stringValue ?: @"";
    updates[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] =
        self.notificationCheckbox.state == NSControlStateValueOff ? @"0" : @"1";
    updates[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] =
        self.successNotificationCheckbox.state == NSControlStateValueOff ? @"0" : @"1";

    if ([target isEqualToString:@"nas"]) {
        updates[@"GDRIVE_BACKUP_NAS_MOUNT"] = self.nasMountField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_URL"] = self.nasURLField.stringValue ?: @"";
        updates[@"GDRIVE_BACKUP_NAS_SUBDIR"] = self.nasSubdirField.stringValue.length ? self.nasSubdirField.stringValue : @"GoogleDrive-Backup";
        updates[@"GDRIVE_BACKUP_NAS_START_ON_MOUNT"] = @"0";
    }

    NSString *externalVolumePath = self.configuredAPFSVolumePath.length
        ? self.configuredAPFSVolumePath
        : ([target isEqualToString:@"apfs"] ? @"/Volumes/GoogleDrive-Backup" : @"");
    if (externalVolumePath.length) {
        updates[@"GDRIVE_BACKUP_VOLUME"] = externalVolumePath;
        updates[@"GDRIVE_BACKUP_VOLUME_NAME"] =
            externalVolumePath.lastPathComponent ?: @"GoogleDrive-Backup";
    }
    if (self.configuredAPFSVolumeUUID.length) {
        updates[@"GDRIVE_BACKUP_VOLUME_UUID"] =
            self.configuredAPFSVolumeUUID;
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
        @"GDRIVE_BACKUP_CRYPT_REMOTE": @"",
        @"GDRIVE_BACKUP_NAS_MOUNT": @"",
        @"GDRIVE_BACKUP_NAS_URL": @"",
        @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
        @"GDRIVE_BACKUP_NAS_START_ON_MOUNT": @"0",
        @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
        @"GDRIVE_BACKUP_VOLUME_NAME": @"GoogleDrive-Backup",
        @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"1",
        @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"0"
    };
    NSSet<NSString *> *caseInsensitiveKeys = [NSSet setWithArray:@[
        @"GDRIVE_BACKUP_TARGET", @"GDRIVE_BACKUP_SCHEDULE", @"GDRIVE_BACKUP_ENCRYPTION"
    ]];
    for (NSString *key in updates) {
        NSString *current = updates[key] ?: @"";
        NSString *saved = savedConfig[key] ?: defaults[key] ?: @"";
        if ([key isEqualToString:@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] &&
            ![@[@"0", @"1"] containsObject:saved]) {
            saved = @"0";
        }
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

- (NSString *)setupValidationErrorKeyForUpdates:
    (NSDictionary<NSString *, NSString *> *)updates {
    NSString *target = [updates[@"GDRIVE_BACKUP_TARGET"] ?: @"apfs" lowercaseString];
    NSString *encryption = [updates[@"GDRIVE_BACKUP_ENCRYPTION"] ?: @"none" lowercaseString];
    if (![@[@"apfs", @"nas"] containsObject:target] ||
        ![@[@"none", @"apfs", @"rclone-crypt"] containsObject:encryption] ||
        ([encryption isEqualToString:@"apfs"] && ![target isEqualToString:@"apfs"])) {
        return @"statusEncryptionIncompatible";
    }
    if ([encryption isEqualToString:@"rclone-crypt"]) {
        NSString *remote = updates[@"GDRIVE_BACKUP_CRYPT_REMOTE"] ?: @"";
        NSRegularExpression *expression = [NSRegularExpression
            regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
                                 options:0 error:nil];
        BOOL safeRemote = [expression numberOfMatchesInString:remote options:0
            range:NSMakeRange(0, remote.length)] == 1;
        NSString *sourceRemote = updates[@"RCLONE_REMOTE"] ?: @"";
        while ([sourceRemote hasSuffix:@":"]) {
            sourceRemote = [sourceRemote substringToIndex:sourceRemote.length - 1];
        }
        if (!safeRemote || (sourceRemote.length && [remote isEqualToString:sourceRemote])) {
            return @"statusCryptRemoteInvalid";
        }
    }
    return nil;
}

- (BOOL)saveSetupValues {
    NSDictionary<NSString *, NSString *> *updates = [self currentSetupUpdates];
    NSMutableDictionary<NSString *, NSString *> *validationUpdates = [updates mutableCopy];
    validationUpdates[@"RCLONE_REMOTE"] = [self savedSetupConfig][@"RCLONE_REMOTE"] ?: @"gdrive";
    NSString *validationErrorKey = [self setupValidationErrorKeyForUpdates:validationUpdates];
    if (validationErrorKey.length) {
        self.statusField.stringValue = T(self.language ?: @"en", validationErrorKey);
        return NO;
    }
    NSError *error = nil;
    if (!GDTWriteConfigUpdates(updates, &error)) {
        self.statusField.stringValue = error.localizedDescription ?: @"Save failed.";
        return NO;
    }
    if (![self applySchedule:self.schedulePopup.selectedItem.representedObject ?: @"manual" error:&error]) {
        self.statusField.stringValue = error.localizedDescription ?: @"Schedule update failed.";
        return NO;
    }
    NSDictionary<NSString *, NSString *> *savedConfig = GDTReadConfigDictionary();
    [self configureBackupNotificationsForConfig:savedConfig];
    NSString *savedSchedule =
        [savedConfig[@"GDRIVE_BACKUP_SCHEDULE"] ?: @"manual" lowercaseString];
    BOOL automaticSchedule =
        [@[@"login", @"hourly", @"daily"] containsObject:savedSchedule];
    BOOL failureNotificationsEnabled =
        ![savedConfig[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"0"];
    BOOL routineSuccessNotificationsEnabled =
        [savedConfig[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"1"];
    if (automaticSchedule &&
        (failureNotificationsEnabled || routineSuccessNotificationsEnabled)) {
        [self requestBackupNotificationAuthorizationIfNeededForConfig:savedConfig];
    } else {
        // This prompt follows an explicit Save in setup; a disk mount itself
        // never opens a permission sheet or steals focus.
        [self requestUnknownExternalVolumeNotificationAuthorizationIfNeeded];
    }
    self.setupContextStatusText = nil;
    self.statusField.stringValue = T(self.language, @"statusSaved");
    return YES;
}

- (void)saveSetup:(id)sender {
    [self saveSetupValues];
}

- (NSDictionary<NSString *, id> *)unknownSetupHealthSnapshot {
    return @{
        @"dependencies": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"},
        @"remote": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"},
        @"destination": @{@"status": @"unknown", @"detailKey": @"setupCheckNotRun"}
    };
}

- (void)invalidateSetupHealth:(id)sender {
    (void)sender;
    self.setupHealthGeneration++;
    if (self.setupHealthCheckInFlight) {
        return;
    }
    [self.setupHealthView applySnapshot:[self unknownSetupHealthSnapshot]];
    self.statusField.stringValue = self.setupContextStatusText ?:
        T(self.language ?: @"en", @"setupCheckNotRun");
}

- (void)completeSetupHealthCheck:(NSDictionary<NSString *, id> *)snapshot
                      generation:(NSUInteger)generation {
    self.setupHealthCheckInFlight = NO;
    self.setupHealthView.checking = NO;
    if (generation == self.setupHealthGeneration) {
        [self.setupHealthView applySnapshot:snapshot ?: @{}];
        BOOL ready = [snapshot[@"overall"] isEqualToString:@"ready"];
        self.statusField.stringValue = self.setupContextStatusText ?:
            T(self.language ?: @"en",
              ready ? @"setupCheckReady" : @"setupCheckNeedsAttention");
    } else {
        [self.setupHealthView applySnapshot:[self unknownSetupHealthSnapshot]];
        self.statusField.stringValue = self.setupContextStatusText ?:
            T(self.language ?: @"en", @"setupCheckNotRun");
    }
    [self updateSetupActionAvailability];
}

- (void)completeSetupHealthCheck:(NSDictionary<NSString *, id> *)snapshot {
    [self completeSetupHealthCheck:snapshot generation:self.setupHealthGeneration];
}

- (void)runSetupHealthCheck:(id)sender {
    (void)sender;
    if (self.setupHealthCheckInFlight) {
        return;
    }
    self.setupHealthCheckInFlight = YES;
    self.setupHealthView.checking = YES;
    [self updateSetupActionAvailability];

    if (!self.setupHealthChecker) {
        self.setupHealthChecker = [GDTSetupHealthChecker productionChecker];
    }
    GDTSetupHealthChecker *checker = self.setupHealthChecker;
    NSMutableDictionary<NSString *, NSString *> *config = [[self savedSetupConfig] mutableCopy];
    [config addEntriesFromDictionary:[self currentSetupUpdates]];
    NSUInteger generation = self.setupHealthGeneration;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, id> *snapshot = [checker snapshotForConfig:config];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf completeSetupHealthCheck:snapshot generation:generation];
        });
    });
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
    [self updateSetupActionAvailability];
    self.statusField.stringValue = T(self.language, @"statusBackupPreparing");
    if (![self launchBackupWithArgument:@"--run" trigger:@"setup" assumeYes:YES]) {
        self.manualLaunchPending = NO;
        [self updateSetupActionAvailability];
        return;
    }
    [self dismissSetupAfterBackupLaunch];
}

- (void)dismissSetupAfterBackupLaunch {
    [self.setupWindow orderOut:nil];
    if (self.overviewMode) {
        self.manualLaunchPending = NO;
        [self updateSetupActionAvailability];
        [self handoffOverviewDockPresenceToManualProgress];
        return;
    }
    [NSApp terminate:nil];
}

- (void)startDryRun:(id)sender {
    (void)sender;
    if (self.dryRunPending) {
        return;
    }
    if ([self hasUnsavedSetupChanges]) {
        self.statusField.stringValue = T(self.language, @"statusUnsavedChanges");
        return;
    }
    self.dryRunPending = YES;
    self.statusField.stringValue = T(self.language, @"statusDryRunStarted");
    [self updateSetupActionAvailability];
    __weak typeof(self) weakSelf = self;
    if (![self launchBackupWithArgument:@"--dry-run"
                              assumeYes:YES
                             completion:^(NSInteger terminationStatus) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.dryRunPending = NO;
        NSString *resultKey = terminationStatus == 0
            ? @"statusDryRunSucceeded"
            : (terminationStatus == 69
                ? @"statusDryRunTargetUnavailable" : @"statusDryRunFailed");
        strongSelf.statusField.stringValue = T(strongSelf.language ?: @"en", resultKey);
        [strongSelf updateSetupActionAvailability];
    }]) {
        self.dryRunPending = NO;
        [self updateSetupActionAvailability];
    }
}

- (void)updateSetupActionAvailability {
    BOOL busy = self.manualLaunchPending || self.dryRunPending || self.setupHealthCheckInFlight;
    self.setupBackupButton.enabled = !busy;
    self.setupDryRunButton.enabled = !busy;
    self.setupDryRunButton.title = T(self.language ?: @"en",
        self.dryRunPending ? @"dryRunRunning" : @"dryRun");
}

- (BOOL)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    return [self launchBackupWithArgument:argument
                                  trigger:@"manual"
                                assumeYes:assumeYes
                               completion:nil];
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                       assumeYes:(BOOL)assumeYes
                      completion:(void (^)(NSInteger status))completion {
    return [self launchBackupWithArgument:argument
                                  trigger:@"manual"
                                assumeYes:assumeYes
                               completion:completion];
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes {
    return [self launchBackupWithArgument:argument
                                  trigger:trigger
                                assumeYes:assumeYes
                               completion:nil];
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes
                      completion:(void (^)(NSInteger status))completion {
    return [self launchBackupWithArgument:argument
                                  trigger:trigger
                                assumeYes:assumeYes
                    additionalEnvironment:nil
                               completion:completion];
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes
           additionalEnvironment:(NSDictionary<NSString *, NSString *> *)additionalEnvironment
                      completion:(void (^)(NSInteger status))completion {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"/usr/local/bin/backup-google-drive.sh", argument];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"HOME"] = NSHomeDirectory();
    environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    environment[@"GDRIVE_BACKUP_TRIGGER"] = trigger.length ? trigger : @"manual";
    BOOL actionWindowVisible = self.setupWindow.isVisible || self.window.isVisible;
    environment[@"BACKUP_PROGRESS_FOREGROUND"] = [self shouldShowProgressForTrigger:trigger
        fromVisibleWindow:actionWindowVisible] ? @"1" : @"0";
    if (assumeYes) {
        environment[@"BACKUP_ASSUME_YES"] = @"1";
    }
    [environment addEntriesFromDictionary:additionalEnvironment ?: @{}];
    task.environment = environment;
    if (completion) {
        task.terminationHandler = ^(NSTask *finishedTask) {
            NSInteger status = finishedTask.terminationStatus;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(status);
            });
        };
    }
    @try {
        [task launch];
        return YES;
    } @catch (NSException *exception) {
        self.statusField.stringValue = exception.reason ?: @"Launch failed.";
        return NO;
    }
}

- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision {
    __weak typeof(self) weakSelf = self;
    return [self launchAutomaticRetryDecision:decision completion:^(NSInteger status) {
        (void)status;
        [weakSelf refreshOverviewStatus:nil];
    }];
}

- (BOOL)launchAutomaticRetryDecision:(NSDictionary<NSString *, NSString *> *)decision
                           completion:(void (^)(NSInteger status))completion {
    NSString *origin = decision[@"originStartedAt"];
    NSString *attempt = decision[@"attempt"];
    if (!origin.length || ![attempt isEqualToString:@"1"]) {
        return NO;
    }
    return [self launchBackupWithArgument:@"--run"
                                  trigger:@"schedule-retry"
                                assumeYes:YES
                    additionalEnvironment:@{
                        @"GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT": origin,
                        @"GDRIVE_BACKUP_RETRY_ATTEMPT": attempt
                    }
                               completion:completion];
}

- (NSData *)schedulePlistDataForMode:(NSString *)mode error:(NSError **)error {
    NSMutableDictionary<NSString *, id> *plist = [@{
        @"Label": @"com.commcats.gdrivebackup.schedule",
        @"ProgramArguments": @[@"/bin/bash", @"/usr/local/bin/backup-google-drive.sh", @"--run"],
        @"EnvironmentVariables": @{
            @"HOME": NSHomeDirectory(),
            @"PATH": @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            @"GDRIVE_BACKUP_TRIGGER": @"schedule",
            // A scheduled job has no attentive user; the script still verifies
            // that the configured destination is the expected mounted target.
            @"BACKUP_ASSUME_YES": @"1"
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

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.voiceOverEnabled = NSWorkspace.sharedWorkspace.isVoiceOverEnabled;
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
             selector:@selector(accessibilityDisplayOptionsChanged:)
               name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
             object:nil];
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSString *mode = [self applicationModeForArguments:arguments];
    self.progressForegroundMode = [self shouldForegroundProgressForArguments:arguments];
    if ([self shouldInstallStatusItemForMode:mode] || [mode isEqualToString:@"setup"]) {
        [self prepareProfileStore];
    }
    self.language = ConfiguredLanguage();
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
               selector:@selector(workspaceVolumeDidUnmount:)
                   name:NSWorkspaceDidUnmountNotification
                 object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter
            addObserver:self
               selector:@selector(refreshOverviewStatus:)
                   name:NSWorkspaceDidWakeNotification
                 object:nil];
        [NSApp setApplicationIconImage:CreateApplicationIcon()];
        [NSApp setActivationPolicy:self.menubarOnlyMode
            ? NSApplicationActivationPolicyAccessory
            : NSApplicationActivationPolicyRegular];
        [self buildMainMenu];
        [self configureBackupNotificationsForConfig:GDTReadConfigDictionary()];
        [self primeMountedExternalVolumeCache];
        [self installStatusItemIfNeeded];
        if ([mode isEqualToString:@"overview"]) {
            self.updateConsentRequested = YES;
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
    [NSApp setActivationPolicy:self.progressForegroundMode
        ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];

    NSSize size = self.confirmMode ? NSMakeSize(392, 180) : NSMakeSize(392, 198);
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
    self.window.collectionBehavior = [self statusWindowCollectionBehavior];
    self.window.hidesOnDeactivate = [self statusWindowShouldHideOnDeactivate];
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
    contentView.cancelHandler = ^{
        [weakSelf requestCancelBackup:nil];
    };
    self.window.contentView = contentView;
    self.window.alphaValue = 0;
    if (self.confirmMode && self.progressForegroundMode) {
        [self.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    } else {
        [self.window orderFront:nil];
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = [self animationDuration:0.22];
        self.window.animator.alphaValue = 1;
    } completionHandler:nil];

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
    return self.setupMode && !self.overviewMode && !self.rebuildingSetupWindow;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender == self.setupWindow) {
        if (self.overviewMode) {
            [self.setupWindow orderOut:nil];
            [self updateControllerActivationPolicy];
            return NO;
        }
        return YES;
    }
    if (sender == self.restoreWindow) {
        self.restoreLoadGeneration++;
        return YES;
    }
    if (sender == self.diagnosticsWindow) {
        self.diagnosticsGeneration++;
        self.diagnosticsView.loading = NO;
        return YES;
    }
    if (self.overviewMode) {
        [self.window orderOut:nil];
        [self updateControllerActivationPolicy];
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

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *closingWindow = notification.object;
    if (closingWindow == self.restoreWindow) {
        self.restoreWindow = nil;
        self.restoreView = nil;
        self.restoreCatalog = nil;
        self.restoreCopier = nil;
    } else if (closingWindow == self.diagnosticsWindow) {
        self.diagnosticsWindow = nil;
        self.diagnosticsView = nil;
    } else if (closingWindow == self.setupWindow) {
        self.setupWindow = nil;
    }
    if (self.overviewMode) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateControllerActivationPolicy];
        });
    }
}

- (BOOL)windowShouldMiniaturize:(NSWindow *)window {
    if (window == self.restoreWindow || window == self.diagnosticsWindow) {
        return YES;
    }
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
        [self.window makeKeyAndOrderFront:nil];
        return NO;
    }

    if ((self.setupWindow && self.setupWindow.isMiniaturized) ||
        (self.setupMode && (!self.setupWindow || !flag))) {
        [self showSetupWindow];
        return NO;
    }

    if (self.overviewMode && (self.menubarOnlyMode || !self.window || !flag)) {
        self.updateConsentRequested = YES;
        [self showOverviewWindow];
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

- (void)requestCancelBackup:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = T(self.language ?: @"en", @"cancelBackupConfirm");
    alert.informativeText = T(self.language ?: @"en", @"cancelBackupDetail");
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancelBackupAction")];
    [alert addButtonWithTitle:T(self.language ?: @"en", @"cancel")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [weakSelf cancelRunningBackup];
        }
    }];
}

- (BOOL)cancelRunningBackup {
    NSString *sentinel = [NSString stringWithContentsOfFile:self.sentinelPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    NSString *pidText = [sentinel
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!pidText.length ||
        [pidText rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound ||
        pidText.integerValue <= 0) {
        return NO;
    }

    NSDictionary<NSString *, NSString *> *state = [self parseProgressContent:
        [NSString stringWithContentsOfFile:self.runStatePath encoding:NSUTF8StringEncoding error:nil] ?: @""];
    if (![state[@"protocol"] isEqualToString:@"1"] ||
        ![state[@"status"] isEqualToString:@"running"] ||
        state[@"exit_code"].length ||
        ![state[@"pid"] isEqualToString:pidText]) {
        return NO;
    }

    pid_t pid = (pid_t)pidText.intValue;
    errno = 0;
    if (getpgid(pid) != pid || (kill(pid, 0) != 0 && errno != EPERM)) {
        return NO;
    }
    if (kill(-pid, SIGTERM) != 0) {
        return NO;
    }

    if ([self.window.contentView isKindOfClass:TigerBackupView.class]) {
        TigerBackupView *contentView = (TigerBackupView *)self.window.contentView;
        contentView.cancelButton.enabled = NO;
        contentView.progressTitle = T(self.language ?: @"en", @"cancellingBackup");
    }
    return YES;
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
    NSSet<NSString *> *safeReasons = [NSSet setWithArray:@[
        @"destination_permission_denied",
        @"nas_connection_lost",
        @"nas_mount_unavailable",
        @"nas_mount_not_ready"
    ]];
    return [safeReasons containsObject:reason] ? reason : @"";
}

- (NSString *)localizedTerminalDetailForReason:(NSString *)reason {
    if ([reason isEqualToString:@"destination_permission_denied"]) {
        return T(self.language ?: @"en", @"failedPermissionHint");
    }
    if ([reason isEqualToString:@"nas_connection_lost"]) {
        return T(self.language ?: @"en", @"failedNASConnectionHint");
    }
    if ([reason isEqualToString:@"nas_mount_unavailable"] ||
        [reason isEqualToString:@"nas_mount_not_ready"]) {
        return T(self.language ?: @"en", @"backupNotificationNASRetryBody");
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
    } else {
        contentView.progressTitle = nil;
    }

    contentView.progressDetail = GDTLocalizedProgressDetail(values, self.language ?: @"en");

    NSString *percent = values[@"percent"];
    contentView.progressPercent = percent.length
        ? MAX(0.0, MIN(100.0, percent.doubleValue)) : -1.0;

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

    if (self.hiddenByUser || !self.window.isVisible || !NSApp.isActive) {
        [NSApp terminate:nil];
        return;
    }
    self.window.alphaValue = 1;

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

        BOOL handledNetworkMountCommand = NO;
        int networkMountResult = GDTHandleNetworkMountCLIArguments(
            NSProcessInfo.processInfo.arguments,
            ^int(NSString *urlString, BOOL authorizeCredential) {
                return authorizeCredential
                    ? GDTAuthorizeSMBCredentialForURL(urlString)
                    : GDTMountSMBURLFromKeychain(urlString);
            },
            &handledNetworkMountCommand);
        if (handledNetworkMountCommand) {
            if (networkMountResult != 0) {
                fprintf(stderr, "Network mount command failed (%d).\n",
                        networkMountResult);
            }
            return networkMountResult;
        }

        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
