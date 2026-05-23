#import <Cocoa/Cocoa.h>

static NSImage *CreateIcon(CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    CGFloat scale = size / 128.0;
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:scale];
    [transform concat];

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

static BOOL WritePNG(NSImage *image, NSString *path) {
    NSRect rect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cgImage = [image CGImageForProposedRect:&rect context:nil hints:nil];
    if (!cgImage) {
        return NO;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [data writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: IconGenerator <AppIcon.iconset>\n");
            return 64;
        }

        NSString *iconset = [NSString stringWithUTF8String:argv[1]];
        NSFileManager *fileManager = NSFileManager.defaultManager;
        [fileManager createDirectoryAtPath:iconset withIntermediateDirectories:YES attributes:nil error:nil];

        NSDictionary<NSString *, NSNumber *> *icons = @{
            @"icon_16x16.png": @16,
            @"icon_16x16@2x.png": @32,
            @"icon_32x32.png": @32,
            @"icon_32x32@2x.png": @64,
            @"icon_128x128.png": @128,
            @"icon_128x128@2x.png": @256,
            @"icon_256x256.png": @256,
            @"icon_256x256@2x.png": @512,
            @"icon_512x512.png": @512,
            @"icon_512x512@2x.png": @1024
        };

        for (NSString *filename in icons) {
            NSString *path = [iconset stringByAppendingPathComponent:filename];
            if (!WritePNG(CreateIcon(icons[filename].doubleValue), path)) {
                fprintf(stderr, "failed to write %s\n", path.UTF8String);
                return 1;
            }
        }
    }

    return 0;
}
