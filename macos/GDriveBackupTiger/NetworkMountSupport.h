#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSData * _Nullable (^GDTNASCredentialLookup)(
    NSString *host,
    NSString *account,
    NSString *path,
    BOOL allowUserInteraction);
typedef int (^GDTNASMountOperation)(
    NSURL *url,
    NSString *account,
    NSData *passwordData);
typedef int (^GDTNetworkMountCLIHandler)(
    NSString *urlString,
    BOOL authorizeCredential);
typedef int (^GDTLegacyKeychainInteractionSetter)(BOOL allowInteraction);

FOUNDATION_EXPORT int GDTHandleSMBURLWithHandlers(
    NSString *urlString,
    BOOL allowCredentialUI,
    BOOL performMount,
    GDTNASCredentialLookup credentialLookup,
    GDTNASMountOperation _Nullable mountOperation);
FOUNDATION_EXPORT int GDTAuthorizeSMBCredentialForURL(NSString *urlString);
FOUNDATION_EXPORT int GDTMountSMBURLFromKeychain(NSString *urlString);
FOUNDATION_EXPORT int GDTHandleNetworkMountCLIArguments(
    NSArray<NSString *> *arguments,
    GDTNetworkMountCLIHandler handler,
    BOOL * _Nullable handled);
FOUNDATION_EXPORT BOOL GDTConfigureLegacyKeychainInteraction(
    BOOL allowInteraction,
    GDTLegacyKeychainInteractionSetter setter);

NS_ASSUME_NONNULL_END
