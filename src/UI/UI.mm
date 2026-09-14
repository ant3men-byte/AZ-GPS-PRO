#import "LicenseManager.h"
#import "AZGPS.h"
#import "UI.h"
#import "Audit.h"
#import "Identity.h"

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <cmath>

#pragma mark - Root

@interface AZOverlayWindow : UIWindow
@end

@implementation AZOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {

    UIView *hit = [super hitTest:point withEvent:event];

    // If the window/root itself is the only hit target, do not consume
    // the touch. Returning nil here lets the event continue to the
    // application's normal window underneath AZGPS.
    if (hit == nil ||
        hit == self ||
        hit == self.rootViewController.view) {
        return nil;
    }

    return hit;
}

@end


@interface AZOverlayPassthroughView : UIView
@end

@implementation AZOverlayPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {

    UIView *hit = [super hitTest:point withEvent:event];

    // If the touch lands only on the transparent full-screen root,
    // pass it through to the host application below AZGPS.
    if (hit == self) {
        return nil;
    }

    // AZGPS controls such as the floating button and open panel
    // continue receiving touches normally.
    return hit;
}

@end


@interface AZOverlayRootController : UIViewController
@end

@implementation AZOverlayRootController

- (void)loadView {

    AZOverlayPassthroughView *v =
        [[AZOverlayPassthroughView alloc]
            initWithFrame:UIScreen.mainScreen.bounds];

    v.backgroundColor = UIColor.clearColor;
    v.userInteractionEnabled = YES;

    self.view = v;
}

@end

#pragma mark - UI

@interface AZUIController () <MKMapViewDelegate, UISearchBarDelegate>
@end

@implementation AZUIController {
    UIWindow *_overlayWindow;
    UIButton *_floatingButton;
    UIScrollView *_panel;
    UIView *_content;

    UISearchBar *_searchBar;
    MKMapView *_mapView;
    UILabel *_coordLabel;
    UILabel *_statusLabel;
    UISwitch *_locationSwitch;

    CLLocationCoordinate2D _selectedCoordinate;
    BOOL _hasCoordinate;
}

+ (instancetype)sharedController {
    static AZUIController *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obj = [[AZUIController alloc] init];
    });
    return obj;
}

- (void)installWhenReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(AZLicenseCanRun()){[self installOverlay];if(!self->_panel)[self buildPanel];}
    });
}

- (UIWindowScene *)activeScene API_AVAILABLE(ios(13.0)) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateForegroundInactive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)scene;
    }
    return nil;
}

- (void)installOverlay {
    if(!AZLicenseCanRun())return;
    if (_overlayWindow) {
        _overlayWindow.hidden = NO;
        return;
    }

    AZOverlayWindow *w = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeScene];
        if (!scene) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if(AZLicenseCanRun()){[self installOverlay];if(!self->_panel)[self buildPanel];}
            });
            return;
        }
        w = [[AZOverlayWindow alloc] initWithWindowScene:scene];
    } else {
        w = [[AZOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    w.frame = UIScreen.mainScreen.bounds;
    w.backgroundColor = UIColor.clearColor;
    w.windowLevel = UIWindowLevelAlert + 1000.0;

    AZOverlayRootController *root = [[AZOverlayRootController alloc] init];
    w.rootViewController = root;
    w.hidden = NO;
    _overlayWindow = w;

    [self buildFloatingButton:root.view];
}

#pragma mark - Helpers

- (UIColor *)panelColor {
    return [UIColor colorWithRed:0.105 green:0.11 blue:0.12 alpha:0.985];
}

- (UIColor *)cardColor {
    return [UIColor colorWithRed:0.19 green:0.20 blue:0.21 alpha:0.98];
}

- (UILabel *)label:(NSString *)text frame:(CGRect)frame size:(CGFloat)size bold:(BOOL)bold {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return l;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)frame tint:(UIColor *)tint {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    b.layer.cornerRadius = 13.0;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [tint colorWithAlphaComponent:0.65].CGColor;
    b.backgroundColor = [tint colorWithAlphaComponent:0.23];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.78;
    return b;
}

- (UIView *)card:(CGRect)frame {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = [self cardColor];
    v.layer.cornerRadius = 16.0;
    v.layer.borderWidth = 1.0;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    return v;
}

#pragma mark - Floating

- (void)buildFloatingButton:(UIView *)root {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(18, 160, 62, 62);
    b.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.10 alpha:0.98];
    b.layer.cornerRadius = 31;
    b.layer.borderWidth = 2;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    b.layer.shadowOpacity = 0.35;
    b.layer.shadowRadius = 8;
    [b setTitle:@"\U0001F98A" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:29];
    [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloating:)];
    [b addGestureRecognizer:pan];

    [root addSubview:b];
    _floatingButton = b;
}

