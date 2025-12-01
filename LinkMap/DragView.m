//
//  DragView.m
//  LinkMap
//
//  Created by Leon on 2022/12/30.
//  Copyright © 2022 ND. All rights reserved.
//

#import "DragView.h"

@implementation DragView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    NSArray<NSPasteboardItem *> *items = [pb pasteboardItems];
    NSUInteger fileCount = 0;
    for (NSPasteboardItem *item in items) {
        NSString *urlString = [item stringForType:NSPasteboardTypeFileURL];
        if (urlString.length > 0) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url.isFileURL) {
                fileCount++;
            }
        }
    }
    if (fileCount != 1) {
        return NO;
    }
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    NSArray<NSPasteboardItem *> *items = [pb pasteboardItems];
    for (NSPasteboardItem *item in items) {
        NSString *urlString = [item stringForType:NSPasteboardTypeFileURL];
        if (urlString.length > 0) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url.isFileURL) {
                [self.delegate didDragFileUrl:url.path];
                break;
            }
        }
    }
    return YES;
}
@end
