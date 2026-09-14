#import "LicenseManager.h"
#import "InstallationIdentity.h"
#import "LicenseAPIClient.h"
#import "AZGPS.h"
#import "UI.h"
#import "Audit.h"
#import <UIKit/UIKit.h>
#import <Network/Network.h>
#import <mach/mach_time.h>
#import <atomic>
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
@property(nonatomic,strong) NSTimer *timer;
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
@end
@implementation AZLicenseManager
+ (instancetype)sharedManager {static AZLicenseManager *m;static dispatch_once_t once;dispatch_once(&once,^{m=[self new];m.identity=[AZInstallationIdentity new];m.api=[AZLicenseAPIClient new];m.pathAvailable=YES;});return m;}
- (void)start {
 if(self.started)return;self.started=YES;
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
 self.monitor=nw_path_monitor_create();nw_path_monitor_set_queue(self.monitor,dispatch_get_main_queue());
 __weak AZLicenseManager *weak=self;
 nw_path_monitor_set_update_handler(self.monitor,^(nw_path_t path){AZLicenseManager *m=weak;if(!m)return;BOOL available=nw_path_get_status(path)==nw_path_status_satisfied;BOOL changed=m.pathAvailable!=available;m.pathAvailable=available;if(!available){m.generation++;m.busy=NO;[m disable];m.message.text=@"لا يوجد اتصال. الأداة متوقفة حتى ينجح التحقق.";}else if(changed&&m.active)[m verify];});nw_path_monitor_start(self.monitor);
 self.tapWindows=[NSHashTable weakObjectsHashTable];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(windowVisible:) name:UIWindowDidBecomeVisibleNotification object:nil];
 [self installTapGestures];
 self.timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *t){AZLicenseManager *m=weak;if(!m||!m.active)return;[m installTapGestures];if(AZAuthorized.load()&&!AZLicenseCanRun()){[m disable];if(m.subscriptionDeadline>0&&AZMonotonic()>=m.subscriptionDeadline){[m showActivation];m.message.text=[m friendly:@"expired"];}}static double lastVerify=0;if(AZMonotonic()-lastVerify>=60){lastVerify=AZMonotonic();[m verify];}}];[[NSRunLoop mainRunLoop]addTimer:self.timer forMode:NSRunLoopCommonModes];
 self.active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
 if(self.active)[self begin];
}
- (void)begin {if(!self.identity.savedCode.length)[self showActivation];else [self verify];}
- (void)foreground:(NSNotification *)note {self.active=YES;[self installTapGestures];[self disable];[self begin];}
- (void)background:(NSNotification *)note {self.active=NO;self.generation++;self.busy=NO;[self disable];self.window.hidden=YES;}
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
 if(!self.pathAvailable){[self disable];return;}
 NSError *identityError=nil;if(![self.identity prepare:&identityError]){[self disable];[self showActivation];self.message.text=identityError.localizedDescription ?: @"تعذر إعداد هوية الترخيص.";return;}
 self.busy=YES;NSUInteger gen=++self.generation;double start=AZMonotonic();self.message.text=@"جارٍ التحقق…";
 NSDictionary *body=@{@"key":code,@"installation_id":self.identity.installationID,@"bundle_id":NSBundle.mainBundle.bundleIdentifier ?: @"unknown",@"public_key":self.identity.publicKey};
 [self.api post:@"/license/challenge" body:body completion:^(NSDictionary *challenge,NSError *error){
  if(gen!=self.generation)return;
  if(error){[self failed:error code:challenge[@"error"]];return;}
  if(![challenge[@"message"]isKindOfClass:NSString.class]||![challenge[@"challenge_id"]isKindOfClass:NSString.class]){[self failed:nil code:@"invalid_server_signature"];return;}
  NSError *signError=nil;NSString *signature=[self.identity signMessage:challenge[@"message"] error:&signError];
  if(!signature){[self failed:signError code:nil];return;}
  [self.api post:@"/license/verify" body:@{@"challenge_id":challenge[@"challenge_id"],@"signature":signature} completion:^(NSDictionary *envelope,NSError *verifyError){
   if(gen!=self.generation)return;self.busy=NO;
   if(verifyError){[self failed:verifyError code:envelope[@"error"]];return;}
   NSError *leaseError=nil;NSDictionary *lease=[self.api validateLease:envelope installation:self.identity.installationID bundle:NSBundle.mainBundle.bundleIdentifier ?: @"unknown" error:&leaseError];
   if(!lease||![lease[@"challenge_id"]isEqual:challenge[@"challenge_id"]]||!self.pathAvailable||!self.active){[self failed:leaseError code:@"invalid_server_signature"];return;}
   double ttl=[lease[@"lease_expires_at"]doubleValue]-[lease[@"server_time"]doubleValue]-(AZMonotonic()-start);
   if(ttl<=0){[self failed:nil code:@"expired"];return;}
   if(![self.identity saveCode:code error:&leaseError]){[self disable];self.message.text=leaseError.localizedDescription;return;}
   self.subscriptionDeadline=AZMonotonic()+[lease[@"expires_at"]doubleValue]-[lease[@"server_time"]doubleValue]-(AZMonotonic()-start);
   self.pendingCode=nil;AZDeadline.store(AZMonotonic()+ttl);AZAuthorized.store(true);
   [[AZAppManager sharedManager]initialize];
   self.window.hidden=YES;self.message.text=@"تم التفعيل. انقر الشاشة ثلاث مرات متتالية لإظهار الأداة.";
   AZAuditLogFeature(@"license",@"VALID",@"Online verification succeeded; protected UI remains hidden");
  }];
 }];
}
- (void)failed:(NSError *)error code:(NSString *)code {
 self.busy=NO;[self disable];
 BOOL show=self.pendingCode.length||[@[@"expired",@"revoked",@"suspended",@"invalid",@"device_limit",@"wrong_app"]containsObject:code ?: @""];
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
 if(AZLicenseCanRun())[[AZUIController sharedController]installWhenReady];
 else if(self.identity.savedCode.length){[self showActivation];[self verify];}else [self showActivation];
}
- (UIWindowScene *)scene API_AVAILABLE(ios(13.0)) {for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive)return (UIWindowScene *)s;return nil;}
- (void)showActivation {
 if(!self.active)return;
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
- (void)activateTapped {[self.field resignFirstResponder];[self activateCode:self.field.text ?: @""];}
- (void)closeActivation {[self.field resignFirstResponder];self.window.hidden=YES;}
@end
