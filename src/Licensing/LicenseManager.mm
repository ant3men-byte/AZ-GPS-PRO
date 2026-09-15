#import "LicenseManager.h"
#import "InstallationIdentity.h"
#import "LicenseAPIClient.h"
#import "AZGPS.h"
#import "UI.h"
#import "Audit.h"
#import "LicenseSessionPolicy.h"
#import <UIKit/UIKit.h>
#import <Network/Network.h>
#import <mach/mach_time.h>
#import <atomic>
#import <cmath>
static std::atomic<bool> AZAuthorized(false);
static std::atomic<double> AZDeadline(0);
static double AZMonotonic(void){static mach_timebase_info_data_t info;static dispatch_once_t once;dispatch_once(&once,^{mach_timebase_info(&info);});return (double)mach_continuous_time()*info.numer/info.denom/1e9;}
BOOL AZLicenseCanRun(void){return AZAuthorized.load()&&AZMonotonic()<AZDeadline.load();}
@interface AZLicenseWindow : UIWindow @end
@implementation AZLicenseWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {UIView *v=[super hitTest:p withEvent:e];return v==self||v==self.rootViewController.view?nil:v;}
@end
@interface AZLicenseManager () <UIGestureRecognizerDelegate>
@property(nonatomic,strong) AZInstallationIdentity *identity;
@property(nonatomic,strong) AZLicenseAPIClient *api;
@property(nonatomic,strong) NSTimer *expiryTimer;
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) nw_path_monitor_t monitor;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL pathAvailable;
@property(nonatomic) BOOL active;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) NSHashTable<UIWindow *> *tapWindows;
@property(nonatomic) double subscriptionDeadline;
@property(nonatomic,copy) NSString *pendingCode;
@property(nonatomic) BOOL activationRequested;
@property(nonatomic,strong) NSDictionary *subscription;
@property(nonatomic) double backgroundAt;
@property(nonatomic) BOOL verifiedThisProcess;
@property(nonatomic) BOOL verificationAttempted;
@property(nonatomic) BOOL revealAfterVerification;
@property(nonatomic,copy) NSString *lastFailureCode;
@end
@implementation AZLicenseManager
+ (instancetype)sharedManager {static AZLicenseManager *m;static dispatch_once_t once;dispatch_once(&once,^{m=[self new];m.identity=[AZInstallationIdentity new];m.api=[AZLicenseAPIClient new];m.pathAvailable=YES;});return m;}
- (void)start {
 if(self.started)return;self.started=YES;
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
 self.monitor=nw_path_monitor_create();nw_path_monitor_set_queue(self.monitor,dispatch_get_main_queue());
 __weak AZLicenseManager *weak=self;
 nw_path_monitor_set_update_handler(self.monitor,^(nw_path_t path){AZLicenseManager *m=weak;if(!m)return;BOOL available=nw_path_get_status(path)==nw_path_status_satisfied;BOOL becameAvailable=!m.pathAvailable&&available;m.pathAvailable=available;if(becameAvailable&&m.active&&!m.verifiedThisProcess&&m.identity.savedCode.length)[m verify];});nw_path_monitor_start(self.monitor);
 self.tapWindows=[NSHashTable weakObjectsHashTable];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(windowVisible:) name:UIWindowDidBecomeVisibleNotification object:nil];
 [self installTapGestures];

 self.active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
 if(self.active)[self begin];
}
- (void)begin {if(self.identity.savedCode.length&&!self.verifiedThisProcess)[self verify];}
- (void)foreground:(NSNotification *)note {
 self.active=YES;self.activationRequested=NO;self.window.hidden=YES;[self installTapGestures];
 if(!AZLicenseNeedsForegroundVerification(self.verifiedThisProcess,self.backgroundAt,AZMonotonic()))return;
 if(self.backgroundAt>0){self.generation++;self.busy=NO;self.verifiedThisProcess=NO;self.verificationAttempted=NO;self.revealAfterVerification=NO;self.lastFailureCode=nil;[self disable];}
 [self begin];
}
- (void)background:(NSNotification *)note {
 self.active=NO;self.activationRequested=NO;self.backgroundAt=AZMonotonic();self.window.hidden=YES;
}
- (void)disable {
 AZAuthorized.store(false);AZDeadline.store(0);
 [[AZLocationService sharedService]restoreDefault];
 [[AZUIController sharedController]hideForLicense];
}
- (NSString *)friendly:(NSString *)code {
 NSDictionary *messages=@{@"expired":@"انتهى الاشتراك. أدخل كودًا جديدًا أو أعد التحقق بعد التمديد.",@"invalid":@"الكود غير صالح.",@"invalid_input":@"تحقق من صيغة الكود.",@"suspended":@"الاشتراك موقوف مؤقتًا. تواصل مع الإدارة.",@"revoked":@"تم إلغاء الاشتراك. أدخل كودًا آخر.",@"wrong_app":@"هذا الكود مرتبط بتطبيق آخر.",@"device_limit":@"الكود مستخدم على تثبيت آخر. تواصل مع الإدارة.",@"rate_limited":@"محاولات كثيرة. انتظر دقيقة.",@"invalid_server_signature":@"تعذر التأكد من استجابة السيرفر. الأداة متوقفة."};
 return messages[code] ?: @"تعذر التحقق عبر الإنترنت. الأداة متوقفة؛ حاول مجددًا.";
}
- (void)activateCode:(NSString *)code {
 if(self.busy)return;self.pendingCode=[[code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];if(!self.pendingCode.length){self.message.text=@"أدخل كود الاشتراك أولًا.";return;}[self verify];
}
- (void)verify {
 if(self.busy||!self.active)return;NSString *code=self.pendingCode ?: self.identity.savedCode;
 if(!code.length)return;
 if(!self.pathAvailable){self.verificationAttempted=YES;self.lastFailureCode=@"offline";BOOL requested=self.revealAfterVerification||self.activationRequested;self.revealAfterVerification=NO;self.activationRequested=requested;[self disable];if(requested){[self showActivation];self.message.text=@"لا يوجد اتصال بالإنترنت.";}return;}
 NSError *identityError=nil;if(![self.identity prepare:&identityError]){[self disable];[self showActivation];self.message.text=identityError.localizedDescription ?: @"تعذر إعداد هوية الترخيص.";return;}
 NSString *installation=[self.identity installationIDForCode:code error:&identityError];
 if(!installation.length){[self disable];[self showActivation];self.message.text=identityError.localizedDescription;return;}
 self.busy=YES;self.verificationAttempted=YES;self.lastFailureCode=nil;NSUInteger gen=++self.generation;double start=AZMonotonic();self.message.text=@"جارٍ التحقق…";
 NSDictionary *body=@{@"key":code,@"installation_id":installation,@"bundle_id":NSBundle.mainBundle.bundleIdentifier ?: @"unknown",@"public_key":self.identity.publicKey};
 [self.api post:@"/license/challenge" body:body completion:^(NSDictionary *challenge,NSError *error){
  if(gen!=self.generation)return;
  if(error){[self failed:error code:challenge[@"error"]];return;}
  if(![challenge[@"message"]isKindOfClass:NSString.class]||![challenge[@"challenge_id"]isKindOfClass:NSString.class]){[self failed:nil code:@"invalid_server_signature"];return;}
  NSError *signError=nil;NSString *signature=[self.identity signMessage:challenge[@"message"] error:&signError];
  if(!signature){[self failed:signError code:nil];return;}
  [self.api post:@"/license/verify" body:@{@"challenge_id":challenge[@"challenge_id"],@"signature":signature} completion:^(NSDictionary *envelope,NSError *verifyError){
   if(gen!=self.generation)return;self.busy=NO;
   if(verifyError){[self failed:verifyError code:envelope[@"error"]];return;}
   NSError *leaseError=nil;NSDictionary *lease=[self.api validateLease:envelope installation:installation bundle:NSBundle.mainBundle.bundleIdentifier ?: @"unknown" error:&leaseError];
   if(!lease||![lease[@"challenge_id"]isEqual:challenge[@"challenge_id"]]||!self.pathAvailable||!self.active){[self failed:leaseError code:@"invalid_server_signature"];return;}
   double ttl=[lease[@"lease_expires_at"]doubleValue]-[lease[@"server_time"]doubleValue]-(AZMonotonic()-start);
   if(ttl<=0){[self failed:nil code:@"expired"];return;}
   if(![self.identity saveCode:code error:&leaseError]){[self disable];self.message.text=leaseError.localizedDescription;return;}
   self.subscriptionDeadline=AZMonotonic()+[lease[@"expires_at"]doubleValue]-[lease[@"server_time"]doubleValue]-(AZMonotonic()-start);
   self.subscription=lease;self.activationRequested=NO;self.verifiedThisProcess=YES;
   self.pendingCode=nil;AZDeadline.store(self.subscriptionDeadline);AZAuthorized.store(true);
   [self.expiryTimer invalidate];double until=self.subscriptionDeadline-AZMonotonic();
   self.expiryTimer=[NSTimer scheduledTimerWithTimeInterval:MAX(.1,until) target:self selector:@selector(subscriptionExpired:) userInfo:nil repeats:NO];
   [[AZAppManager sharedManager]initialize];
   BOOL reveal=self.revealAfterVerification;self.revealAfterVerification=NO;
   self.window.hidden=YES;if(reveal)[[AZUIController sharedController]installWhenReady];self.message.text=@"تم التفعيل. انقر الشاشة ثلاث مرات متتالية لإظهار الأداة.";
   AZAuditLogFeature(@"license",@"VALID",@"Online verification succeeded; protected UI remains hidden");
  }];
 }];
}
- (void)subscriptionExpired:(NSTimer *)timer {
 if(AZMonotonic()<self.subscriptionDeadline)return;
 self.verifiedThisProcess=NO;self.verificationAttempted=YES;self.lastFailureCode=@"expired";[self disable];
 self.message.text=[self friendly:@"expired"];
}
- (void)failed:(NSError *)error code:(NSString *)code {
 self.busy=NO;self.lastFailureCode=code ?: (error.code==NSURLErrorNotConnectedToInternet?@"offline":@"network");BOOL requested=self.revealAfterVerification||self.activationRequested;self.revealAfterVerification=NO;self.activationRequested=requested;[self disable];
 BOOL show=requested;
 if(show)[self showActivation];self.message.text=[self friendly:code];
 AZAuditLogFeature(@"license",@"OFF",code ?: @"network_or_configuration_error");
}
- (void)windowVisible:(NSNotification *)note {[self installTapGestures];}
- (void)installTapGestures {
 NSMutableArray<UIWindow *> *windows=[NSMutableArray array];
 if(@available(iOS 13.0,*)){
  for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
   if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)
    [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
 }else [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
 for(UIWindow *window in windows){
  if(window==self.window||[window isKindOfClass:AZLicenseWindow.class]||window.hidden||[self.tapWindows containsObject:window])continue;
  UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tripleTapped:)];
  tap.numberOfTapsRequired=3;tap.numberOfTouchesRequired=1;
  tap.cancelsTouchesInView=NO;tap.delaysTouchesBegan=NO;tap.delaysTouchesEnded=NO;tap.delegate=self;
  [window addGestureRecognizer:tap];[self.tapWindows addObject:window];
 }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {return YES;}
- (void)tripleTapped:(UITapGestureRecognizer *)gesture {
 if(gesture.state!=UIGestureRecognizerStateRecognized||!self.active)return;
 switch(azgps::licenseRevealAction(AZLicenseCanRun(),self.identity.savedCode.length>0,self.busy,self.verificationAttempted)){
  case azgps::LicenseRevealAction::ShowTool:[[AZUIController sharedController]installWhenReady];break;
  case azgps::LicenseRevealAction::WaitForVerification:self.revealAfterVerification=YES;break;
  case azgps::LicenseRevealAction::VerifyThenShow:self.revealAfterVerification=YES;[self verify];break;
  case azgps::LicenseRevealAction::ShowActivation:self.activationRequested=YES;[self showActivation];self.message.text=[self friendly:self.lastFailureCode];break;
 }
}
- (UIWindowScene *)scene API_AVAILABLE(ios(13.0)) {for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive)return (UIWindowScene *)s;return nil;}
- (void)showActivation {
 if(!self.active||!self.activationRequested)return;
 if(!self.window){
  UIWindow *w=nil;if(@available(iOS 13.0,*)){UIWindowScene *scene=[self scene];if(!scene){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self showActivation];});return;}w=[[AZLicenseWindow alloc]initWithWindowScene:scene];}else w=[[AZLicenseWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
  w.windowLevel=UIWindowLevelAlert+101;w.backgroundColor=UIColor.clearColor;UIViewController *vc=[UIViewController new];vc.view.backgroundColor=UIColor.clearColor;w.rootViewController=vc;self.window=w;
  UIView *card=[UIView new];card.translatesAutoresizingMaskIntoConstraints=NO;card.backgroundColor=[UIColor colorWithRed:.09 green:.12 blue:.18 alpha:.98];card.layer.cornerRadius=24;[vc.view addSubview:card];self.card=card;
  UILabel *title=[UILabel new];title.text=@"تفعيل AZ GPS PRO";title.font=[UIFont boldSystemFontOfSize:20];title.textColor=UIColor.whiteColor;title.textAlignment=NSTextAlignmentCenter;
  self.message=[UILabel new];self.message.text=@"أدخل كود الاشتراك الخاص بهذا التطبيق.";self.message.textColor=[UIColor colorWithWhite:.85 alpha:1];self.message.font=[UIFont systemFontOfSize:14];self.message.numberOfLines=0;self.message.textAlignment=NSTextAlignmentCenter;
  self.field=[UITextField new];self.field.placeholder=@"az-XXXX-XXXX-XXXX";self.field.borderStyle=UITextBorderStyleRoundedRect;self.field.autocorrectionType=UITextAutocorrectionTypeNo;self.field.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;self.field.font=[UIFont systemFontOfSize:14];self.field.text=self.identity.savedCode;
  UIButton *activate=[UIButton buttonWithType:UIButtonTypeSystem];[activate setTitle:@"تفعيل" forState:UIControlStateNormal];[activate addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
  UIButton *retry=[UIButton buttonWithType:UIButtonTypeSystem];[retry setTitle:@"إعادة التحقق" forState:UIControlStateNormal];[retry addTarget:self action:@selector(verify) forControlEvents:UIControlEventTouchUpInside];
  UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setTitle:@"إغلاق" forState:UIControlStateNormal];[close addTarget:self action:@selector(closeActivation) forControlEvents:UIControlEventTouchUpInside];
  UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[title,self.message,self.field,activate,retry,close]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[[card.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],[card.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],[card.widthAnchor constraintEqualToAnchor:vc.view.widthAnchor multiplier:.86],[card.widthAnchor constraintLessThanOrEqualToConstant:360],[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],[stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],[self.field.heightAnchor constraintEqualToConstant:44]]];
 }
 self.window.hidden=NO;
}
- (NSString *)subscriptionSummary {
 NSDictionary *s=self.subscription;
 if(!s)return @"لم يتم التحقق من اشتراك صالح في هذه الجلسة.";
 NSDateFormatter *format=[NSDateFormatter new];format.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"ar"];format.dateFormat=@"yyyy/MM/dd HH:mm";
 double expiry=[s[@"expires_at"]doubleValue];
 double remaining=MAX(0,self.subscriptionDeadline-AZMonotonic());
 NSString *activation=[s[@"activated_at"]isKindOfClass:NSNumber.class]?[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[s[@"activated_at"]doubleValue]]]:@"غير متوفر";
 NSString *end=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:expiry]];
 return [NSString stringWithFormat:@"حالة الاشتراك: %@\nتاريخ التفعيل: %@\nتاريخ الانتهاء: %@\nالأيام المتبقية: %.0f",AZLicenseCanRun()?@"نشط":@"الأداة متوقفة",activation,end,ceil(remaining/86400.0)];
}
- (void)activateTapped {[self.field resignFirstResponder];[self activateCode:self.field.text ?: @""];}
- (void)closeActivation {self.activationRequested=NO;[self.field resignFirstResponder];self.window.hidden=YES;}
@end
