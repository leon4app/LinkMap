//
//  AppDelegate.m
//  LinkMap
//
//  Created by Suteki(67111677@qq.com) on 4/8/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate () <NSWindowDelegate>

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApplication sharedApplication].windows.firstObject.delegate = self;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    sender.releasedWhenClosed = NO;
    [sender orderOut:self];
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [sender.windows.firstObject makeKeyAndOrderFront:self];
    }
    return YES;
}
@end
