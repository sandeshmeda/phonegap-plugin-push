//
//  AppDelegate+notification.m
//  pushtest
//
//  Created by Robert Easterday on 10/26/12.
//
//

#import "AppDelegate+notification.h"
#import "PushPlugin.h"
#import <objc/runtime.h>

static char launchNotificationKey;

@implementation AppDelegate (notification)

- (id) getCommandInstance:(NSString*)className
{
    return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    Method original, swizzled;

    original = class_getInstanceMethod(self, @selector(init));
    swizzled = class_getInstanceMethod(self, @selector(swizzled_init));
    method_exchangeImplementations(original, swizzled);
}

- (AppDelegate *)swizzled_init
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNotificationChecker:)
                                                 name:@"UIApplicationDidFinishLaunchingNotification" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onApplicationDidBecomeActive:)
                                              name:@"UIApplicationDidBecomeActiveNotification" object:nil];

    // This actually calls the original init method over in AppDelegate. Equivilent to calling super
    // on an overrided method, this is not recursive, although it appears that way. neat huh?
    return [self swizzled_init];
}

// This code will be called immediately after application:didFinishLaunchingWithOptions:. We need
// to process notifications in cold-start situations
- (void)createNotificationChecker:(NSNotification *)notification
{
    NSLog(@"createNotificationChecker");

    if (notification)
    {
        NSDictionary *launchOptions = [notification userInfo];
        if (launchOptions)
            self.launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
    }
}

- (void)onApplicationDidBecomeActive:(NSNotification *)notification
{
  NSLog(@"onApplicationDidBecomeActive");
  
  UIApplication *application = notification.object;

  application.applicationIconBadgeNumber = 0;
  
  if (self.launchNotification) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    
    pushHandler.notificationMessage = self.launchNotification;
    self.launchNotification = nil;
    [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
  }
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
}

// this method is invoked when:
// - a regular notification is tapped
// - an interactive notification is tapped, but not one of its buttons
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
  NSLog(@"didReceiveNotification");
  
  if (application.applicationState == UIApplicationStateActive) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    pushHandler.notificationMessage = userInfo;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];
  } else {
    //save it for later
    self.launchNotification = userInfo;
  }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSLog(@"didReceiveNotification with fetchCompletionHandler");

    // app is in the foreground so call notification callback
    if (application.applicationState == UIApplicationStateActive) {
        NSLog(@"app active");
        PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
        pushHandler.notificationMessage = userInfo;
        pushHandler.isInline = YES;
        [pushHandler notificationReceived];

        completionHandler(UIBackgroundFetchResultNewData);
    }
    // app is in background or in stand by
    else {
        NSLog(@"app in-active");

        // do some convoluted logic to find out if this should be a silent push.
        long silent = 0;
        id aps = [userInfo objectForKey:@"aps"];
        id contentAvailable = [aps objectForKey:@"content-available"];
        if ([contentAvailable isKindOfClass:[NSString class]] && [contentAvailable isEqualToString:@"1"]) {
            silent = 1;
        } else if ([contentAvailable isKindOfClass:[NSNumber class]]) {
            silent = [contentAvailable integerValue];
        }

        if (silent == 1) {
            NSLog(@"this should be a silent push");
            void (^safeHandler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result){
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(result);
                });
            };

            NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
            [params setObject:safeHandler forKey:@"handler"];

            PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;
            pushHandler.handlerObj = params;
            [pushHandler notificationReceived];
        } else {
            NSLog(@"just put it in the shade");
            //save it for later
            self.launchNotification = userInfo;

            completionHandler(UIBackgroundFetchResultNewData);
        }
    }
}

- (BOOL)userHasRemoteNotificationsEnabled {
    UIApplication *application = [UIApplication sharedApplication];
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        return application.currentUserNotificationSettings.types != UIUserNotificationTypeNone;
    } else {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        return application.enabledRemoteNotificationTypes != UIRemoteNotificationTypeNone;
#pragma GCC diagnostic pop
    }
}

//- (void)applicationDidBecomeActive:(UIApplication *)application {
//
//    NSLog(@"applicationDidBecomeActive");
//
//    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
//    if (pushHandler.clearBadge) {
//        NSLog(@"PushPlugin clearing badge");
//        //zero badge
//        application.applicationIconBadgeNumber = 0;
//    } else {
//       NSLog(@"PushPlugin skip clear badge");
//    }
//
//    if (self.launchNotification) {
//        pushHandler.isInline = NO;
//        pushHandler.notificationMessage = self.launchNotification;
//        self.launchNotification = nil;
//        [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
//    }
//}


- (void)application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier
forRemoteNotification: (NSDictionary *) notification completionHandler: (void (^)()) completionHandler {

    NSLog(@"Push Plugin handleActionWithIdentifier %@", identifier);

    NSMutableDictionary *userInfo = [notification mutableCopy];
    [userInfo setObject:identifier forKey:@"callback"];

    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    pushHandler.notificationMessage = userInfo;
    pushHandler.isInline = NO;

    void (^safeHandler)() = ^(){
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    };

    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    [params setObject:safeHandler forKey:@"handler"];
    pushHandler.handlerObj = params;
    [pushHandler notificationReceived];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
// this method is invoked when:
// - one of the buttons of an interactive notification is tapped
// see https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/IPhoneOSClientImp.html#//apple_ref/doc/uid/TP40008194-CH103-SW1
// THIS SEEMS TO BE iOS9 ONLY
- (void)application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier forRemoteNotification: (NSDictionary *) notification withResponseInfo:(NSDictionary *)responseInfo completionHandler: (void (^)()) completionHandler {

  NSLog(@"Push Plugin handleActionWithIdentifier %@ and responseInfo", identifier);
  NSMutableDictionary *userInfo = [notification mutableCopy];

  [userInfo setObject:identifier forKey:@"callback"];
    
  if(responseInfo != nil){
    NSString *textInput = [[NSString alloc]initWithFormat:@"%@",[responseInfo objectForKey:@"UIUserNotificationActionResponseTypedTextKey"]];
    [userInfo setValue:textInput forKey:@"textInput"];
  }

  if (application.applicationState == UIApplicationStateActive) {
    NSLog(@"app is active");
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    pushHandler.notificationMessage = userInfo;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];
  } else {
    NSLog(@"app is inactive");
    void (^safeHandler)() = ^(){
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    };
    
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    [params setObject:safeHandler forKey:@"handler"];
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];    
    pushHandler.notificationMessage = userInfo;
    pushHandler.isInline = NO;
    pushHandler.handlerObj = params;
    [pushHandler notificationReceived];
  }
}
#endif
  

// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
    return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
    self.launchNotification = nil; // clear the association and release the object
}

@end