- (void)dragFloating:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    UIView *p = v.superview;
    CGPoint t = [g translationInView:p];
    CGPoint c = v.center;
    c.x += t.x;
    c.y += t.y;
    CGFloat hw = CGRectGetWidth(v.bounds)/2.0;
    CGFloat hh = CGRectGetHeight(v.bounds)/2.0;
    c.x = MAX(hw, MIN(CGRectGetWidth(p.bounds)-hw, c.x));
    c.y = MAX(hh, MIN(CGRectGetHeight(p.bounds)-hh, c.y));
    v.center = c;
    [g setTranslation:CGPointZero inView:p];
}

#pragma mark - Panel

- (void)togglePanel {
    if (_panel) [self closePanel];
    else [self buildPanel];
}

- (void)buildPanel {
    if(!AZLicenseCanRun())return;
    UIView *root = _overlayWindow.rootViewController.view;
    if (!root) return;

    CGFloat sw = CGRectGetWidth(root.bounds);
    CGFloat sh = CGRectGetHeight(root.bounds);
    CGFloat pw = MIN(376.0, sw - 34.0);
    CGFloat ph = MIN(820.0, sh - 42.0);
    CGFloat px = (sw-pw)/2.0;
    CGFloat py = MAX(18.0, (sh-ph)/2.0);

    UIScrollView *panel = [[UIScrollView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    panel.backgroundColor = [self panelColor];
    panel.layer.cornerRadius = 28;
    panel.layer.masksToBounds = YES;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    panel.showsVerticalScrollIndicator = NO;

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0,0,pw,875)];
    [panel addSubview:content];
    panel.contentSize = content.bounds.size;

    [root addSubview:panel];
    _panel = panel;
    _content = content;
    _floatingButton.hidden = YES;

    CGFloat W = pw;
    CGFloat margin = 14;
    CGFloat inner = W - margin*2;

    // Header
    UILabel *logo = [self label:@"\U0001F98A  AZ.GPS" frame:CGRectMake(18,14,178,36) size:24 bold:YES];
    [content addSubview:logo];

    UILabel *sub = [self label:@"GPS baseline • iOS 12+" frame:CGRectMake(70,44,180,18) size:11 bold:NO];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    [content addSubview:sub];

    UIButton *support = [self button:@"\u2708\uFE0E  \u0627\u0644\u062F\u0639\u0645" frame:CGRectMake(W-166,12,92,40)
                                tint:[UIColor colorWithRed:0.0 green:0.68 blue:0.92 alpha:1]];
    [support addTarget:self action:@selector(showSupport) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:support];

    UIButton *info = [UIButton buttonWithType:UIButtonTypeSystem];
    info.frame = CGRectMake(W-70,13,38,38);
    info.backgroundColor = [UIColor colorWithRed:0.16 green:0.76 blue:0.29 alpha:1];
    info.layer.cornerRadius = 19;
    [info setTitle:@"\u24D8" forState:UIControlStateNormal];
    [info setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    info.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [info addTarget:self action:@selector(showStatus) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:info];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(W-34,14,28,34);
    [close setTitle:@"\u00D7" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:1 alpha:.65] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:30];
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];

    // Search
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(margin,68,inner,48)];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"\u0628\u062D\u062B \u0639\u0646 \u0645\u0648\u0642\u0639";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.barStyle = UIBarStyleBlack;
    [content addSubview:_searchBar];

    // Save row
    UIColor *orange = [UIColor colorWithRed:.95 green:.55 blue:.0 alpha:1];
    UIColor *green  = [UIColor colorWithRed:.10 green:.72 blue:.30 alpha:1];
    UIColor *red    = [UIColor colorWithRed:.92 green:.23 blue:.20 alpha:1];
    UIColor *cyan   = [UIColor colorWithRed:.0 green:.72 blue:.88 alpha:1];
    UIColor *purple = [UIColor colorWithRed:.58 green:.31 blue:.92 alpha:1];

    CGFloat gap=8, third=(inner-gap*2)/3.0;
    UIButton *saved=[self button:@"\U0001F516 \u0627\u0644\u0645\u062D\u0641\u0648\u0638\u0627\u062A" frame:CGRectMake(margin,124,third,48) tint:orange];
    UIButton *save=[self button:@"\u271A  \u062D\u0641\u0638" frame:CGRectMake(margin+third+gap,124,third,48) tint:green];
    UIButton *restore=[self button:@"\u21B6  \u0627\u0633\u062A\u0639\u0627\u062F\u0629" frame:CGRectMake(margin+(third+gap)*2,124,third,48) tint:red];
    [saved addTarget:self action:@selector(showSaved) forControlEvents:UIControlEventTouchUpInside];
    [save addTarget:self action:@selector(saveCurrent) forControlEvents:UIControlEventTouchUpInside];
    [restore addTarget:self action:@selector(restoreLocation) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:saved]; [content addSubview:save]; [content addSubview:restore];

    // Map
    _mapView = [[MKMapView alloc] initWithFrame:CGRectMake(margin,184,inner,224)];
    _mapView.delegate = self;
    _mapView.layer.cornerRadius = 18;
    _mapView.layer.masksToBounds = YES;
    _mapView.showsUserLocation = YES;
    [content addSubview:_mapView];

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPress:)];
    lp.minimumPressDuration = .3;
    [_mapView addGestureRecognizer:lp];

    UIButton *expand=[self button:@"\u2922" frame:CGRectMake(W-68,198,40,40)
                             tint:[UIColor colorWithWhite:.7 alpha:1]];
    [expand addTarget:self action:@selector(centerSelected) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:expand];

    AZRuntimeState *state=[AZRuntimeState sharedState];
    CLLocationCoordinate2D start = state.locationEnabled ? CLLocationCoordinate2DMake(state.currentLatitude,state.currentLongitude) : CLLocationCoordinate2DMake(24.7136,46.6753);
    [self selectCoordinate:start animated:NO];

    // Map mode row
    UISegmentedControl *mapModes =
        [[UISegmentedControl alloc] initWithItems:@[@"\u0639\u0627\u062F\u064A",@"\u0642\u0645\u0631 \u0635\u0646\u0627\u0639\u064A"]];
    mapModes.frame = CGRectMake(margin,418,inner*0.50-4,42);
    mapModes.selectedSegmentIndex = 0;
    [mapModes addTarget:self action:@selector(mapModeChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:mapModes];

    UIButton *myLocation=[self button:@"\u27A4  \u0645\u0648\u0642\u0639\u064A"
                                frame:CGRectMake(margin+inner*0.50+4,418,inner*0.50-4,42)
                                 tint:cyan];
    [myLocation addTarget:self action:@selector(goMyLocation) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:myLocation];

    // Location switch
    UIView *locCard=[self card:CGRectMake(margin,472,inner,60)];
    [content addSubview:locCard];
    UILabel *locTitle=[self label:@"\u27A4  \u062A\u0641\u0639\u064A\u0644 \u062A\u063A\u064A\u064A\u0631 \u0627\u0644\u0645\u0648\u0642\u0639"
                            frame:CGRectMake(18,8,inner-95,42) size:17 bold:NO];
    [locCard addSubview:locTitle];
    _locationSwitch=[[UISwitch alloc] initWithFrame:CGRectMake(inner-68,13,55,32)];
    [_locationSwitch addTarget:self action:@selector(locationSwitchChanged:)
              forControlEvents:UIControlEventValueChanged];
    [locCard addSubview:_locationSwitch];

    _coordLabel=[self label:@"" frame:CGRectMake(margin,537,inner,20) size:11 bold:NO];
    _coordLabel.textAlignment=NSTextAlignmentCenter;
    _coordLabel.textColor=[UIColor colorWithWhite:1 alpha:.55];
    [content addSubview:_coordLabel];
    [self refreshCoordinate];

    CGFloat half=(inner-gap)/2.0;

    // Device card
    UIView *device=[self card:CGRectMake(margin,563,inner,66)];
    [content addSubview:device];
    UILabel *deviceTitle=[self label:@"\U0001F4F1  \u0645\u0639\u0631\u0641 \u0627\u0644\u062C\u0647\u0627\u0632" frame:CGRectMake(15,10,145,42) size:16 bold:NO];
    [device addSubview:deviceTitle];

    NSArray *deviceButtons=@[@"\u0646\u0633\u062E",@"\u062A\u0639\u0628\u0626\u0629",@"\u0647\u0648\u064A\u0629",@"\u0627\u0633\u062A\u0639\u0627\u062F\u0629"];
    NSArray *deviceColors=@[orange,cyan,purple,green];
    CGFloat dW=(inner-170)/4.0;
    for (NSInteger i=0;i<4;i++) {
        UIButton *b=[self button:deviceButtons[i]
                          frame:CGRectMake(160+i*dW,13,dW-4,38)
                           tint:deviceColors[i]];
        [b addTarget:self action:@selector(deviceAction:) forControlEvents:UIControlEventTouchUpInside];
        b.tag=i;
        [device addSubview:b];
    }

    // Support / shop
    UIButton *shop=[self button:@"\U0001F6D2  \u0634\u0631\u0627\u0621 \u0643\u0648\u062F" frame:CGRectMake(margin,643,half,52) tint:orange];
    UIButton *chat=[self button:@"\u25CF  \u0627\u0644\u062F\u0639\u0645 \u0627\u0644\u0641\u0646\u064A" frame:CGRectMake(margin+half+gap,643,half,52) tint:cyan];
    [shop addTarget:self action:@selector(showSupport) forControlEvents:UIControlEventTouchUpInside];
    [chat addTarget:self action:@selector(showSupport) forControlEvents:UIControlEventTouchUpInside];
    shop.enabled=NO;chat.enabled=NO;shop.alpha=0.4;chat.alpha=0.4;
    [content addSubview:shop]; [content addSubview:chat];

    // Bottom controls
    UIButton *stop=[self button:@"\u23F9  \u0625\u064A\u0642\u0627\u0641 \u0627\u0644\u0643\u0644" frame:CGRectMake(margin,715,half,50) tint:red];
    UIButton *hide=[self button:@"\u25C9\u0338  \u0625\u062E\u0641\u0627\u0621 \u0627\u0644\u0623\u062F\u0627\u0629" frame:CGRectMake(margin+half+gap,715,half,50)
                           tint:[UIColor colorWithWhite:.65 alpha:1]];
    [stop addTarget:self action:@selector(stopAll) forControlEvents:UIControlEventTouchUpInside];
    [hide addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    
    [content addSubview:stop]; [content addSubview:hide];

    UIButton *logs=[self button:@"Logs" frame:CGRectMake(margin,779,inner,46)
                           tint:[UIColor colorWithRed:.42 green:.46 blue:.52 alpha:1]];
    [logs addTarget:self action:@selector(showAuditLogs) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:logs];

    _statusLabel=[self label:@"DEFAULT" frame:CGRectMake(margin,835,inner,20) size:11 bold:NO];
    _statusLabel.textAlignment=NSTextAlignmentCenter;
    _statusLabel.textColor=[UIColor colorWithWhite:1 alpha:.45];
    [content addSubview:_statusLabel];

    [self refreshStatus];
}


#pragma mark - Audit Helpers

- (void)auditErrorResult:(AZError *)error
                 feature:(NSString *)feature
                 details:(NSString *)details {

    BOOL success =
        (error != nil && [error isSuccess]);

    NSString *status =
        success ? @"SUCCESS" : @"ERROR";

    NSString *message =
        details ?: @"";

    if (!success && error != nil) {

        NSString *human =
            error.humanReadableMessage ?: @"";

        NSString *technical =
            error.technicalMessage ?: @"";

        message =
            [NSString stringWithFormat:
                @"code=%ld | human=%@ | technical=%@%@%@",
                (long)error.errorCode,
                human,
                technical,
                message.length ? @" | " : @"",
                message];
    }

    AZAuditLogFeature(
        feature ?: @"unknown",
        status,
        message
    );

    AZAuditLogState(
        feature ?: @"unknown",
        [[AZRuntimeState sharedState] snapshotForUI]
    );
}


- (void)auditStateForFeature:(NSString *)feature
                      status:(NSString *)status
                     details:(NSString *)details {

    AZAuditLogFeature(
        feature ?: @"unknown",
        status ?: @"UNKNOWN",
        details ?: @""
    );

    AZAuditLogState(
        feature ?: @"unknown",
        [[AZRuntimeState sharedState] snapshotForUI]
    );
}

#pragma mark - Map

- (void)mapLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGPoint p=[g locationInView:_mapView];
    CLLocationCoordinate2D c =
        [_mapView convertPoint:p
          toCoordinateFromView:_mapView];

    AZAuditLogFeature(
        @"mapLongPress",
        @"SUCCESS",
        [NSString stringWithFormat:
            @"lat=%.8f | lon=%.8f",
            c.latitude,
            c.longitude]
    );

    [self selectCoordinate:c animated:YES];

    // If static location is already enabled, immediately apply the newly
    // selected coordinate so the runtime and CLLocation hooks stay in sync.
    if (_locationSwitch.isOn) {

        AZAuditLogFeature(
            @"mapLongPressLiveUpdate",
            @"REQUESTED",
            [NSString stringWithFormat:
                @"lat=%.8f | lon=%.8f",
                c.latitude,
                c.longitude]
        );

        AZError *e =
            [[AZAppManager sharedManager]
                activateStaticLocationWithLatitude:c.latitude
                longitude:c.longitude];

        [self auditErrorResult:
            e
            feature:@"mapLongPressLiveUpdate"
            details:[NSString stringWithFormat:
                @"lat=%.8f | lon=%.8f",
                c.latitude,
                c.longitude]];
    }
}

