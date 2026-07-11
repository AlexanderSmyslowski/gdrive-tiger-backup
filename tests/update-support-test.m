#import <Foundation/Foundation.h>

#import "UpdateSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSData *JSONData(NSDictionary *dictionary) {
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
}

int main(void) {
    @autoreleasepool {
        NSURL *apiURL = [NSURL URLWithString:
            @"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"];
        NSDictionary *available = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"v2.10.0",
            @"draft": @NO,
            @"prerelease": @NO,
            @"html_url": @"https://evil.invalid/fake.pkg",
            @"body": @"token=private-secret"
        }) responseURL:apiURL currentVersion:@"2.9.9"];
        Assert([available[@"status"] isEqualToString:@"updateAvailable"] &&
               [available[@"version"] isEqualToString:@"2.10.0"] &&
               [available[@"releaseURL"] isEqualToString:
                   @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"] &&
               ![[available description] containsString:@"evil.invalid"] &&
               ![[available description] containsString:@"private-secret"],
               @"update results use numeric versions and one hard-coded official release page");

        NSDictionary *current = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"2.0.0", @"draft": @NO, @"prerelease": @NO
        }) responseURL:apiURL currentVersion:@"2.0.0"];
        NSDictionary *older = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"v1.99.0", @"draft": @NO, @"prerelease": @NO
        }) responseURL:apiURL currentVersion:@"2.0.0"];
        Assert([current[@"status"] isEqualToString:@"current"] &&
               [older[@"status"] isEqualToString:@"current"],
               @"equal or older releases never become a downgrade offer");

        NSArray<NSDictionary *> *invalidResults = @[
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"v2.1.0-beta.1", @"draft": @NO, @"prerelease": @YES
            }) responseURL:apiURL currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"2.1.0\nhttps://evil.invalid", @"draft": @NO, @"prerelease": @NO
            }) responseURL:apiURL currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"v2.1.0", @"draft": @NO, @"prerelease": @NO
            }) responseURL:[NSURL URLWithString:@"https://evil.invalid/releases/latest"]
               currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:[NSMutableData dataWithLength:300 * 1024]
                                        responseURL:apiURL currentVersion:@"2.0.0"]
        ];
        BOOL rejected = YES;
        NSSet<NSString *> *safeUnavailableKeys = [NSSet setWithArray:@[@"reason", @"status"]];
        for (NSDictionary *result in invalidResults) {
            rejected = rejected && [result[@"status"] isEqualToString:@"unavailable"] &&
                [[NSSet setWithArray:result.allKeys] isEqualToSet:safeUnavailableKeys];
        }
        Assert(rejected,
               @"prereleases, malformed versions, foreign responses, and oversized bodies fail closed");

        __block NSInteger loadCalls = 0;
        __block NSURLRequest *capturedRequest = nil;
        GDTUpdateChecker *checker = [[GDTUpdateChecker alloc] init];
        checker.dataLoader = ^(NSURLRequest *request, GDTUpdateDataCompletion completion) {
            loadCalls++;
            capturedRequest = request;
            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
                initWithURL:apiURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
            completion(JSONData(@{
                @"tag_name": @"v2.1.0", @"draft": @NO, @"prerelease": @NO
            }), response, nil);
        };
        Assert(loadCalls == 0, @"constructing the checker never contacts the network");
        __block NSDictionary *checkedResult = nil;
        [checker checkCurrentVersion:@"2.0.0" completion:^(NSDictionary *result) {
            checkedResult = result;
        }];
        Assert(loadCalls == 1 &&
               [capturedRequest.URL isEqual:apiURL] &&
               [capturedRequest.HTTPMethod isEqualToString:@"GET"] &&
               [capturedRequest valueForHTTPHeaderField:@"Authorization"] == nil &&
               [checkedResult[@"status"] isEqualToString:@"updateAvailable"],
               @"one explicit check makes one unauthenticated request to the fixed API endpoint");

        SEL redirectSelector = NSSelectorFromString(
            @"URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:");
        __block NSURLRequest *allowedRedirect = nil;
        __block NSURLRequest *blockedRedirect = (NSURLRequest *)[NSNull null];
        if ([checker respondsToSelector:redirectSelector]) {
            typedef void (*RedirectMethod)(id, SEL, NSURLSession *, NSURLSessionTask *,
                NSHTTPURLResponse *, NSURLRequest *, void (^)(NSURLRequest *));
            RedirectMethod redirect = (RedirectMethod)[checker methodForSelector:redirectSelector];
            NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc]
                initWithURL:apiURL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
            NSURLRequest *sameEndpoint = [NSURLRequest requestWithURL:apiURL];
            NSURLRequest *foreignEndpoint = [NSURLRequest requestWithURL:
                [NSURL URLWithString:@"https://evil.invalid/collect"]];
            redirect(checker, redirectSelector, nil, nil, redirectResponse, sameEndpoint,
                ^(NSURLRequest *request) { allowedRedirect = request; });
            redirect(checker, redirectSelector, nil, nil, redirectResponse, foreignEndpoint,
                ^(NSURLRequest *request) { blockedRedirect = request; });
        }
        Assert([allowedRedirect.URL isEqual:apiURL] && blockedRedirect == nil,
               @"redirect handling never contacts a foreign or modified endpoint");
    }

    if (failures > 0) {
        printf("%d update support test(s) failed.\n", failures);
        return 1;
    }
    printf("All update support tests passed.\n");
    return 0;
}
