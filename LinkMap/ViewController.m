//
//  ViewController.m
//  LinkMap
//
//  Created by Suteki(67111677@qq.com) on 4/8/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "ViewController.h"
#import "SymbolModel.h"
#import "DragView.h"
#import "LinkMap-Swift.h"
@interface ViewController() <DragViewDelegate>

@property (weak) IBOutlet NSTextField *filePathField;//显示选择的文件路径
@property (weak) IBOutlet NSProgressIndicator *indicator;//指示器
@property (weak) IBOutlet NSTextField *binaryRuleField;
@property (weak) IBOutlet NSTextField *assetsRuleField;

@property (weak) IBOutlet NSTextView *contentTextView;
@property (weak) IBOutlet NSButton *groupButton;
@property (weak) IBOutlet DragView *dragView;


@property (strong) NSURL *linkMapFileURL;
@property (strong) NSString *linkMapContent;

@property (copy) NSString *searchText;

@property (strong) NSMutableAttributedString *result;//分析的结果

@property (weak) IBOutlet NSButton *aCheckButton;
@property (weak) IBOutlet NSButton *oCheckButton;
@property (weak) IBOutlet NSButton *tbdCheckButton;
@property (weak) IBOutlet NSButton *dylibCheckButton;

@property (weak) IBOutlet NSButton *spacePrefixCheckButton;
@property (weak) IBOutlet NSButton *syncRuleButton;
@property (weak) IBOutlet NSButton *ignoreEmbeddedButton;
@property (weak) IBOutlet NSButton *ignoreBundleButton;