- (void)selectCoordinate:(CLLocationCoordinate2D)c animated:(BOOL)animated {
    _selectedCoordinate=c;
    _hasCoordinate=YES;

    NSMutableArray *remove=[NSMutableArray array];
    for (id<MKAnnotation> a in _mapView.annotations) {
        if (![a isKindOfClass:MKUserLocation.class]) [remove addObject:a];
    }
    [_mapView removeAnnotations:remove];

    MKPointAnnotation *pin=[[MKPointAnnotation alloc] init];
    pin.coordinate=c;
    pin.title=@"Selected Location";
    [_mapView addAnnotation:pin];

    MKCoordinateRegion r=MKCoordinateRegionMakeWithDistance(c,650000,650000);
    [_mapView setRegion:r animated:animated];
    [self refreshCoordinate];
}

- (void)refreshCoordinate {
    if (!_coordLabel || !_hasCoordinate) return;
    _coordLabel.text=[NSString stringWithFormat:@"%.6f   %.6f",
                      _selectedCoordinate.latitude,_selectedCoordinate.longitude];
}

- (void)mapModeChanged:(UISegmentedControl *)s {

    _mapView.mapType =
        s.selectedSegmentIndex == 0
            ? MKMapTypeStandard
            : MKMapTypeSatellite;

    AZAuditLogFeature(
        @"mapModeChanged",
        @"SUCCESS",
        [NSString stringWithFormat:
            @"selectedIndex=%ld | mapType=%@",
            (long)s.selectedSegmentIndex,
            s.selectedSegmentIndex == 0
                ? @"STANDARD"
                : @"SATELLITE"]
    );
}

