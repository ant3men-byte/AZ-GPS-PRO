#import "LicenseAPIClient.h"
#import "LicenseConfig.h"
#import <Security/Security.h>
#import <cmath>
@implementation AZLicenseAPIClient
- (NSError *)error:(NSString *)message {return [NSError errorWithDomain:@"AZLicense" code:1 userInfo:@{NSLocalizedDescriptionKey:message ?: @"تعذر التحقق"}];}
- (void)post:(NSString *)path body:(NSDictionary *)body completion:(void (^)(NSDictionary *,NSError *))completion {
 NSURL *base=[NSURL URLWithString:@AZ_LICENSE_API_URL];
 if(![base.scheme isEqualToString:@"https"]||!base.host.length){dispatch_async(dispatch_get_main_queue(),^{completion(nil,[self error:@"يلزم إعداد عنوان سيرفر الترخيص قبل تشغيل هذه النسخة."]);});return;}
 NSURL *url=[NSURL URLWithString:path relativeToURL:base];NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.absoluteURL];request.HTTPMethod=@"POST";request.timeoutInterval=12;request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
 [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];NSError *encodeError=nil;request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError];
 if(encodeError){completion(nil,encodeError);return;}
 NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.timeoutIntervalForRequest=12;config.timeoutIntervalForResource=15;config.URLCache=nil;
 NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
 [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
  NSDictionary *result=nil;if(data.length&&data.length<16384){id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if([obj isKindOfClass:NSDictionary.class])result=obj;}
  NSInteger status=[(NSHTTPURLResponse *)response statusCode];
  if(!error&&(!result||status<200||status>=300))error=[self error:result[@"error"] ?: @"network_unavailable"];
  dispatch_async(dispatch_get_main_queue(),^{completion(result,error);});[session finishTasksAndInvalidate];
 }]resume];
}
- (NSDictionary *)validateLease:(NSDictionary *)envelope installation:(NSString *)installation bundle:(NSString *)bundle error:(NSError **)error {
 BOOL valid=NO;NSDictionary *lease=nil;
 if([envelope[@"algorithm"]isEqual:@"RS256"]&&[envelope[@"payload"]isKindOfClass:NSString.class]&&[envelope[@"signature"]isKindOfClass:NSString.class]){
  NSData *payload=[[NSData alloc]initWithBase64EncodedString:envelope[@"payload"] options:0],*signature=[[NSData alloc]initWithBase64EncodedString:envelope[@"signature"] options:0],*publicData=[[NSData alloc]initWithBase64EncodedString:@AZ_LICENSE_PUBLIC_KEY_B64 options:0];
  if(payload.length&&payload.length<8192&&signature.length&&publicData.length){
   SecKeyRef pub=SecKeyCreateWithData((__bridge CFDataRef)publicData,(__bridge CFDictionaryRef)@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic},NULL);
   if(pub){valid=SecKeyVerifySignature(pub,kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,(__bridge CFDataRef)payload,(__bridge CFDataRef)signature,NULL);CFRelease(pub);}
   if(valid){id obj=[NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];if([obj isKindOfClass:NSDictionary.class])lease=obj;}
  }
 }
 valid=valid&&[lease[@"status"]isEqual:@"active"]&&[lease[@"installation_id"]isEqual:installation]&&[lease[@"bundle_id"]isEqual:bundle]&&[lease[@"license_id"]isKindOfClass:NSString.class]&&[lease[@"server_time"]isKindOfClass:NSNumber.class]&&[lease[@"expires_at"]isKindOfClass:NSNumber.class]&&[lease[@"lease_expires_at"]isKindOfClass:NSNumber.class]&&[lease[@"revision"]isKindOfClass:NSNumber.class];
 if(valid){double now=[lease[@"server_time"]doubleValue],expiry=[lease[@"lease_expires_at"]doubleValue];valid=isfinite(now)&&isfinite(expiry)&&expiry>now&&expiry-now<=300&&expiry<=[lease[@"expires_at"]doubleValue];}
 if(!valid){if(error)*error=[self error:@"invalid_server_signature"];return nil;}return lease;
}
@end