@property (copy) void (^onAnalyzeFinished)(NSAttributedString *result);
@property (copy) NSString *binaryRule;
@property (copy) NSString *assetsRule;
@property (assign) BOOL syncRuleOn;
@property (assign) BOOL ignoreEmbeddedOn;
@property (assign) BOOL ignoreBundleOn;
@property (assign) BOOL groupParseOn;
@property (strong) LinkMapModel *uiModel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.dragView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    self.dragView.delegate = self;

    self.indicator.hidden = YES;
    
    _contentTextView.editable = NO;
    _contentTextView.selectable = YES;
    
    _contentTextView.string = @"使用方式：\n\
    1.在XCode中开启编译选项Write Link Map File \n\
    XCode -> Project -> Build Settings -> 把Write Link Map File选项设为yes，并指定好linkMap的存储位置 \n\
    2.工程编译完成后，在编译目录里找到Link Map文件（txt类型） \n\
    默认的文件地址：~/Library/Developer/Xcode/DerivedData/XXX-xxxxxxxxxxxxx/Build/Intermediates/XXX.build/Debug-iphoneos/XXX.build/ \n\
    3.回到本应用，点击“选择文件”，打开Link Map文件  \n\
    4.点击“开始”，解析Link Map文件 \n\
    5.点击“输出文件”，得到解析后的Link Map文件 \n\
    6. * 输入目标文件的关键字(例如：libIM)，然后点击“开始”。实现搜索功能 \n\
    7. * 勾选“分组解析”，然后点击“开始”。实现对不同库的目标文件进行分组";

    // 设置悬停文案
    [self.spacePrefixCheckButton setToolTip:@"比如` linker synthesized`或者` objc-stubs-file`\n系统库如AVFCapture虽然显示是AVFCapture, 但是捕获到的名字是` /System/Library/PrivateFrameworks/AVFCapture.framework/AVFCapture`, 所以会命中空格规则"];

    [self.syncRuleButton setToolTip:@"资源规则为空时，让 bundle 采用二进制规则进行匹配"];
    [self.ignoreEmbeddedButton setToolTip:@"只统计静态链接到可执行文件的体积，忽略 .framework/.dylib"];
    [self.ignoreBundleButton setToolTip:@"只统计二进制体积，忽略 .bundle 资源体积"];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *br = [ud stringForKey:@"LM_BinaryRule"] ?: @"";
    NSString *ar = [ud stringForKey:@"LM_AssetsRule"] ?: @"";
    NSArray *fh = [ud arrayForKey:@"LM_FileHistory"] ?: @[];
    NSArray *brh = [ud arrayForKey:@"LM_BinaryRuleHistory"] ?: @[];
    NSArray *arh = [ud arrayForKey:@"LM_AssetsRuleHistory"] ?: @[];
    BOOL syncOn = [ud boolForKey:@"LM_SyncRuleOn"];
    BOOL ignEmb = [ud boolForKey:@"LM_IgnoreEmbedded"];
    BOOL ignBundle = [ud boolForKey:@"LM_IgnoreBundle"];
    if (self.binaryRuleField) self.binaryRuleField.stringValue = br;
    if (self.assetsRuleField) self.assetsRuleField.stringValue = ar;
    if (self.syncRuleButton) self.syncRuleButton.state = syncOn ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.ignoreEmbeddedButton) self.ignoreEmbeddedButton.state = ignEmb ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.ignoreBundleButton) self.ignoreBundleButton.state = ignBundle ? NSControlStateValueOn : NSControlStateValueOff;

    LinkMapModel *model = [LinkMapModel new];
    model.binaryRule = br;
    model.assetsRule = ar;
    model.syncRuleOn = syncOn;
    model.ignoreEmbeddedOn = ignEmb;
    model.ignoreBundleOn = ignBundle;
    model.groupParseOn = YES;
    model.filePathHistory = fh;
    model.binaryRuleHistory = brh;
    model.assetsRuleHistory = arh;

    self.uiModel = model;
    __weak typeof(self) weakSelf2 = self;
    NSView *hosting = [LinkMapHosting hostingViewWithModel:model
                                             onChooseFile:^(){ [weakSelf2 chooseFile:nil]; }
                                                onAnalyze:^(){
                                                    weakSelf2.binaryRule = model.binaryRule ?: @"";
                                                    weakSelf2.assetsRule = model.assetsRule ?: @"";
                                                    weakSelf2.syncRuleOn = model.syncRuleOn;
                                                    weakSelf2.ignoreEmbeddedOn = model.ignoreEmbeddedOn;
                                                    weakSelf2.ignoreBundleOn = model.ignoreBundleOn;
                                                    weakSelf2.groupParseOn = model.groupParseOn;
                                                    [weakSelf2 analyze:nil];
                                                }
                                                onOutput:^(){ [weakSelf2 ouputFile:nil]; }
                                           onFileDropped:^(NSString *path){ [weakSelf2 didDragFileUrl:path]; }];
    // 清空旧的 XIB 子视图，避免布局重叠
    for (NSView *sub in [self.view.subviews copy]) {
        [sub removeFromSuperview];
    }
    hosting.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hosting];
    [NSLayoutConstraint activateConstraints:@[
        [hosting.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hosting.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [hosting.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [hosting.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.onAnalyzeFinished = ^(NSAttributedString *result){
        weakSelf2.uiModel.result = result;
    };
}

- (void)didDragFileUrl:(NSString *)url {
    NSURL *URL = [NSURL fileURLWithPath:url];
    _filePathField.stringValue = URL.path;
    self.linkMapFileURL = URL;
    if (self.uiModel) self.uiModel.filePath = URL.path;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *old = [ud arrayForKey:@"LM_FileHistory"] ?: @[];
    NSMutableArray *mut = [NSMutableArray arrayWithArray:old];
    [mut removeObject:URL.path];
    [mut insertObject:URL.path atIndex:0];
    if (mut.count > 10) [mut removeObjectsInRange:NSMakeRange(10, mut.count-10)];
    [ud setObject:mut forKey:@"LM_FileHistory"];
    if (self.uiModel) self.uiModel.filePathHistory = mut;
}

- (IBAction)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            if (weakSelf == nil) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf->_filePathField.stringValue = document.path;
            strongSelf.linkMapFileURL = document;
            if (strongSelf.uiModel) strongSelf.uiModel.filePath = document.path;
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            NSArray *old = [ud arrayForKey:@"LM_FileHistory"] ?: @[];
            NSMutableArray *mut = [NSMutableArray arrayWithArray:old];
            [mut removeObject:document.path];
            [mut insertObject:document.path atIndex:0];
            if (mut.count > 10) [mut removeObjectsInRange:NSMakeRange(10, mut.count-10)];
            [ud setObject:mut forKey:@"LM_FileHistory"];
            if (strongSelf.uiModel) strongSelf.uiModel.filePathHistory = mut;
        }
    }];
}