- (void)centerSelected {

    if (!_hasCoordinate) {

        AZAuditLogFeature(
            @"centerSelected",
            @"ERROR",
            @"No selected coordinate"
        );

        return;
    }

    MKCoordinateRegion r =
        MKCoordinateRegionMakeWithDistance(
            _selectedCoordinate,
            1500,
            1500
        );

    [_mapView setRegion:r animated:YES];

    AZAuditLogFeature(
        @"centerSelected",
        @"SUCCESS",
        [NSString stringWithFormat:
            @"lat=%.8f | lon=%.8f",
            _selectedCoordinate.latitude,
            _selectedCoordinate.longitude]
    );
}

- (void)goMyLocation {
    AZAuditLogFeature(@"goMyLocation",@"REQUESTED",@"Requesting fresh real device location");
    __weak AZUIController *weakSelf=self;
    AZRequestRealLocation(^(CLLocation *location,NSError *error) {
        AZUIController *selfRef=weakSelf;
        if (!selfRef) return;
        if (!location) {
            AZAuditLogFeature(@"goMyLocation",@"ERROR",error.localizedDescription);
            [selfRef alert:error.localizedDescription ?: @"تعذر الحصول على الموقع الحقيقي."];
            return;
        }
        AZAuditLogLocation(@"goMyLocation.real",location);
        [selfRef selectCoordinate:location.coordinate animated:YES];
        [selfRef centerSelected];
    });
}

