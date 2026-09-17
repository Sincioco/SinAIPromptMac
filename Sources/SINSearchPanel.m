#import "SINSearchPanel.h"
#import "SINEditor.h"
#import "SINDocument.h"

@interface SINSearchPanel () <NSSearchFieldDelegate,NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate>
@property(nonatomic, weak) SINEditor *editor;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSSearchField *queryField;
@property(nonatomic, strong) NSTextField *replacementField;
@property(nonatomic, strong) NSButton *matchCase;
@property(nonatomic, strong) NSButton *wholeWord;
@property(nonatomic, strong) NSButton *regex;
@property(nonatomic, strong) NSButton *wrap;
@property(nonatomic, strong) NSButton *replaceButton;
@property(nonatomic, strong) NSButton *replaceAllButton;
@property(nonatomic, strong) NSPopUpButton *mode;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSTableView *resultsTable;
@property(nonatomic, strong) NSArray<NSDictionary *> *matches;
@property(nonatomic, strong) NSArray<NSDictionary *> *rows;
@property(nonatomic, copy) NSString *searchedText;
@property(nonatomic, copy) NSString *searchedKey;
@property(nonatomic) NSInteger currentIndex;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL applying;
@property(nonatomic) BOOL suppressTableAction;
@property(nonatomic, strong) NSTimer *debounce;
@end

