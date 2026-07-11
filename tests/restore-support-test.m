#import <Foundation/Foundation.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static void Write(NSURL *url, NSString *value) {
    [value writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSArray<NSDictionary<NSString *, id> *> *CallList(id object,
                                                          NSString *selectorName,
                                                          NSString *relativePath,
                                                          NSError **error) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    typedef NSArray *(*ListMethod)(id, SEL, NSString *, NSError **);
    ListMethod method = (ListMethod)[object methodForSelector:selector];
    return method(object, selector, relativePath, error);
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-restore-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];
        NSURL *myDrive = [root URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *versions = [root URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES];
        NSString *olderRun = @"2026-07-09T08-00-00+0200-11111111-1111-1111-1111-111111111111";
        NSString *newerRun = @"2026-07-10T20-00-00+0200-22222222-2222-2222-2222-222222222222";
        NSURL *olderDrive = [[versions URLByAppendingPathComponent:olderRun isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *newerDrive = [[versions URLByAppendingPathComponent:newerRun isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *retiredDrive = [[[versions URLByAppendingPathComponent:@".retention-trash" isDirectory:YES]
            URLByAppendingPathComponent:@"retired-run" isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *outside = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"outside-%@.txt", NSUUID.UUID.UUIDString]];
        NSURL *linkedRoot = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"linked-root-%@", NSUUID.UUID.UUIDString]];
        NSURL *output = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-restored-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];

        for (NSURL *directory in @[myDrive, olderDrive, newerDrive, retiredDrive, output]) {
            [fileManager createDirectoryAtURL:directory
                  withIntermediateDirectories:YES attributes:nil error:nil];
        }
        Write([myDrive URLByAppendingPathComponent:@"current-only.txt"], @"current");
        Write([myDrive URLByAppendingPathComponent:@"shared.txt"], @"live shared");
        Write([olderDrive URLByAppendingPathComponent:@"shared.txt"], @"older shared");
        Write([newerDrive URLByAppendingPathComponent:@"shared.txt"], @"newer shared");
        Write([newerDrive URLByAppendingPathComponent:@"historical-only.txt"], @"deleted later");
        Write([retiredDrive URLByAppendingPathComponent:@"retired.txt"], @"retired");
        Write(outside, @"outside");
        [fileManager createSymbolicLinkAtURL:[myDrive URLByAppendingPathComponent:@"unsafe-link.txt"]
                         withDestinationURL:outside error:nil];
        [fileManager createSymbolicLinkAtURL:linkedRoot withDestinationURL:root error:nil];

        Class catalogClass = NSClassFromString(@"GDTRestoreCatalog");
        Class copierClass = NSClassFromString(@"GDTRestoreCopier");
        Assert(catalogClass != Nil && copierClass != Nil,
               @"restore catalog and verified copier are available");

        if (catalogClass && copierClass) {
            SEL catalogInitSelector = NSSelectorFromString(@"initWithBackupRootURL:fileManager:");
            typedef id (*CatalogInitMethod)(id, SEL, NSURL *, NSFileManager *);
            CatalogInitMethod catalogInit = (CatalogInitMethod)[catalogClass
                instanceMethodForSelector:catalogInitSelector];
            id catalog = catalogInit([catalogClass alloc], catalogInitSelector, root, fileManager);

            NSError *error = nil;
            NSArray<NSDictionary<NSString *, id> *> *rootChildren =
                CallList(catalog, @"childrenAtRelativePath:error:", @"", &error);
            NSSet *rootNames = [NSSet setWithArray:[rootChildren valueForKey:@"name"]];
            Assert(!error && [rootNames containsObject:@"My Drive"] &&
                   ![rootNames containsObject:@".gdrive-versions"],
                   @"browser starts at backup areas without exposing its internal version store");

            NSArray<NSDictionary<NSString *, id> *> *children =
                CallList(catalog, @"childrenAtRelativePath:error:", @"My Drive", &error);
            NSSet *childNames = [NSSet setWithArray:[children valueForKey:@"name"]];
            Assert(!error && [childNames containsObject:@"current-only.txt"] &&
                   [childNames containsObject:@"shared.txt"] &&
                   [childNames containsObject:@"historical-only.txt"],
                   @"browser merges current and retained per-file versions lazily");
            Assert(![childNames containsObject:@"unsafe-link.txt"] &&
                   ![childNames containsObject:@"retired.txt"],
                   @"browser excludes symbolic links and retired quarantine data");

            NSArray<NSDictionary<NSString *, id> *> *sharedVersions =
                CallList(catalog, @"versionsForRelativePath:error:", @"My Drive/shared.txt", &error);
            Assert(sharedVersions.count == 3 &&
                   [sharedVersions[0][@"kind"] isEqualToString:@"current"] &&
                   [sharedVersions[1][@"runID"] isEqualToString:newerRun] &&
                   [sharedVersions[2][@"runID"] isEqualToString:olderRun],
                   @"file versions show current first and history newest first");

            error = nil;
            NSArray *unsafeTraversal =
                CallList(catalog, @"childrenAtRelativePath:error:", @"../private", &error);
            Assert(unsafeTraversal.count == 0 && error != nil,
                   @"catalog rejects traversal outside the backup root");

            NSArray<NSDictionary<NSString *, id> *> *historicalVersions =
                CallList(catalog, @"versionsForRelativePath:error:", @"My Drive/historical-only.txt", &error);
            NSURL *historicalSource = historicalVersions.firstObject[@"sourceURL"];
            Write([output URLByAppendingPathComponent:@"historical-only.txt"], @"keep existing");

            SEL copierInitSelector = NSSelectorFromString(@"initWithBackupRootURL:fileManager:");
            typedef id (*CopierInitMethod)(id, SEL, NSURL *, NSFileManager *);
            CopierInitMethod copierInit = (CopierInitMethod)[copierClass
                instanceMethodForSelector:copierInitSelector];
            id copier = copierInit([copierClass alloc], copierInitSelector, root, fileManager);
            SEL restoreSelector = NSSelectorFromString(@"restoreSourceURL:toDirectoryURL:error:");
            typedef NSDictionary *(*RestoreMethod)(id, SEL, NSURL *, NSURL *, NSError **);
            RestoreMethod restore = (RestoreMethod)[copier methodForSelector:restoreSelector];

            error = nil;
            NSDictionary<NSString *, id> *result = restore(copier, restoreSelector,
                                                            historicalSource, output, &error);
            NSURL *restoredURL = result[@"destinationURL"];
            NSString *restoredContent = restoredURL
                ? [NSString stringWithContentsOfURL:restoredURL encoding:NSUTF8StringEncoding error:nil]
                : nil;
            Assert(!error && [restoredURL.lastPathComponent isEqualToString:@"historical-only restored.txt"] &&
                   [restoredContent isEqualToString:@"deleted later"] &&
                   [result[@"sha256"] length] == 64,
                   @"verified restore preserves an existing file and returns its SHA-256 proof");

            __block NSInteger digestCalls = 0;
            id mismatchProvider = [^NSString *(NSURL *url, NSError **digestError) {
                (void)url;
                (void)digestError;
                digestCalls++;
                return digestCalls == 1 ? @"aaaaaaaa" : @"bbbbbbbb";
            } copy];
            [copier setValue:mismatchProvider forKey:@"digestProvider"];
            NSUInteger beforeCount = [fileManager contentsOfDirectoryAtURL:output
                                                includingPropertiesForKeys:nil options:0 error:nil].count;
            error = nil;
            NSDictionary *mismatchResult = restore(copier, restoreSelector,
                                                     historicalSource, output, &error);
            NSUInteger afterCount = [fileManager contentsOfDirectoryAtURL:output
                                               includingPropertiesForKeys:nil options:0 error:nil].count;
            Assert(!mismatchResult && error != nil && beforeCount == afterCount,
                   @"checksum mismatch never publishes an unverified restored file");

            error = nil;
            NSDictionary *outsideResult = restore(copier, restoreSelector, outside, output, &error);
            Assert(!outsideResult && error != nil,
                   @"restore copier rejects sources outside the configured backup");

            error = nil;
            NSDictionary *insideResult = restore(copier, restoreSelector,
                                                  historicalSource, myDrive, &error);
            Assert(!insideResult && error != nil,
                   @"restore destination cannot modify the independent backup tree");

            id linkedCatalog = catalogInit([catalogClass alloc], catalogInitSelector,
                                            linkedRoot, fileManager);
            error = nil;
            NSArray *linkedRootChildren =
                CallList(linkedCatalog, @"childrenAtRelativePath:error:", @"", &error);
            Assert(linkedRootChildren.count == 0,
                   @"symbolic-link backup roots are never browsed as trusted copies");
        }

        [fileManager trashItemAtURL:root resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:outside resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:output resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:linkedRoot resultingItemURL:nil error:nil];
    }

    if (failures > 0) {
        printf("%d restore support test(s) failed.\n", failures);
        return 1;
    }
    printf("All restore support tests passed.\n");
    return 0;
}
