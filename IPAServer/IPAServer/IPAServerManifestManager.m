//
//  IPAServerManifestManager.m
//  IPAServer
//
//  Created by 冷秋 on 2019/12/2.
//  Copyright © 2019 Magic-Unique. All rights reserved.
//

#import "IPAServerManifestManager.h"

@interface IPAServerManifestUploadManager : NSObject

@property (nonatomic, strong) AFHTTPSessionManager *sessionManager;

@property (nonatomic, copy) NSString *url;

@property (nonatomic, strong) NSData *data;

@property (nonatomic, strong, readonly) NSOperationQueue *queue;

@property (nonatomic, assign, readonly) IPAManifestUploadingPolicy policy;

@end

@implementation IPAServerManifestUploadManager

- (void)startWithPolicy:(IPAManifestUploadingPolicy)policy {
    _policy = policy;
    if (policy == IPAManifestUploadingPolicyPreuploadBeforeInstall) {
        [self.queue addOperationWithBlock:^{
            self.url = [self syncUpload];
        }];
    }
}

- (NSString *)syncUpload {
    dispatch_semaphore_t semaphore_t = dispatch_semaphore_create(0);
    __block NSDictionary *_response = nil;
    __block NSError *_error = nil;
    [self.sessionManager POST:@"https://file.io/?expires=1d"
                   parameters:nil
    constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFileData:self.data
                                    name:@"file"
                                fileName:@"install.plist"
                                mimeType:@"application/x-plist"];
    } progress:^(NSProgress *uploadProgress) {
    } success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        _response = responseObject;
        dispatch_semaphore_signal(semaphore_t);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        _error = error;
        dispatch_semaphore_signal(semaphore_t);
    }];
    dispatch_semaphore_wait(semaphore_t, DISPATCH_TIME_FOREVER);
    if (_response) {
        return _response[@"link"];
    }
    return nil;
}

- (void)getDownloadURL:(void (^)(NSString *))block {
    [self.queue addOperationWithBlock:^{
        if (self.policy == IPAManifestUploadingPolicyPreuploadBeforeInstall) {
            NSString *url = self.url;
            dispatch_async(dispatch_get_main_queue(), ^{
                block(url);
            });
            self.url = [self syncUpload];
        } else {
            NSString *url = [self syncUpload];
            block(url);
        }
    }];
}

@synthesize queue = _queue;
- (NSOperationQueue *)queue {
    if (!_queue) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
    }
    return _queue;
}

@end



@interface IPAServerManifestManager ()

@property (nonatomic, strong, readonly) NSMutableDictionary *targets;

@end

@implementation IPAServerManifestManager

- (instancetype)initWithPolicy:(IPAManifestUploadingPolicy)policy sessionManager:(AFHTTPSessionManager *)sessionManager {
    self = [super init];
    if (self) {
        _sessionManager = sessionManager;
        _policy = policy;
        _targets = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setManifest:(IPAServerManifest *)manifest forKey:(NSString *)key {
    IPAServerManifestUploadManager *mgr = [[IPAServerManifestUploadManager alloc] init];
    mgr.sessionManager = self.sessionManager;
    mgr.data = [manifest propertyListDataWithXMLFormat];
    self.targets[key] = mgr;
    [mgr startWithPolicy:self.policy];
}

- (void)getDownloadURLForKey:(NSString *)key completed:(void (^)(NSString *))completion {
    IPAServerManifestUploadManager *mgr = self.targets[key];
    [mgr getDownloadURL:completion];
}

@end