- (IBAction)analyze:(id)sender {
    if (!_linkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_linkMapFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确的Link Map文件路径"];
        return;
    }
    self.searchText = self.binaryRuleField ? self.binaryRuleField.stringValue : @"";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (weakSelf == nil) return;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *content = [NSString stringWithContentsOfURL:strongSelf->_linkMapFileURL encoding:NSMacOSRomanStringEncoding error:nil];
        strongSelf.linkMapContent = content;
        
        if (![strongSelf checkContent:content]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf == nil) return;
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf showAlertWithText:@"Link Map文件格式有误"];
            });
            return ;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf == nil) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.indicator.hidden = NO;
            [strongSelf.indicator startAnimation:self];
            
        });
        
        NSDictionary *symbolMap = [strongSelf symbolMapFromContent:content];
        
        NSArray <SymbolModel *>*symbols = [symbolMap allValues];
        
        NSArray *sortedSymbols = [strongSelf sortSymbols:symbols];
        
        BOOL groupOn = self.groupParseOn;
        if (!groupOn && self->_groupButton) {
            __block NSControlStateValue groupButtonState = 0;
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (weakSelf == nil) return;
                __strong typeof(weakSelf) strongSelf = weakSelf;
                groupButtonState = strongSelf->_groupButton.state;
            });
            groupOn = (groupButtonState == NSControlStateValueOn);
        }
        
        if (groupOn) {
            [strongSelf buildCombinationResultWithSymbols:sortedSymbols];
        } else {
            [strongSelf buildResultWithSymbols:sortedSymbols];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf == nil) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            // SwiftUI 承载结果；旧文本视图不再更新
            strongSelf.indicator.hidden = YES;
            [strongSelf.indicator stopAnimation:self];
            if (strongSelf.onAnalyzeFinished) strongSelf.onAnalyzeFinished(strongSelf.result);
            
        });
    });
}

- (NSMutableDictionary *)symbolMapFromContent:(NSString *)content {
    NSMutableDictionary <NSString *,SymbolModel *>*symbolMap = [NSMutableDictionary new];
    // 符号文件列表
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    
    BOOL reachFiles = NO;
    BOOL reachSymbols = NO;
    BOOL reachSections = NO;
    
    for(NSString *line in lines) {
        if([line hasPrefix:@"#"]) {
            if([line hasPrefix:@"# Object files:"])
                reachFiles = YES;
            else if ([line hasPrefix:@"# Sections:"])
                reachSections = YES;
            else if ([line hasPrefix:@"# Symbols:"])
                reachSymbols = YES;
            else if ([line hasPrefix:@"# Dead Stripped Symbols:"]) {
                break;
            }
        } else {
            if(reachFiles == YES && reachSections == NO && reachSymbols == NO) {
                NSRange range = [line rangeOfString:@"]"];
                if(range.location != NSNotFound) {
                    SymbolModel *symbol = [SymbolModel new];
                    symbol.file = [line substringFromIndex:range.location+1];
                    NSString *key = [line substringToIndex:range.location+1];
                    symbolMap[key] = symbol;
                }
            } else if (reachFiles == YES && reachSections == YES && reachSymbols == YES) {
                NSArray <NSString *>*symbolsArray = [line componentsSeparatedByString:@"\t"];
                if(symbolsArray.count == 3) {
                    NSString *fileKeyAndName = symbolsArray[2];
                    NSString *sizeStr = symbolsArray[1];
                    NSUInteger size = 0;
                    if ([sizeStr hasPrefix:@"0x"] || [sizeStr hasPrefix:@"0X"]) {
                        size = (NSUInteger)strtoull([sizeStr UTF8String], nil, 16);
                    } else {
                        size = (NSUInteger)strtoull([sizeStr UTF8String], nil, 10);
                    }
                    
                    NSRange range = [fileKeyAndName rangeOfString:@"]"];
                    if(range.location != NSNotFound) {
                        NSString *key = [fileKeyAndName substringToIndex:range.location+1];
                        SymbolModel *symbol = symbolMap[key];
                        if(symbol) {
                            symbol.size += size;
                        }
                    }
                }
            }
        }
    }
    return symbolMap;
}

