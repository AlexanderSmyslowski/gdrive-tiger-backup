#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GDTUpdateDataCompletion)(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error);
typedef void (^GDTUpdateDataLoader)(NSURLRequest *request,
                                    GDTUpdateDataCompletion completion);

@interface GDTUpdateChecker : NSObject <NSURLSessionTaskDelegate>

@property(nonatomic, copy) GDTUpdateDataLoader dataLoader;

+ (NSDictionary<NSString *, NSString *> *)resultForResponseData:(NSData *)data
                                                    responseURL:(NSURL *)responseURL
                                                 currentVersion:(NSString *)currentVersion;
- (void)checkCurrentVersion:(NSString *)currentVersion
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *result))completion;

@end

// Installing an update. Every step fails closed:
// - assets come only from this repository's release of exactly that version,
//   over HTTPS, with redirects only to GitHub's release asset hosts;
// - the package must match the SHA-256 listed in the same release's
//   SHA256SUMS.txt and contain this app;
// - once the project signs its packages (GDTUpdateTrustedTeamID set), the
//   package must carry a Developer ID signature from that team.
FOUNDATION_EXPORT NSString * const GDTUpdateTrustedTeamID;
FOUNDATION_EXPORT NSString *GDTUpdatePackageName(NSString *version);
FOUNDATION_EXPORT NSURL * _Nullable GDTUpdateAssetURL(NSString *version, NSString *name);
FOUNDATION_EXPORT BOOL GDTTrustedUpdateDownloadURL(NSURL * _Nullable url);
FOUNDATION_EXPORT NSString * _Nullable GDTExpectedSHA256(NSString *sums, NSString *fileName);
FOUNDATION_EXPORT NSString * _Nullable GDTSHA256OfFile(NSString *path);
// Signature check output of `pkgutil --check-signature`: nil when acceptable,
// otherwise a reason ("unsigned", "untrusted_signature").
FOUNDATION_EXPORT NSString * _Nullable GDTUpdateSignatureProblem(int status, NSString *output,
                                                                 NSString *trustedTeamID);

typedef void (^GDTUpdateDownloadCompletion)(NSString * _Nullable packagePath,
                                            NSString * _Nullable failureReason);

@interface GDTUpdateDownloader : NSObject <NSURLSessionTaskDelegate>
// Downloads SHA256SUMS.txt and the package into `directory` (created 0700)
// and verifies the checksum. The completion runs on an arbitrary queue.
- (void)downloadVersion:(NSString *)version
            toDirectory:(NSString *)directory
             completion:(GDTUpdateDownloadCompletion)completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
