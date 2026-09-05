#import "UpdateSupport.h"
#import <math.h>

static NSString * const GDTUpdateAPIURLString =
    @"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest";
static NSString * const GDTUpdateReleaseURLString =
    @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest";
static NSUInteger const GDTMaximumUpdateResponseBytes = 256 * 1024;

static NSDictionary<NSString *, NSString *> *GDTUnavailableUpdateResult(NSString *reason) {
    return @{ @"reason": reason, @"status": @"unavailable" };
}

static NSArray<NSNumber *> *GDTVersionComponents(NSString *version) {
    if (![version isKindOfClass:NSString.class]) return nil;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^v?([0-9]{1,6})\\.([0-9]{1,6})\\.([0-9]{1,6})$"
                             options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:version
                                                         options:0
                                                           range:NSMakeRange(0, version.length)];
    if (!match || !NSEqualRanges(match.range, NSMakeRange(0, version.length))) return nil;
    NSMutableArray<NSNumber *> *components = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger index = 1; index <= 3; index++) {
        [components addObject:@([[version substringWithRange:[match rangeAtIndex:index]] integerValue])];
    }
    return components;
}

static NSComparisonResult GDTCompareVersions(NSArray<NSNumber *> *left,
                                              NSArray<NSNumber *> *right) {
    for (NSUInteger index = 0; index < 3; index++) {
        NSComparisonResult result = [left[index] compare:right[index]];
        if (result != NSOrderedSame) return result;
    }
    return NSOrderedSame;
}

static BOOL GDTTrustedUpdateResponseURL(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:@"api.github.com"] &&
        [url.path isEqualToString:
            @"/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"] &&
        !url.user.length && !url.password.length && !url.port && !url.query.length && !url.fragment.length;
}

@interface GDTUpdateChecker ()
@property(nonatomic, strong) NSURLSession *session;
@end

@interface GDTAutomaticUpdatePolicy ()
@property(nonatomic, strong) NSUserDefaults *defaults;
@property(nonatomic, strong) GDTUpdateChecker *checker;
@property(nonatomic, copy) NSString *currentVersion;
@property(nonatomic) BOOL inFlight;
@end

@implementation GDTAutomaticUpdatePolicy

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults checker:(GDTUpdateChecker *)checker
                   currentVersion:(NSString *)version {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults;
    _checker = checker;
    _currentVersion = [version copy];
    _clock = ^{ return [NSDate date]; };
    return self;
}

- (BOOL)answered {
    id value = [self.defaults objectForKey:@"GDTUpdates.enabled"];
    return [value isKindOfClass:NSNumber.class] &&
        ([value isEqual:@YES] || [value isEqual:@NO]);
}

- (BOOL)enabled {
    return self.answered && [self.defaults boolForKey:@"GDTUpdates.enabled"];
}

- (NSString *)generation {
    return [self.defaults stringForKey:@"GDTUpdates.generation"] ?: @"";
}

- (void)setEnabled:(BOOL)enabled {
    if (self.answered && self.enabled == enabled) return;
    [self.defaults setBool:enabled forKey:@"GDTUpdates.enabled"];
    [self.defaults setObject:NSUUID.UUID.UUIDString forKey:@"GDTUpdates.generation"];
    if (!enabled) [self.defaults removeObjectForKey:@"GDTUpdates.availableVersion"];
    if (self.stateChanged) self.stateChanged();
}

- (NSString *)availableVersion {
    if (!self.enabled) return nil;
    NSString *version = [self.defaults stringForKey:@"GDTUpdates.availableVersion"];
    NSArray *latest = GDTVersionComponents(version);
    NSArray *current = GDTVersionComponents(self.currentVersion);
    if (!latest || !current || GDTCompareVersions(latest, current) != NSOrderedDescending) return nil;
    return [NSString stringWithFormat:@"%@.%@.%@", latest[0], latest[1], latest[2]];
}

- (void)checkIfDue {
    if (!self.enabled || self.inFlight) return;
    NSTimeInterval now = self.clock().timeIntervalSince1970;
    if (!isfinite(now) || now <= 0) return;
    id attempt = [self.defaults objectForKey:@"GDTUpdates.lastAttempt"];
    if (attempt) {
        NSTimeInterval last = [attempt isKindOfClass:NSNumber.class] ? [attempt doubleValue] : NAN;
        // A damaged date or a backwards wall-clock jump gets one bounded wait,
        // not repeated requests or an indefinitely future next-check date.
        if (!isfinite(last) || last <= 0 || last > now) {
            [self.defaults setDouble:now forKey:@"GDTUpdates.lastAttempt"];
            return;
        }
        if (now - last < 86400) return;
    }
    if (!self.generation.length) {
        [self.defaults setObject:NSUUID.UUID.UUIDString forKey:@"GDTUpdates.generation"];
    }
    NSString *generation = self.generation;
    [self.defaults setDouble:now forKey:@"GDTUpdates.lastAttempt"];
    self.inFlight = YES;
    __weak typeof(self) weakSelf = self;
    [self.checker checkCurrentVersion:self.currentVersion completion:^(NSDictionary *result) {
        void (^finish)(void) = ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.inFlight = NO;
            if (!strongSelf.enabled || ![strongSelf.generation isEqual:generation]) return;
            if ([result[@"status"] isEqual:@"updateAvailable"] && GDTVersionComponents(result[@"version"])) {
                [strongSelf.defaults setObject:result[@"version"] forKey:@"GDTUpdates.availableVersion"];
            } else if ([result[@"status"] isEqual:@"current"]) {
                [strongSelf.defaults removeObjectForKey:@"GDTUpdates.availableVersion"];
            }
            if (strongSelf.stateChanged) strongSelf.stateChanged();
        };
        if (NSThread.isMainThread) finish();
        else dispatch_async(dispatch_get_main_queue(), finish);
    }];
}