- (NSArray *)sortSymbols:(NSArray *)symbols {
    NSArray *sortedSymbols = [symbols sortedArrayUsingComparator:^NSComparisonResult(SymbolModel *  _Nonnull obj1, SymbolModel *  _Nonnull obj2) {
        if(obj1.size > obj2.size) {
            return NSOrderedAscending;
        } else if (obj1.size < obj2.size) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    
    return sortedSymbols;
}

- (void)buildResultWithSymbols:(NSArray *)symbols {
    self.result = [[NSMutableAttributedString alloc] initWithString:@"库大小\t\t库名称\r\n\r\n"];

    NSArray *augmented = symbols;
    NSString *binaryPath = [self appBinaryPathFromContent:self.linkMapContent];
    NSArray *extra = [self extraSymbolsFromAppBinaryPath:binaryPath];
    NSMutableArray *extraFrameworks = [NSMutableArray array];
    NSMutableArray *extraBundles = [NSMutableArray array];
    for (SymbolModel *m in extra) {
        if ([m.file hasSuffix:@".bundle"]) {
            [extraBundles addObject:m];
        } else {
            [extraFrameworks addObject:m];
        }
    }

    NSString *binaryRule = self.binaryRuleField ? self.binaryRuleField.stringValue : (self.binaryRule ?: @"" );
    NSString *assetsRule = nil;
    if (self.assetsRuleField && self.assetsRuleField.stringValue.length > 0) {
        assetsRule = self.assetsRuleField.stringValue;
    } else if ((self.syncRuleButton && self.syncRuleButton.state == NSControlStateValueOn) || self.syncRuleOn) {
        assetsRule = binaryRule;
    } else {
        assetsRule = @"";
    }

    BOOL ignoreEmbedded = self.ignoreEmbeddedButton ? (self.ignoreEmbeddedButton.state == NSControlStateValueOn) : self.ignoreEmbeddedOn;
    NSArray *binarySymbols = augmented;
    if (ignoreEmbedded) {
        binarySymbols = symbols;
    }
    if (!ignoreEmbedded && extraFrameworks.count > 0) {
        binarySymbols = [binarySymbols arrayByAddingObjectsFromArray:extraFrameworks];
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:binaryRule ?: @"" forKey:@"LM_BinaryRule"];
    [ud setObject:assetsRule ?: @"" forKey:@"LM_AssetsRule"];
    [ud setBool:((self.syncRuleButton ? (self.syncRuleButton.state == NSControlStateValueOn) : self.syncRuleOn)) forKey:@"LM_SyncRuleOn"];
    [ud setBool:((self.ignoreEmbeddedButton ? (self.ignoreEmbeddedButton.state == NSControlStateValueOn) : self.ignoreEmbeddedOn)) forKey:@"LM_IgnoreEmbedded"];
    [ud setBool:((self.ignoreBundleButton ? (self.ignoreBundleButton.state == NSControlStateValueOn) : self.ignoreBundleOn)) forKey:@"LM_IgnoreBundle"];
    NSArray *oldBR = [ud arrayForKey:@"LM_BinaryRuleHistory"] ?: @[];
    NSMutableArray *mutBR = [NSMutableArray arrayWithArray:oldBR];
    if (binaryRule.length > 0) {
        [mutBR removeObject:binaryRule];
        [mutBR insertObject:binaryRule atIndex:0];
        if (mutBR.count > 10) [mutBR removeObjectsInRange:NSMakeRange(10, mutBR.count-10)];
        [ud setObject:mutBR forKey:@"LM_BinaryRuleHistory"];
        if (self.uiModel) self.uiModel.binaryRuleHistory = mutBR;
    }
    NSArray *oldAR = [ud arrayForKey:@"LM_AssetsRuleHistory"] ?: @[];
    NSMutableArray *mutAR = [NSMutableArray arrayWithArray:oldAR];
    if (assetsRule.length > 0) {
        [mutAR removeObject:assetsRule];
        [mutAR insertObject:assetsRule atIndex:0];
        if (mutAR.count > 10) [mutAR removeObjectsInRange:NSMakeRange(10, mutAR.count-10)];
        [ud setObject:mutAR forKey:@"LM_AssetsRuleHistory"];
        if (self.uiModel) self.uiModel.assetsRuleHistory = mutAR;
    }
    
    NSUInteger binaryTotal = [self analyze:binarySymbols withSearchKey:binaryRule];
    BOOL ignoreBundle = self.ignoreBundleButton ? (self.ignoreBundleButton.state == NSControlStateValueOn) : self.ignoreBundleOn;
    NSUInteger bundleTotal = ignoreBundle ? 0 : [self analyzeAssets:extraBundles withSearchKey:assetsRule];
    NSUInteger totalSize = binaryTotal + bundleTotal;

    NSString *text = [[NSString alloc] initWithFormat:@"\r\n总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n(不包括忽略部分)\r\n",(totalSize/1024.0/1024.0), (totalSize/1024.0), totalSize/1000.0/1000.0, totalSize/1000.0];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text]];

    NSString *binText = [[NSString alloc] initWithFormat:@"二进制总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n",(binaryTotal/1024.0/1024.0), (binaryTotal/1024.0), binaryTotal/1000.0/1000.0, binaryTotal/1000.0];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:binText]];

    NSString *assetText = [[NSString alloc] initWithFormat:@"资源文件: %.2fMiB(%.2fKiB)\r\n",(bundleTotal/1024.0/1024.0), (bundleTotal/1024.0)];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:assetText]];
}


