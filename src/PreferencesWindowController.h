#import <Cocoa/Cocoa.h>

@interface PreferencesWindowController : NSWindowController

+ (instancetype)shared;
- (void)showWindow;

@end