#pragma mark - Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {

    NSString *q = searchBar.text;

    if (!q.length) {

        AZAuditLogFeature(
            @"searchLocation",
            @"ERROR",
            @"Empty search query"
        );

        return;
    }

    AZAuditLogFeature(
        @"searchLocation",
        @"REQUESTED",
        [NSString stringWithFormat:
            @"query=%@",
            q]
    );
    [searchBar resignFirstResponder];

    MKLocalSearchRequest *req=[[MKLocalSearchRequest alloc] init];
    req.naturalLanguageQuery=q;
    MKLocalSearch *search=[[MKLocalSearch alloc] initWithRequest:req];

    __weak AZUIController *weakSelf=self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        AZUIController *selfRef=weakSelf;
        if (!selfRef) return;
        if (error || !response.mapItems.count) {
            [selfRef alert:@"\u0644\u0645 \u064A\u062A\u0645 \u0627\u0644\u0639\u062B\u0648\u0631 \u0639\u0644\u0649 \u0627\u0644\u0645\u0648\u0642\u0639."];
            return;
        }
        MKMapItem *item=response.mapItems.firstObject;
        dispatch_async(dispatch_get_main_queue(), ^{
            [selfRef selectCoordinate:item.placemark.coordinate animated:YES];
            if (selfRef->_locationSwitch.isOn) { [[AZAppManager sharedManager] activateStaticLocationWithLatitude:item.placemark.coordinate.latitude longitude:item.placemark.coordinate.longitude]; }
        });
    }];
}