- (void)buildCombinationResultWithSymbols:(NSArray *)symbols {
    self.result = [[NSMutableAttributedString alloc] initWithString:@"库大小\t\t库名称\r\n\r\n"];
    
    NSMutableDictionary *combinationMap = [[NSMutableDictionary alloc] init];
    
    for(SymbolModel *symbol in symbols) {
        NSString *name = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
        if ([name hasSuffix:@")"] &&
            [name containsString:@"("]) {
            NSRange range = [name rangeOfString:@"("];
            NSString *component = [name substringToIndex:range.location];
            if ([component hasSuffix:@"]"] &&
                [component containsString:@"["]) {
                range = [component rangeOfString:@"["];
                component = [component substringToIndex:range.location];
            }
            SymbolModel *combinationSymbol = [combinationMap objectForKey:component];
            if (!combinationSymbol) {
                combinationSymbol = [[SymbolModel alloc] init];
                [combinationMap setObject:combinationSymbol forKey:component];
            }
            
            combinationSymbol.size += symbol.size;
            combinationSymbol.file = component;
        } else {
            // symbol可能来自app本身的目标文件或者系统的动态库，在最后的结果中一起显示
            [combinationMap setObject:symbol forKey:symbol.file];
        }
    }
    
    NSArray <SymbolModel *>*combinationSymbols = [combinationMap allValues];
    
    NSArray *sortedSymbols = [self sortSymbols:combinationSymbols];

    NSString *binaryPath = [self appBinaryPathFromContent:self.linkMapContent];
    NSArray *extra = [self extraSymbolsFromAppBinaryPath:binaryPath];
    NSMutableArray *extraFrameworks = [NSMutableArray array];
    NSMutableArray *extraBundles = [NSMutableArray array];
    for (SymbolModel *m in extra) {
        if ([m.file hasSuffix:@".bundle"]) {
            [extraBundles addObject:m];
        } else {
            [extraFrameworks addObject:m];
        }
    }

    NSString *binaryRule = self.binaryRuleField ? self.binaryRuleField.stringValue : (self.binaryRule ?: @"" );
    NSString *assetsRule = nil;
    if (self.assetsRuleField && self.assetsRuleField.stringValue.length > 0) {
        assetsRule = self.assetsRuleField.stringValue;
    } else if ((self.syncRuleButton && self.syncRuleButton.state == NSControlStateValueOn) || self.syncRuleOn) {
        assetsRule = binaryRule;
    } else {
        assetsRule = @"";
    }

    BOOL ignoreEmbedded = self.ignoreEmbeddedButton ? (self.ignoreEmbeddedButton.state == NSControlStateValueOn) : self.ignoreEmbeddedOn;
    NSArray *binarySymbols = sortedSymbols;
    if (!ignoreEmbedded && extraFrameworks.count > 0) {
        binarySymbols = [self sortSymbols:[sortedSymbols arrayByAddingObjectsFromArray:extraFrameworks]];
    }

    NSUserDefaults *ud2 = [NSUserDefaults standardUserDefaults];
    [ud2 setObject:binaryRule ?: @"" forKey:@"LM_BinaryRule"];
    [ud2 setObject:assetsRule ?: @"" forKey:@"LM_AssetsRule"];
    [ud2 setBool:((self.syncRuleButton ? (self.syncRuleButton.state == NSControlStateValueOn) : self.syncRuleOn)) forKey:@"LM_SyncRuleOn"];
    [ud2 setBool:((self.ignoreEmbeddedButton ? (self.ignoreEmbeddedButton.state == NSControlStateValueOn) : self.ignoreEmbeddedOn)) forKey:@"LM_IgnoreEmbedded"];
    [ud2 setBool:((self.ignoreBundleButton ? (self.ignoreBundleButton.state == NSControlStateValueOn) : self.ignoreBundleOn)) forKey:@"LM_IgnoreBundle"];
    NSArray *oldBR2 = [ud2 arrayForKey:@"LM_BinaryRuleHistory"] ?: @[];
    NSMutableArray *mutBR2 = [NSMutableArray arrayWithArray:oldBR2];
    if (binaryRule.length > 0) {
        [mutBR2 removeObject:binaryRule];
        [mutBR2 insertObject:binaryRule atIndex:0];
        if (mutBR2.count > 10) [mutBR2 removeObjectsInRange:NSMakeRange(10, mutBR2.count-10)];
        [ud2 setObject:mutBR2 forKey:@"LM_BinaryRuleHistory"];
        if (self.uiModel) self.uiModel.binaryRuleHistory = mutBR2;
    }
    NSArray *oldAR2 = [ud2 arrayForKey:@"LM_AssetsRuleHistory"] ?: @[];
    NSMutableArray *mutAR2 = [NSMutableArray arrayWithArray:oldAR2];
    if (assetsRule.length > 0) {
        [mutAR2 removeObject:assetsRule];
        [mutAR2 insertObject:assetsRule atIndex:0];
        if (mutAR2.count > 10) [mutAR2 removeObjectsInRange:NSMakeRange(10, mutAR2.count-10)];
        [ud2 setObject:mutAR2 forKey:@"LM_AssetsRuleHistory"];
        if (self.uiModel) self.uiModel.assetsRuleHistory = mutAR2;
    }
    
    NSUInteger binaryTotal = [self analyze:binarySymbols withSearchKey:binaryRule];
    BOOL ignoreBundle = (self.ignoreBundleButton ? (self.ignoreBundleButton.state == NSControlStateValueOn) : self.ignoreBundleOn);
    NSUInteger bundleTotal = ignoreBundle ? 0 : [self analyzeAssets:extraBundles withSearchKey:assetsRule];
    NSUInteger totalSize = binaryTotal + bundleTotal;

    NSString *text = [[NSString alloc] initWithFormat:@"\r\n总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n(不包括忽略部分)\r\n",(totalSize/1024.0/1024.0), (totalSize/1024.0), totalSize/1000.0/1000.0, totalSize/1000.0];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text]];

    NSString *binText = [[NSString alloc] initWithFormat:@"二进制总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n",(binaryTotal/1024.0/1024.0), (binaryTotal/1024.0), binaryTotal/1000.0/1000.0, binaryTotal/1000.0];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:binText]];

    NSString *assetText = [[NSString alloc] initWithFormat:@"资源文件: %.2fMiB(%.2fKiB)\r\n",(bundleTotal/1024.0/1024.0), (bundleTotal/1024.0)];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:assetText]];
}

