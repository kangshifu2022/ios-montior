#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSHCommandResult : NSObject

@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *output;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *remoteBanner;
@property (nonatomic, copy) NSString *fingerprint;
@property (nonatomic, copy) NSString *authMethods;

@end

@interface SSHNMSSHClient : NSObject

+ (SSHCommandResult *)runCommandWithHost:(NSString *)host
                                    port:(NSInteger)port
                                username:(NSString *)username
                                password:(NSString *)password
                                 command:(NSString *)command
                                 timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