#pragma mark - Core actions

- (void)locationSwitchChanged:(UISwitch *)s {

    AZAuditLogFeature(
        @"locationSwitchChanged",
        @"REQUESTED",
        s.isOn ? @"requested=ON" : @"requested=OFF"
    );

    if (s.isOn) {

        if (!_hasCoordinate) {

            s.on = NO;

            [self auditStateForFeature:
                @"locationSwitchChanged"
                status:@"ERROR"
                details:@"No selected coordinate"];

            [self alert:@"\u062d\u062f\u062f \u0645\u0648\u0642\u0639\u0627\u064b \u0623\u0648\u0644\u0627\u064b."];

            return;
        }

        AZError *e =
            [[AZAppManager sharedManager]
                activateStaticLocationWithLatitude:
                    _selectedCoordinate.latitude
                longitude:
                    _selectedCoordinate.longitude];

        [self auditErrorResult:
            e
            feature:@"activateStaticLocation"
            details:[NSString stringWithFormat:
                @"requestedLat=%.8f | requestedLon=%.8f",
                _selectedCoordinate.latitude,
                _selectedCoordinate.longitude]];

        if (![e isSuccess]) {

            s.on = NO;

            [self alert:
                e.humanReadableMessage
                    ?: @"\u062a\u0639\u0630\u0631 \u062a\u0641\u0639\u064a\u0644 \u0627\u0644\u0645\u0648\u0642\u0639."];
        }
    }
    else {

        AZError *e =
            [[AZAppManager sharedManager]
                restoreDefaultLocation];

        [self auditErrorResult:
            e
            feature:@"restoreDefaultLocation"
            details:@"source=locationSwitchChanged"];
    }

    [self refreshStatus];
}


