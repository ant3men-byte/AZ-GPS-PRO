#import <Foundation/Foundation.h>

#pragma mark - AZLogger

typedef NS_ENUM(NSInteger, AZLogCategory) {
    AZLogCore,
    AZLogLocation,
    AZLogDevice,
    AZLogStorage,
    AZLogUI
};

@interface AZLogger : NSObject

+ (instancetype)sharedLogger;
- (void)logCategory:(AZLogCategory)category
            message:(NSString *)message;

@end


#pragma mark - AZError

typedef NS_ENUM(NSInteger, AZErrorCode) {
    AZErrorCodeSuccess            = 0,
    AZErrorCodeInvalidInput       = 1,
    AZErrorCodeNotAvailable       = 2,
    AZErrorCodeNetworkError       = 3,
    AZErrorCodeConflict           = 4,
    AZErrorCodeStorageError       = 5,
    AZErrorCodeUnsupportedVersion = 6,
};

@interface AZError : NSObject

@property (nonatomic, readonly) AZErrorCode errorCode;
@property (nonatomic, readonly, copy) NSString *humanReadableMessage;
@property (nonatomic, readonly, copy) NSString *technicalMessage;

+ (instancetype)errorWithCode:(AZErrorCode)code
                    technical:(NSString *)technicalMessage;

+ (instancetype)success;

- (BOOL)isSuccess;

@end


#pragma mark - AZEventBus

extern NSString * const AZEventLocationChanged;
extern NSString * const AZEventRuntimeStateChanged;
extern NSString * const AZEventErrorOccurred;

@interface AZEventBus : NSObject

+ (instancetype)sharedBus;

- (void)subscribe:(NSString *)eventName
         observer:(id)observer
            block:(void (^)(NSDictionary *payload))block;

- (void)unsubscribe:(id)observer;

- (void)publish:(NSString *)eventName
        payload:(NSDictionary *)payload;

@end


#pragma mark - AZRuntimeState

typedef NS_ENUM(NSInteger, AZLocationMode) {
    AZLocationModeDefault  = 0,
    AZLocationModeStatic   = 1,
};

@protocol AZRuntimeStateMutable <NSObject>

@property (nonatomic, assign, readwrite) BOOL locationEnabled;
@property (nonatomic, assign, readwrite) double currentLatitude;
@property (nonatomic, assign, readwrite) double currentLongitude;
@property (nonatomic, assign, readwrite) AZLocationMode locationMode;




@property (nonatomic, copy, readwrite) NSString *activeDeviceProfileID;


@property (nonatomic, copy, readwrite) NSString *lastAction;
@property (nonatomic, copy, readwrite) NSString *lastError;

@end


@interface AZRuntimeState : NSObject

+ (instancetype)sharedState;

@property (nonatomic, readonly) BOOL locationEnabled;
@property (nonatomic, readonly) double currentLatitude;
@property (nonatomic, readonly) double currentLongitude;
@property (nonatomic, readonly) AZLocationMode locationMode;




@property (nonatomic, readonly, copy) NSString *activeDeviceProfileID;


@property (nonatomic, readonly, copy) NSString *lastAction;
@property (nonatomic, readonly, copy) NSString *lastError;

- (void)performUpdate:
    (void (^)(id<AZRuntimeStateMutable> state))updateBlock;

- (NSDictionary *)snapshotForUI;

- (void)resetToDefaultEnvironment;

@end


#pragma mark - AZSettingsStore

@interface AZSettingsStore : NSObject

+ (instancetype)sharedStore;

- (void)setObjectForKey:(NSString *)key value:(id)value;
- (id)objectForKey:(NSString *)key;

- (void)setStringForKey:(NSString *)key value:(NSString *)value;
- (NSString *)stringForKey:(NSString *)key;

- (void)setDoubleForKey:(NSString *)key value:(double)value;
- (double)doubleForKey:(NSString *)key;

- (void)setBoolForKey:(NSString *)key value:(BOOL)value;
- (BOOL)boolForKey:(NSString *)key;

- (void)setArrayForKey:(NSString *)key value:(NSArray *)value;
- (NSArray *)arrayForKey:(NSString *)key;

- (void)setDictionaryForKey:(NSString *)key
                      value:(NSDictionary *)value;

- (NSDictionary *)dictionaryForKey:(NSString *)key;

- (void)removeKey:(NSString *)key;

@end


#pragma mark - AZLocationModel

@interface AZLocationModel : NSObject

@property (nonatomic, copy, readonly) NSString *locationID;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, copy, readonly) NSDate *createdAt;

+ (instancetype)locationWithName:(NSString *)name
                        latitude:(double)latitude
                       longitude:(double)longitude;

- (BOOL)coordinateIsValid;

- (NSDictionary *)toDictionary;

+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end


#pragma mark - AZLocationService

@interface AZLocationService : NSObject

+ (instancetype)sharedService;

- (AZError *)setLocationWithLatitude:(double)latitude
                           longitude:(double)longitude;

- (BOOL)isLocationActive;

- (NSDictionary *)currentLocation;

- (AZError *)clearLocation;

- (AZError *)restoreDefault;

- (NSArray<AZLocationModel *> *)favorites;

- (AZError *)addFavoriteWithName:(NSString *)name
                        latitude:(double)latitude
                       longitude:(double)longitude;

- (AZError *)renameFavoriteWithID:(NSString *)locationID
                          newName:(NSString *)newName;

- (AZError *)deleteFavoriteWithID:(NSString *)locationID;

- (AZError *)activateFavoriteWithID:(NSString *)locationID;

@end


#pragma mark - AZAppManager

@interface AZAppManager : NSObject

+ (instancetype)sharedManager;

- (void)initialize;

- (AZError *)activateStaticLocationWithLatitude:(double)latitude
                                      longitude:(double)longitude;

- (AZError *)restoreDefaultLocation;

- (AZError *)setActiveDeviceProfileWithID:(NSString *)profileID;


@end
@class CLLocation;
/// Fresh real device location, independent of the simulation state. Main-thread completion.
void AZRequestRealLocation(void (^completion)(CLLocation *location, NSError *error));