- (NSString *)appBinaryPathFromContent:(NSString *)content {
    if (content.length == 0) return nil;
    NSRange pathTagRange = [content rangeOfString:@"# Path:"];
    if (pathTagRange.location == NSNotFound) return nil;
    NSString *sub = [content substringFromIndex:pathTagRange.location + pathTagRange.length];
    NSRange newline = [sub rangeOfString:@"\n"];
    NSString *path = newline.location == NSNotFound ? sub : [sub substringToIndex:newline.location];
    return [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSArray<SymbolModel *> *)extraSymbolsFromAppBinaryPath:(NSString *)binaryPath {
    if (binaryPath.length == 0) return @[];
    NSString *appDir = [binaryPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<SymbolModel *> *arr = [NSMutableArray array];

    NSString *frameworksDir = [appDir stringByAppendingPathComponent:@"Frameworks"];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:frameworksDir isDirectory:&isDir] && isDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:frameworksDir error:nil];
        for (NSString *item in items) {
            NSString *full = [frameworksDir stringByAppendingPathComponent:item];
            if ([item hasSuffix:@".framework"]) {
                NSString *binName = [item stringByDeletingPathExtension];
                NSString *binPath = [full stringByAppendingPathComponent:binName];
                unsigned long long size = [self fileSizeAtPath:binPath];
                if (size > 0) {
                    SymbolModel *m = [SymbolModel new];
                    m.file = binPath;
                    m.size = (NSUInteger)size;
                    [arr addObject:m];
                }
            } else if ([item hasSuffix:@".dylib"]) {
                unsigned long long size = [self fileSizeAtPath:full];
                if (size > 0) {
                    SymbolModel *m = [SymbolModel new];
                    m.file = full;
                    m.size = (NSUInteger)size;
                    [arr addObject:m];
                }
            }
        }
    }

    NSArray *appItems = [fm contentsOfDirectoryAtPath:appDir error:nil];
    for (NSString *item in appItems) {
        if ([item hasSuffix:@".bundle"]) {
            NSString *bundlePath = [appDir stringByAppendingPathComponent:item];
            unsigned long long size = [self directorySizeAtPath:bundlePath];
            if (size > 0) {
                SymbolModel *m = [SymbolModel new];
                m.file = bundlePath;
                m.size = (NSUInteger)size;
                [arr addObject:m];
            }
        }
    }

    return arr;
}

