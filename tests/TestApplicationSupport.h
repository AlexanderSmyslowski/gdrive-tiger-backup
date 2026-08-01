#ifndef GDT_TEST_APPLICATION_SUPPORT_H
#define GDT_TEST_APPLICATION_SUPPORT_H

#import <Cocoa/Cocoa.h>

static inline NSApplication *GDTInitializeAccessoryTestApplication(void) {
    // Unbundled test executables never enter the product delegate lifecycle,
    // so they must opt out of Dock presence as soon as AppKit is initialized.
    NSApplication *application = NSApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
    return application;
}

#endif