- (void)restoreLocation {
    AZError *result=[[AZAppManager sharedManager] restoreDefaultLocation];
    [self refreshStatus];
    if (![result isSuccess]) { [self alert:result.humanReadableMessage]; return; }
    // Simulation is disabled before requesting the device position.
    [self goMyLocation];
}

- (void)saveCurrent {

    AZAuditLogFeature(
        @"saveCurrent",
        @"REQUESTED",
        @"Save button pressed"
    );

    if (!_hasCoordinate) {

        [self auditStateForFeature:
            @"saveCurrent"
            status:@"ERROR"
            details:@"No selected coordinate"];

        [self alert:@"\u062d\u062f\u062f \u0645\u0648\u0642\u0639\u0627\u064b \u0623\u0648\u0644\u0627\u064b."];

        return;
    }

    AZError *e =
        [[AZLocationService sharedService]
            addFavoriteWithName:@"AZGPS Location"
            latitude:_selectedCoordinate.latitude
            longitude:_selectedCoordinate.longitude];

    AZAuditLogFeature(
        @"saveCurrent",
        [e isSuccess] ? @"SUCCESS" : @"ERROR",
        [NSString stringWithFormat:
            @"lat=%.8f | lon=%.8f | code=%ld | message=%@",
            _selectedCoordinate.latitude,
            _selectedCoordinate.longitude,
            (long)e.errorCode,
            e.humanReadableMessage ?: @""]
    );

    AZAuditLogState(
        @"saveCurrent",
        [[AZRuntimeState sharedState] snapshotForUI]
    );

    [self alert:
        [e isSuccess]
            ? @"\u062a\u0645 \u062d\u0641\u0638 \u0627\u0644\u0645\u0648\u0642\u0639 \u2705"
            : (e.humanReadableMessage
                ?: @"\u062a\u0639\u0630\u0631 \u0627\u0644\u062d\u0641\u0638.")];
}