- (unsigned long long)fileSizeAtPath:(NSString *)path {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *n = attrs[NSFileSize];
    return n ? [n unsignedLongLongValue] : 0;
}

- (unsigned long long)directorySizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    unsigned long long total = 0;
    for (NSString *sub in enumerator) {
        NSString *full = [path stringByAppendingPathComponent:sub];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        NSString *type = attrs[NSFileType];
        if ([type isEqualToString:NSFileTypeRegular]) {
            NSNumber *n = attrs[NSFileSize];
            if (n) total += [n unsignedLongLongValue];
        }
    }
    return total;
}

- (NSUInteger)analyze:(NSArray<SymbolModel *> *)symbols withSearchKey:(NSString *)searchKey {
    NSUInteger totalSize = 0;
    __block BOOL ignoreA;
    __block BOOL ignoreO;
    __block BOOL ignoreTbd;
    __block BOOL ignoreDylib;
    __block BOOL ignorelinkerSyn;
    dispatch_sync(dispatch_get_main_queue(), ^{
        ignoreA = self.aCheckButton.state == NSControlStateValueOn;
        ignoreO = self.oCheckButton.state == NSControlStateValueOn;
        ignoreTbd = self.tbdCheckButton.state == NSControlStateValueOn;
        ignoreDylib = self.dylibCheckButton.state == NSControlStateValueOn;
        ignorelinkerSyn = self.spacePrefixCheckButton.state == NSControlStateValueOn;
    });

    for(SymbolModel *symbol in symbols) {
        if (searchKey.length > 0) {
            NSString *name = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
            if ([self name:name matchesPattern:searchKey]) {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        } else {
            if ((ignoreA && [symbol.file hasSuffix:@".a"]) 
                || (ignoreO && [symbol.file hasSuffix:@".o"]) 
                || (ignoreTbd && [symbol.file hasSuffix:@".tbd"]) 
                || (ignoreDylib && [symbol.file hasSuffix:@".dylib"]) 
                || (ignorelinkerSyn && [symbol.file hasPrefix:@" "]) ) {
                // 系统库如AVFCapture虽然显示是AVFCapture, 但是捕获到的名字是" /System/Library/PrivateFrameworks/AVFCapture.framework/AVFCapture", 所以会命中空格规则
                [self appendResultWithSymbol:symbol ignore:YES];
            } else {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        }
    }
    return totalSize;
}

- (NSUInteger)analyzeAssets:(NSArray<SymbolModel *> *)symbols withSearchKey:(NSString *)searchKey {
    NSUInteger totalSize = 0;
    for (SymbolModel *symbol in symbols) {
        NSString *name = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
        if (searchKey.length > 0) {
            if ([self name:name matchesPattern:searchKey]) {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        } else {
            [self appendResultWithSymbol:symbol ignore:NO];
            totalSize += symbol.size;
        }
    }
    return totalSize;
}

- (NSString *)regexFromSearchKey:(NSString *)searchKey {
    NSString *key = [searchKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (key.length == 0) return nil;
    NSArray *parts = [key componentsSeparatedByString:@"+"];
    NSMutableArray *valid = [NSMutableArray array];
    for (NSString *p in parts) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) [valid addObject:t];
    }
    if (valid.count == 0) return nil;
    return [NSString stringWithFormat:@"(?:%@)", [valid componentsJoinedByString:@"|"]];
}

- (BOOL)name:(NSString *)name matchesPattern:(NSString *)searchKey {
    NSString *pattern = [self regexFromSearchKey:searchKey];
    if (pattern.length == 0) {
        return [name rangeOfString:searchKey options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    NSError *error = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error || !re) {
        return [name rangeOfString:searchKey options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    NSRange r = NSMakeRange(0, name.length);
    return [re firstMatchInString:name options:0 range:r] != nil;
}

- (IBAction)ouputFile:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setPrompt:@"OK"];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:NO];
    
    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            if (weakSelf == nil)
                return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSURL *dirPath = [[panel URLs] objectAtIndex:0];
            NSString *filePath = [NSString stringWithFormat:@"%@/linkMap.rtf", dirPath.path];
            NSData *data = [strongSelf.result dataFromRange:NSMakeRange(0, strongSelf.result.length)
                                         documentAttributes:@{
                                             NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType,
                                             NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
                                         }
                                                      error:nil];
            [data writeToFile:filePath atomically:YES];
        }
    }];
}

