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
    NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
    if (files.count != 1) {
        return NO;
    }
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
    [self.delegate didDragFileUrl:files.firstObject];
    return YES;
}
@end
