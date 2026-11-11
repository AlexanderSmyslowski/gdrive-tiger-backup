#import <Cocoa/Cocoa.h>

#import "TestApplicationSupport.h"

int main(void) {
    @autoreleasepool {
        NSApplication *application = GDTInitializeAccessoryTestApplication();
        BOOL startedWithoutDockPresence =
            application.activationPolicy == NSApplicationActivationPolicyAccessory;

        // Product methods deliberately switch to Regular when a real window
        // needs a Dock icon. A test process must absorb that transition.
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        BOOL remainedWithoutDockPresence =
            application.activationPolicy == NSApplicationActivationPolicyAccessory;

        if (!startedWithoutDockPresence || !remainedWithoutDockPresence) {
            fprintf(stderr, "test application became a regular Dock application\n");
            return 1;
        }
        printf("ok - UI test application remains absent from the Dock\n");
    }
    return 0;
}