@implementation SINSearchPanel
- (instancetype)initWithEditor:(SINEditor *)editor {
    if ((self=[super initWithNibName:nil bundle:nil])) { _editor=editor; _matches=@[]; _rows=@[]; _currentIndex=-1; }
    return self;
}
- (NSString *)query { return self.queryField.stringValue ?: @""; }
- (NSButton *)check:(NSString *)title frame:(NSRect)frame {
    NSButton *button=[NSButton checkboxWithTitle:title target:self action:@selector(optionsChanged:)]; button.frame=frame; [self.view addSubview:button]; return button;
}
- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:action]; button.frame=frame; [self.view addSubview:button]; return button;
}
- (void)loadView {
    self.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,420,580)];
    NSTextField *label=[NSTextField labelWithString:@"Search in"]; label.frame=NSMakeRect(16,545,78,22); [self.view addSubview:label];
    self.mode=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(96,542,308,28)]; [self.mode addItemsWithTitles:@[@"HTML Source",@"Visual Text"]]; self.mode.target=self; self.mode.action=@selector(modeChanged:); [self.view addSubview:self.mode];
    self.queryField=[[NSSearchField alloc] initWithFrame:NSMakeRect(16,503,388,28)]; self.queryField.placeholderString=@"Find text or regular expression"; self.queryField.delegate=self; self.queryField.sendsWholeSearchString=YES; self.queryField.target=self; self.queryField.action=@selector(findForward:); [self.view addSubview:self.queryField];
    self.matchCase=[self check:@"Match case" frame:NSMakeRect(16,468,150,24)];
    self.wholeWord=[self check:@"Whole word" frame:NSMakeRect(206,468,180,24)];
    self.regex=[self check:@"Regular expression" frame:NSMakeRect(16,439,180,24)];
    self.wrap=[self check:@"Wrap around" frame:NSMakeRect(206,439,180,24)]; self.wrap.state=NSControlStateValueOn;
    [self button:@"Previous" action:@selector(findBackward:) frame:NSMakeRect(16,401,188,30)];
    [self button:@"Next" action:@selector(findForward:) frame:NSMakeRect(210,401,194,30)];
    self.replacementField=[[NSTextField alloc] initWithFrame:NSMakeRect(16,360,388,28)]; self.replacementField.placeholderString=@"Replace with"; self.replacementField.delegate=self; [self.view addSubview:self.replacementField];
    self.replaceButton=[self button:@"Replace" action:@selector(replaceOne:) frame:NSMakeRect(16,323,188,30)];
    self.replaceAllButton=[self button:@"Replace All" action:@selector(replaceAll:) frame:NSMakeRect(210,323,194,30)];
    self.status=[NSTextField wrappingLabelWithString:@"Enter text to find."]; self.status.frame=NSMakeRect(16,272,388,42); self.status.font=[NSFont systemFontOfSize:12]; self.status.textColor=NSColor.secondaryLabelColor; [self.view addSubview:self.status];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(16,16,388,246)]; scroll.borderType=NSBezelBorder; scroll.hasVerticalScroller=YES;
    self.resultsTable=[[NSTableView alloc] initWithFrame:scroll.bounds]; self.resultsTable.headerView=nil; self.resultsTable.rowHeight=39; self.resultsTable.dataSource=self; self.resultsTable.delegate=self; self.resultsTable.target=self; self.resultsTable.action=@selector(resultClicked:); self.resultsTable.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"result"]; column.width=380; [self.resultsTable addTableColumn:column]; scroll.documentView=self.resultsTable; [self.view addSubview:scroll];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceChanged:) name:NSTextDidChangeNotification object:self.editor.sourceView];
}
- (void)showForWindow:(NSWindow *)window replace:(BOOL)replace {
    if (!self.panel) {
        (void)self.view;
        self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,420,580) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:NO];
        self.panel.title=@"Find and Replace"; self.panel.contentViewController=self; self.panel.floatingPanel=YES; self.panel.hidesOnDeactivate=NO; self.panel.releasedWhenClosed=NO; self.panel.delegate=self;
    }
    self.replacementField.hidden=!replace; self.replaceButton.hidden=!replace; self.replaceAllButton.hidden=!replace;
    self.replaceButton.enabled=!self.editor.document.readOnly; self.replaceAllButton.enabled=!self.editor.document.readOnly;
    if (self.panel.parentWindow != window) { [self.panel.parentWindow removeChildWindow:self.panel]; [window addChildWindow:self.panel ordered:NSWindowAbove]; }
    if (!self.panel.visible) [self.panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(window.frame)-438,NSMaxY(window.frame)-48)];
    [self.editor showSource:self.mode.indexOfSelectedItem==0 completion:^{
        [self.panel makeKeyAndOrderFront:nil]; [self.panel makeFirstResponder:self.queryField]; [self.queryField selectText:nil];
        [self runAction:@"search" target:0];
    }];
}
- (void)modeChanged:(id)sender {
    self.searchedKey=nil; self.currentIndex=-1;
    [self.editor evaluate:@"window.editor.search({action:'clear'})" completion:nil];
    [self.editor showSource:self.mode.indexOfSelectedItem==0 completion:^{ [self.panel makeFirstResponder:self.queryField]; [self runAction:@"search" target:0]; }];
}
- (void)optionsChanged:(id)sender { self.searchedKey=nil; self.currentIndex=-1; [self runAction:@"search" target:0]; }
- (void)controlTextDidChange:(NSNotification *)notification {
    self.currentIndex=-1; self.searchedKey=nil; [self.debounce invalidate];
    __weak typeof(self) weakSelf=self;
    self.debounce=[NSTimer scheduledTimerWithTimeInterval:.18 repeats:NO block:^(NSTimer *timer) { [weakSelf runAction:@"search" target:0]; }];
}
- (void)sourceChanged:(NSNotification *)notification { if (!self.applying && self.panel.visible && self.mode.indexOfSelectedItem==0) [self controlTextDidChange:notification]; }
- (void)findForward:(id)sender { [self runAction:@"next" target:0]; }
- (void)findBackward:(id)sender { [self runAction:@"previous" target:0]; }
- (void)findNext:(BOOL)backward {
    if (!self.query.length) { [self showForWindow:self.editor.view.window replace:NO]; return; }
    [self runAction:backward ? @"previous" : @"next" target:0];
}
- (void)replaceOne:(id)sender { [self runAction:@"replace" target:0]; }
- (void)replaceAll:(id)sender { [self runAction:@"replaceAll" target:0]; }
- (void)resultClicked:(id)sender { if (!self.suppressTableAction && self.resultsTable.selectedRow>=0) [self runAction:@"select" target:self.resultsTable.selectedRow+1]; }
- (NSDictionary *)optionsForAction:(NSString *)action target:(NSInteger)target {
    return @{@"query":self.query,@"replacement":self.replacementField.stringValue?:@"",@"matchCase":@(self.matchCase.state==NSControlStateValueOn),@"wholeWord":@(self.wholeWord.state==NSControlStateValueOn),@"regex":@(self.regex.state==NSControlStateValueOn),@"wrap":@(self.wrap.state==NSControlStateValueOn),@"action":action,@"target":@(target)};
}
- (void)runAction:(NSString *)action target:(NSInteger)target {
    [self.debounce invalidate]; self.debounce=nil;
    if (!self.editor) return;
    if ([action hasPrefix:@"replace"] && self.editor.document.readOnly) { self.status.stringValue=@"This document is locked. Unlock it before replacing text."; return; }
    NSUInteger generation=++self.generation;
    NSDictionary *options=[self optionsForAction:action target:target];
    if (!self.query.length) { self.matches=@[]; self.rows=@[]; self.currentIndex=-1; self.status.stringValue=@"Enter text to find."; [self.resultsTable reloadData]; [self.editor evaluate:@"window.editor.search({action:'clear'})" completion:nil]; return; }
    self.status.stringValue=@"Searching…";
    if (self.mode.indexOfSelectedItem==1) {
        [self.editor showSource:NO completion:^{
            [self.editor asyncScript:[NSString stringWithFormat:@"return await window.editor.search(%@);",SINJSON(options)] completion:^(id value,NSError *error) {
                if (generation!=self.generation) return;
                if (error || ![value isKindOfClass:NSDictionary.class]) { self.status.stringValue=error.localizedDescription?:@"The search could not complete."; return; }
                self.rows=[value[@"results"] isKindOfClass:NSArray.class] ? value[@"results"] : @[]; self.currentIndex=[value[@"index"] integerValue]-1;
                self.status.stringValue=value[@"message"] ?: [NSString stringWithFormat:@"%ld of %ld matches",(long)MAX(0,self.currentIndex+1),(long)[value[@"count"] integerValue]];
                [self updateResultSelection];
            }];
        }];
        return;
    }
    [self.editor showSource:YES completion:^{
        NSString *text=self.editor.sourceView.string;
        NSString *key=SINJSON(@[self.query,options[@"replacement"],options[@"matchCase"],options[@"wholeWord"],options[@"regex"]]);
        if ([text isEqual:self.searchedText] && [key isEqual:self.searchedKey]) { [self applySourceAction:action target:target]; return; }
        NSMutableDictionary *request=options.mutableCopy; request[@"text"]=text;
        // Reuse the upstream pure matcher inside a disposable worker. A hostile
        // regex can consume only the worker's 750ms budget, never AppKit's thread.
        NSString *script=[NSString stringWithFormat:@"const {searchDocumentText}=await import('sin-asset://app/search-engine.js');return await new Promise(resolve=>{window.sinSourceSearch?.cancel();const url=URL.createObjectURL(new Blob(['const search='+searchDocumentText.toString()+';self.onmessage=e=>self.postMessage(search(e.data));'],{type:'text/javascript'}));let worker,timer,finished=false;const finish=value=>{if(finished)return;finished=true;clearTimeout(timer);worker?.terminate();URL.revokeObjectURL(url);resolve(value);};try{worker=new Worker(url);window.sinSourceSearch={cancel:()=>finish({error:'Search changed.'})};timer=setTimeout(()=>finish({error:'Search took too long. Try a simpler expression.'}),750);worker.onmessage=e=>finish(e.data);worker.onerror=()=>finish({error:'Search could not run.'});worker.postMessage(%@);}catch(error){finish({error:String(error)});}});",SINJSON(request)];
        [self.editor asyncScript:script completion:^(id result,NSError *error) {
            if (generation!=self.generation) return;
            if (error || ![result isKindOfClass:NSDictionary.class] || result[@"error"]) { self.matches=@[]; self.rows=@[]; [self.resultsTable reloadData]; self.status.stringValue=error.localizedDescription?:result[@"error"]?:@"Search could not run."; return; }
            if (![text isEqual:self.editor.sourceView.string]) { [self runAction:action target:target]; return; }
            self.searchedText=text; self.searchedKey=key; self.matches=result[@"matches"]?:@[];
            NSMutableArray *rows=[NSMutableArray arrayWithCapacity:MIN(self.matches.count,10000)];
            for (NSUInteger index=0; index<MIN(self.matches.count,10000); index++) {
                NSDictionary *match=self.matches[index]; NSUInteger start=[match[@"start"] unsignedIntegerValue],length=[match[@"length"] unsignedIntegerValue];
                if (start>text.length || length>text.length-start) continue;
                NSUInteger before=start>45?start-45:0,after=MIN(text.length,start+length+70);
                [rows addObject:@{@"index":@(index+1),@"before":[text substringWithRange:NSMakeRange(before,start-before)],@"match":[text substringWithRange:NSMakeRange(start,MIN(length,100))],@"after":[text substringWithRange:NSMakeRange(start+length,after-start-length)]}];
            }
            self.rows=rows;
            [self applySourceAction:action target:target];
        }];
    }];
}
- (void)applySourceAction:(NSString *)action target:(NSInteger)target {
    NSTextView *source=self.editor.sourceView;
    if ([action isEqual:@"replaceAll"] && self.matches.count) {
        NSMutableString *updated=source.string.mutableCopy;
        for (NSDictionary *match in self.matches.reverseObjectEnumerator) [updated replaceCharactersInRange:NSMakeRange([match[@"start"] unsignedIntegerValue],[match[@"length"] unsignedIntegerValue]) withString:[match[@"text"] isKindOfClass:NSString.class]?match[@"text"]:@""];
        NSUInteger count=self.matches.count;
        self.applying=YES; [source insertText:updated replacementRange:NSMakeRange(0,source.string.length)]; self.applying=NO;
        self.currentIndex=-1; self.searchedKey=nil; self.matches=@[]; self.rows=@[]; [self.resultsTable reloadData];
        self.status.stringValue=[NSString stringWithFormat:@"Replaced %lu occurrences",(unsigned long)count]; return;
    }
    if ([action isEqual:@"replace"] && self.currentIndex>=0 && self.currentIndex<(NSInteger)self.matches.count) {
        NSDictionary *match=self.matches[self.currentIndex]; self.applying=YES;
        [source insertText:[match[@"text"] isKindOfClass:NSString.class]?match[@"text"]:@"" replacementRange:NSMakeRange([match[@"start"] unsignedIntegerValue],[match[@"length"] unsignedIntegerValue])]; self.applying=NO;
        self.currentIndex=-1; self.searchedKey=nil; [self runAction:@"next" target:0]; return;
    }
    if ([@[@"next",@"previous",@"replace",@"select"] containsObject:action] && self.matches.count) {
        BOOL backward=[action isEqual:@"previous"];
        NSInteger index=self.currentIndex+(backward?-1:1);
        if ([action isEqual:@"select"]) index=target-1;
        else if (self.currentIndex<0) {
            index=backward?-1:self.matches.count;
            for (NSUInteger position=0;position<self.matches.count;position++) {
                NSUInteger start=[self.matches[position][@"start"] unsignedIntegerValue];
                if (!backward && start>=NSMaxRange(source.selectedRange)) { index=position; break; }
                if (backward && start<source.selectedRange.location) index=position;
            }
        }
        if (index<0 || index>=(NSInteger)self.matches.count) {
            if (self.wrap.state!=NSControlStateValueOn) { self.status.stringValue=[NSString stringWithFormat:@"%lu matches · Reached the end of the search",(unsigned long)self.matches.count]; [self.resultsTable reloadData]; return; }
            index=backward?self.matches.count-1:0;
        }
        self.currentIndex=index; NSDictionary *match=self.matches[index];
        source.selectedRange=NSMakeRange([match[@"start"] unsignedIntegerValue],[match[@"length"] unsignedIntegerValue]); [source scrollRangeToVisible:source.selectedRange];
    }
    self.status.stringValue=self.matches.count?[NSString stringWithFormat:@"%ld of %lu matches%@",(long)MAX(0,self.currentIndex+1),(unsigned long)self.matches.count,self.matches.count>10000?@" · First 10,000 listed":@""]:@"No matches";
    [self updateResultSelection];
}
- (void)updateResultSelection {
    self.suppressTableAction=YES; [self.resultsTable reloadData];
    if (self.currentIndex>=0 && self.currentIndex<(NSInteger)self.rows.count) { [self.resultsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:self.currentIndex] byExtendingSelection:NO]; [self.resultsTable scrollRowToVisible:self.currentIndex]; }
    else [self.resultsTable deselectAll:nil];
    self.suppressTableAction=NO;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return MIN(self.rows.count,10000); }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *field=[tableView makeViewWithIdentifier:@"result" owner:self];
    if (!field) { field=[NSTextField wrappingLabelWithString:@""]; field.identifier=@"result"; field.maximumNumberOfLines=2; field.font=[NSFont systemFontOfSize:11]; field.lineBreakMode=NSLineBreakByTruncatingTail; }
    NSDictionary *result=self.rows[row];
    NSString *before=[result[@"before"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]?:@"",*match=[result[@"match"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]?:@"",*after=[result[@"after"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]?:@"";
    NSString *prefix=[NSString stringWithFormat:@"%ld. %@",(long)row+1,before];
    NSMutableAttributedString *text=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@%@",prefix,match,after] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11]}];
    [text addAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:11]} range:NSMakeRange(prefix.length,match.length)]; field.attributedStringValue=text; return field;
}
- (void)windowWillClose:(NSNotification *)notification { [self.debounce invalidate]; self.generation++; [self.editor evaluate:@"window.sinSourceSearch?.cancel();window.editor.search({action:'clear'});void 0" completion:nil]; }
- (void)invalidate { [self.debounce invalidate]; self.generation++; [NSNotificationCenter.defaultCenter removeObserver:self]; [self.panel.parentWindow removeChildWindow:self.panel]; [self.panel close]; self.panel.contentViewController=nil; self.panel=nil; self.editor=nil; }
@end
