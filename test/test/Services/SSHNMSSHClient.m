#import "SSHNMSSHClient.h"

#import "NMSSH.h"

@implementation SSHCommandResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _success = NO;
        _output = @"";
        _errorMessage = @"";
        _remoteBanner = @"";
        _fingerprint = @"";
        _authMethods = @"";
    }
    return self;
}

@end

@implementation SSHNMSSHClient

+ (SSHCommandResult *)runCommandWithHost:(NSString *)host
                                    port:(NSInteger)port
                                username:(NSString *)username
                                password:(NSString *)password
                                 command:(NSString *)command
                                 timeout:(NSTimeInterval)timeout {
    @autoreleasepool {
        SSHCommandResult *result = [[SSHCommandResult alloc] init];
        NMSSHSession *session = [[NMSSHSession alloc] initWithHost:host
                                                              port:port
                                                       andUsername:username];
        session.timeout = @(timeout);

        if (![session connect]) {
            result.errorMessage = [self bestErrorMessageForSession:session
                                                      fallbackText:@"SSH connect failed"];
            result.remoteBanner = session.remoteBanner ?: @"";
            [session disconnect];
            return result;
        }

        result.remoteBanner = session.remoteBanner ?: @"";
        NSString *fingerprint = [session fingerprint:NMSSHSessionHashSHA1];
        result.fingerprint = fingerprint ?: @"";
        NSArray *methods = [session supportedAuthenticationMethods];
        if (methods.count > 0) {
            result.authMethods = [methods componentsJoinedByString:@","];
        }

        BOOL authorized = [session authenticateByPassword:password];
        if (!authorized) {
            authorized = [session authenticateByKeyboardInteractiveUsingBlock:^NSString * _Nonnull(NSString * _Nonnull request) {
                return password ?: @"";
            }];
        }

        if (!authorized) {
            result.errorMessage = [self bestErrorMessageForSession:session
                                                      fallbackText:@"SSH authentication failed"];
            [session disconnect];
            return result;
        }

        NSError *executionError = nil;
        NSString *output = [session.channel execute:command
                                              error:&executionError
                                            timeout:@(timeout)];
        if (output == nil) {
            if (executionError.localizedDescription.length > 0) {
                result.errorMessage = executionError.localizedDescription;
            } else {
                result.errorMessage = [self bestErrorMessageForSession:session
                                                          fallbackText:@"SSH command execution failed"];
            }
            [session disconnect];
            return result;
        }

        result.success = YES;
        result.output = output ?: @"";
        [session disconnect];
        return result;
    }
}

+ (NSString *)bestErrorMessageForSession:(NMSSHSession *)session
                            fallbackText:(NSString *)fallbackText {
    if (session.rawSession == NULL) {
        return fallbackText;
    }

    NSString *message = session.lastError.localizedDescription;
    if (message.length > 0) {
        return message;
    }
    return fallbackText;
}

@end
