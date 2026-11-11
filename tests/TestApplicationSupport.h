#ifndef GDT_TEST_APPLICATION_SUPPORT_H
#define GDT_TEST_APPLICATION_SUPPORT_H

#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

@interface GDTAccessoryTestApplication : NSApplication
@end

@implementation GDTAccessoryTestApplication

- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)activationPolicy {
    (void)activationPolicy;
    return [super setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

@end

static inline NSApplication *GDTInitializeAccessoryTestApplication(void) {
    // An unbundled executable is initially registered as a foreground app.
    // Transform it before AppKit checks in, then prevent product code exercised
    // by the test from promoting the harness back into the Dock.
    ProcessSerialNumber process = {0, kCurrentProcess};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TransformProcessType(&process, kProcessTransformToUIElementApplication);
#pragma clang diagnostic pop
    NSApplication *application = GDTAccessoryTestApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
    return application;
}

#endif
