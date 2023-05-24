//
//  DragView.h
//  LinkMap
//
//  Created by Leon on 2022/12/30.
//  Copyright © 2022 ND. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@protocol DragViewDelegate <NSObject>

- (void)didDragFileUrl:(NSString *)url;

@end

@interface DragView : NSScrollView
@property (nonatomic, weak) id<DragViewDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