- (void)showSaved {
    NSArray<AZLocationModel *> *items=[[AZLocationService sharedService] favorites];
    if (!items.count) { [self alert:@"لا توجد مواقع محفوظة. حدد موقعًا واضغط حفظ أولًا."]; return; }
    UIAlertController *list=[UIAlertController alertControllerWithTitle:@"المواقع المحفوظة"
        message:@"اختر موقعًا للانتقال إليه وتفعيله"
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak AZUIController *weakSelf=self;
    for (AZLocationModel *item in items) {
        NSString *title=[NSString stringWithFormat:@"%@ — %.6f, %.6f",item.name,item.latitude,item.longitude];
        [list addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            AZUIController *selfRef=weakSelf;
            if (!selfRef) return;
            AZError *result=[[AZAppManager sharedManager] activateStaticLocationWithLatitude:item.latitude longitude:item.longitude];
            [selfRef auditErrorResult:result feature:@"activateSavedLocation" details:item.locationID];
            if (![result isSuccess]) { [selfRef alert:result.humanReadableMessage]; return; }
            [selfRef selectCoordinate:CLLocationCoordinate2DMake(item.latitude,item.longitude) animated:YES];
            [selfRef centerSelected];
            [selfRef refreshStatus];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *presenter=_overlayWindow.rootViewController;
    while (presenter.presentedViewController) presenter=presenter.presentedViewController;
    // Action sheets need an anchor on iPad.
    list.popoverPresentationController.sourceView=_panel ?: presenter.view;
    list.popoverPresentationController.sourceRect=CGRectMake(14,124,80,48);
    [presenter presentViewController:list animated:YES completion:nil];
}


- (UIViewController *)presenter {
    UIViewController *vc=_overlayWindow.rootViewController;
    while(vc.presentedViewController)vc=vc.presentedViewController;
    return vc;
}
- (void)deviceAction:(UIButton *)sender {
    AZAppManager *manager=AZAppManager.sharedManager;
    if(sender.tag==0){
        NSString *value=AZCurrentIdentity();
        if(!value.length){[self alert:@"معرف التطبيق غير متاح حاليًا من iOS."];return;}
        UIPasteboard.generalPasteboard.string=value;
        [self alert:[NSString stringWithFormat:@"تم نسخ المعرف الذي يراه التطبيق الآن:\n%@",value]];
    }else if(sender.tag==1){
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"تعبئة معرف الجهاز" message:@"أدخل UUID لتفعيل استبدال identifierForVendor داخل التطبيق. يبقى محفوظًا بعد إعادة تشغيل التطبيق." preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field){
            field.placeholder=@"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
            field.text=AZSavedIdentity().length?AZSavedIdentity():AZCurrentIdentity();
            field.autocorrectionType=UITextAutocorrectionTypeNo;field.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"حفظ وتفعيل" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            
            // Empty input is invalid here; restoration has its own button.
            if(![alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length){
                [self alert:@"أدخل UUID صالحًا."];return;
            }
            AZError *result=[manager setActiveDeviceProfileWithID:alert.textFields.firstObject.text];
            if(!result.isSuccess){[self alert:@"UUID غير صالح. مثال: 550E8400-E29B-41D4-A716-446655440000"];return;}
            [self alert:[NSString stringWithFormat:@"المعرف المفعّل:\n%@",AZCurrentIdentity()]];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
        [[self presenter]presentViewController:alert animated:YES completion:nil];
    }else if(sender.tag==2){
        NSString *value=NSUUID.UUID.UUIDString;
        AZError *result=[manager setActiveDeviceProfileWithID:value];
        if(!result.isSuccess){[self alert:result.humanReadableMessage];return;}
        [self alert:[NSString stringWithFormat:@"تم توليد وحفظ وتفعيل هوية جديدة:\n%@",AZCurrentIdentity()]];
    }else if(sender.tag==3){
        [manager setActiveDeviceProfileWithID:@""];
        NSString *value=AZCurrentIdentity();
        [self alert:value.length?[NSString stringWithFormat:@"تمت استعادة المعرف الأصلي:\n%@",value]:@"تم تعطيل الاستبدال. المعرف الأصلي غير متاح حاليًا من iOS."];
    }
}

- (void)stopAll {
    AZError *result=[AZAppManager.sharedManager restoreDefaultLocation];
    [self refreshStatus];
    if(!result.isSuccess)[self alert:result.humanReadableMessage];
}

- (void)refreshStatus {
    BOOL active=AZRuntimeState.sharedState.locationEnabled;
    _statusLabel.text=active ? @"LOCATION ACTIVE" : @"DEFAULT";
    _locationSwitch.on=active;
}

#pragma mark - Audit Logs

- (void)showAuditLogs {
    AZAuditLogNSString(
        @"UI",
        @"Logs viewer requested"
    );

    UIViewController *vc = _overlayWindow.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }

    AZAuditPresentLogs(vc);
}

#pragma mark - Informational

- (void)showStatus {
    NSDictionary *s=[[AZRuntimeState sharedState] snapshotForUI];
    NSString *m=[NSString stringWithFormat:
                 @"Location: %@\nLat: %.6f\nLon: %.6f\nLast: %@",
                 [s[@"locationEnabled"] boolValue] ? @"Active" : @"Default",
                 [s[@"currentLatitude"] doubleValue],
                 [s[@"currentLongitude"] doubleValue],
                 s[@"lastAction"] ?: @""];
    [self alert:m];
}

- (void)showSupport {
    [self alert:@"AZ.GPS"];
}

- (void)alert:(NSString *)message {
    UIViewController *vc=_overlayWindow.rootViewController;
    while (vc.presentedViewController) vc=vc.presentedViewController;

    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"AZ.GPS"
                                                             message:message ?: @""
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                         style:UIAlertActionStyleDefault
                                       handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}


- (void)hideForLicense {
    if(_panel)[self closePanel];
    _overlayWindow.hidden=YES;
}

#pragma mark - Close

- (void)closePanel {
    [_searchBar resignFirstResponder];
    [_panel removeFromSuperview];

    _panel=nil;
    _content=nil;
    _searchBar=nil;
    _mapView=nil;
    _coordLabel=nil;
    _statusLabel=nil;
    _locationSwitch=nil;

    _floatingButton.hidden=NO;
}

@end