- (NSString *)claimNoticeVersion {
    NSString *version = self.availableVersion;
    if (!version.length) return nil;
    NSArray *claimed = [self.defaults stringArrayForKey:@"GDTUpdates.noticedVersions"] ?: @[];
    if ([claimed containsObject:version]) return nil;
    // Reserve before asynchronous permission/delivery callbacks; a failed notice
    // keeps its passive menu entry and never becomes a repeated background prompt.
    [self.defaults setObject:[claimed arrayByAddingObject:version] forKey:@"GDTUpdates.noticedVersions"];
    NSArray *notices = [self.defaults arrayForKey:@"GDTUpdates.notices"] ?: @[];
    [self.defaults setObject:[notices arrayByAddingObject:@{@"version": version, @"generation": self.generation}]
                     forKey:@"GDTUpdates.notices"];
    return version;
}

- (NSArray<NSString *> *)takeObsoleteNoticeIdentifiers {
    NSMutableArray *obsolete = [NSMutableArray array];
    NSMutableArray *current = [NSMutableArray array];
    NSArray *records = [self.defaults arrayForKey:@"GDTUpdates.notices"] ?: @[];
    for (id record in records) {
        if (![record isKindOfClass:NSDictionary.class]) continue;
        NSString *version = record[@"version"];
        NSString *generation = record[@"generation"];
        if (!GDTVersionComponents(version) || ![generation isKindOfClass:NSString.class] ||
            ![[NSUUID alloc] initWithUUIDString:generation]) continue;
        if ([self acceptsNoticeVersion:version generation:generation]) [current addObject:record];
        else [obsolete addObject:[NSString stringWithFormat:@"com.commcats.gdrivebackup.update.%@.%@", generation, version]];
    }
    if (![records isEqual:current]) [self.defaults setObject:current forKey:@"GDTUpdates.notices"];
    return obsolete;
}

- (BOOL)acceptsNoticeVersion:(NSString *)version generation:(NSString *)generation {
    return self.enabled && generation.length && [self.generation isEqual:generation] &&
        version.length && [self.availableVersion isEqual:version] &&
        [[self.defaults stringArrayForKey:@"GDTUpdates.noticedVersions"] containsObject:version];
}

@end

@implementation GDTUpdateChecker

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 10.0;
    configuration.timeoutIntervalForResource = 15.0;
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:nil];
    NSURLSession *session = _session;
    _dataLoader = ^(NSURLRequest *request, GDTUpdateDataCompletion completion) {
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                completion(data, response, error);
            }];
        [task resume];
    };
    return self;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
  completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session;
    (void)task;
    (void)response;
    completionHandler(GDTTrustedUpdateResponseURL(request.URL) ? request : nil);
}

+ (NSDictionary<NSString *, NSString *> *)resultForResponseData:(NSData *)data
                                                    responseURL:(NSURL *)responseURL
                                                 currentVersion:(NSString *)currentVersion {
    if (!data || data.length == 0 || data.length > GDTMaximumUpdateResponseBytes ||
        !GDTTrustedUpdateResponseURL(responseURL)) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    NSDictionary *release = object;
    if (![release[@"tag_name"] isKindOfClass:NSString.class] ||
        ![release[@"draft"] isKindOfClass:NSNumber.class] ||
        ![release[@"prerelease"] isKindOfClass:NSNumber.class] ||
        [release[@"draft"] boolValue] || [release[@"prerelease"] boolValue]) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    NSArray<NSNumber *> *latest = GDTVersionComponents(release[@"tag_name"]);
    NSArray<NSNumber *> *current = GDTVersionComponents(currentVersion);
    if (!latest || !current) return GDTUnavailableUpdateResult(@"invalid_response");
    NSString *normalized = [NSString stringWithFormat:@"%@.%@.%@",
        latest[0], latest[1], latest[2]];
    if (GDTCompareVersions(latest, current) != NSOrderedDescending) {
        return @{ @"status": @"current", @"version": normalized };
    }
    return @{
        @"status": @"updateAvailable",
        @"version": normalized,
        @"releaseURL": GDTUpdateReleaseURLString
    };
}

- (void)checkCurrentVersion:(NSString *)currentVersion
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *))completion {
    NSURL *url = [NSURL URLWithString:GDTUpdateAPIURLString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"GDrive-Backup-Tiger" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    if (!self.dataLoader) {
        completion(GDTUnavailableUpdateResult(@"network"));
        return;
    }
    self.dataLoader(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class] ||
            ((NSHTTPURLResponse *)response).statusCode != 200) {
            completion(GDTUnavailableUpdateResult(@"network"));
            return;
        }
        completion([GDTUpdateChecker resultForResponseData:data
                                               responseURL:response.URL
                                            currentVersion:currentVersion]);
    });
}

@end