- (void)appendResultWithSymbol:(SymbolModel *)model ignore:(BOOL)ignore {
    NSString *size = nil;
    if (model.size / 1024.0 / 1024.0 > 1) {
        size = [NSString stringWithFormat:@"%.2fMiB", model.size / 1024.0 / 1024.0];
    } else {
        size = [NSString stringWithFormat:@"%.2fKiB", model.size / 1024.0];
    }
    NSString *text = [[NSString alloc] initWithFormat:@"%@\t\t%@\r\n",size, [[model.file componentsSeparatedByString:@"/"] lastObject]];
    if (ignore) {
        [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName: NSColor.lightGrayColor}]];
    } else {
        [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
    }
}

- (BOOL)checkContent:(NSString *)content {
    NSRange objsFileTagRange = [content rangeOfString:@"# Object files:"];
    if (objsFileTagRange.length == 0) {
        return NO;
    }
    NSString *subObjsFileSymbolStr = [content substringFromIndex:objsFileTagRange.location + objsFileTagRange.length];
    NSRange symbolsRange = [subObjsFileSymbolStr rangeOfString:@"# Symbols:"];
    if ([content rangeOfString:@"# Path:"].length <= 0||objsFileTagRange.location == NSNotFound||symbolsRange.location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (void)showAlertWithText:(NSString *)text {
    NSAlert *alert = [[NSAlert alloc]init];
    alert.messageText = text;
    [alert addButtonWithTitle:@"确定"];
    [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
    }];
}

@end
