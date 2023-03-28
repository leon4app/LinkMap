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
@interface ViewController() <DragViewDelegate>

@property (weak) IBOutlet NSTextField *filePathField;//显示选择的文件路径
@property (weak) IBOutlet NSProgressIndicator *indicator;//指示器
@property (weak) IBOutlet NSTextField *searchField;

@property (weak) IBOutlet NSScrollView *contentView;//分析的内容
@property (unsafe_unretained) IBOutlet NSTextView *contentTextView;
@property (weak) IBOutlet NSButton *groupButton;
@property (weak) IBOutlet DragView *dragView;


@property (strong) NSURL *linkMapFileURL;
@property (strong) NSString *linkMapContent;

@property (copy) NSString *searchText;

@property (strong) NSMutableAttributedString *result;//分析的结果

@property (weak) IBOutlet NSButton *aCheckButton;
@property (weak) IBOutlet NSButton *oCheckButton;
@property (weak) IBOutlet NSButton *tbdCheckButton;
@property (weak) IBOutlet NSButton *linkerSynCheckButton;

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
}

- (void)didDragFileUrl:(NSString *)url {
    NSURL *URL = [NSURL fileURLWithPath:url];
    _filePathField.stringValue = URL.path;
    self.linkMapFileURL = URL;
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
        }
    }];
}

- (IBAction)analyze:(id)sender {
    if (!_linkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_linkMapFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确的Link Map文件路径"];
        return;
    }
    self.searchText = _searchField.stringValue;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (weakSelf == nil) return;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *content = [NSString stringWithContentsOfURL:strongSelf->_linkMapFileURL encoding:NSMacOSRomanStringEncoding error:nil];
        
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
        
        __block NSControlStateValue groupButtonState = 0;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (weakSelf == nil) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            groupButtonState = strongSelf->_groupButton.state;
        });
        
        if (1 == groupButtonState) {
            [strongSelf buildCombinationResultWithSymbols:sortedSymbols];
        } else {
            [strongSelf buildResultWithSymbols:sortedSymbols];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf == nil) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.contentTextView.string = @"";
            [[strongSelf.contentTextView textStorage] appendAttributedString:strongSelf.result];
            strongSelf.indicator.hidden = YES;
            [strongSelf.indicator stopAnimation:self];
            
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
                    NSUInteger size = strtoul([symbolsArray[1] UTF8String], nil, 16);
                    
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
    self.result = [[NSMutableAttributedString alloc] initWithString:@"库大小\t库名称\r\n\r\n"];
    NSUInteger totalSize = 0;
    
    NSString *searchKey = self.searchText;
    __block BOOL ignoreA;
    __block BOOL ignoreO;
    __block BOOL ignoreTbd;
    __block BOOL ignorelinkerSyn;
    dispatch_sync(dispatch_get_main_queue(), ^{
        ignoreA = self.aCheckButton.state == NSControlStateValueOn;
        ignoreO = self.oCheckButton.state == NSControlStateValueOn;
        ignoreTbd = self.tbdCheckButton.state == NSControlStateValueOn;
        ignorelinkerSyn = self.linkerSynCheckButton.state == NSControlStateValueOn;
    });

    for(SymbolModel *symbol in symbols) {
        if (searchKey.length > 0) {
            if ([symbol.file containsString:searchKey]) {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        } else {
            if ((ignoreA && [symbol.file hasSuffix:@".a"])
                || (ignoreO && [symbol.file hasSuffix:@".o"])
                || (ignoreTbd == NSControlStateValueOn && [symbol.file hasSuffix:@".tbd"])
                || (ignorelinkerSyn == NSControlStateValueOn && [symbol.file isEqual:@" linker synthesized"]) ) {
                [self appendResultWithSymbol:symbol ignore:YES];
            } else {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        }
    }

    NSString *text = [[NSString alloc] initWithFormat:@"\r\n总大小: %.2fM(%.2fK)(不包括忽略部分)\r\n",(totalSize/1024.0/1024.0), (totalSize/1024.0)];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
}


- (void)buildCombinationResultWithSymbols:(NSArray *)symbols {
    self.result = [[NSMutableAttributedString alloc] initWithString:@"库大小\t库名称\r\n\r\n"];
    NSUInteger totalSize = 0;
    
    NSMutableDictionary *combinationMap = [[NSMutableDictionary alloc] init];
    
    for(SymbolModel *symbol in symbols) {
        NSString *name = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
        if ([name hasSuffix:@")"] &&
            [name containsString:@"("]) {
            NSRange range = [name rangeOfString:@"("];
            NSString *component = [name substringToIndex:range.location];
            
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
    
    NSString *searchKey = self.searchText;
    __block BOOL ignoreA;
    __block BOOL ignoreO;
    __block BOOL ignoreTbd;
    __block BOOL ignorelinkerSyn;
    dispatch_sync(dispatch_get_main_queue(), ^{
        ignoreA = self.aCheckButton.state == NSControlStateValueOn;
        ignoreO = self.oCheckButton.state == NSControlStateValueOn;
        ignoreTbd = self.tbdCheckButton.state == NSControlStateValueOn;
        ignorelinkerSyn = self.linkerSynCheckButton.state == NSControlStateValueOn;
    });

    for(SymbolModel *symbol in sortedSymbols) {
        if (searchKey.length > 0) {
            if ([symbol.file containsString:searchKey]) {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        } else {
            if ((ignoreA && [symbol.file hasSuffix:@".a"])
                || (ignoreO && [symbol.file hasSuffix:@".o"])
                || (ignoreTbd == NSControlStateValueOn && [symbol.file hasSuffix:@".tbd"])
                || (ignorelinkerSyn == NSControlStateValueOn && [symbol.file isEqual:@" linker synthesized"]) ) {
                [self appendResultWithSymbol:symbol ignore:YES];
            } else {
                [self appendResultWithSymbol:symbol ignore:NO];
                totalSize += symbol.size;
            }
        }
    }

    NSString *text = [[NSString alloc] initWithFormat:@"\r\n总大小: %.2fM(%.2fK)(不包括忽略部分)\r\n",(totalSize/1024.0/1024.0), (totalSize/1024.0)];
    [_result appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
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
        size = [NSString stringWithFormat:@"%.2fM", model.size / 1024.0 / 1024.0];
    } else {
        size = [NSString stringWithFormat:@"%.2fK", model.size / 1024.0];
    }
    NSString *text = [[NSString alloc] initWithFormat:@"%@\t%@\r\n",size, [[model.file componentsSeparatedByString:@"/"] lastObject]];
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
