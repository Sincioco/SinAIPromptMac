#import <Cocoa/Cocoa.h>

// Native navigation sits over the document's unused left margin. The ribbon
// remains in the same full-width WKWebView as the document it edits.
@interface SINWorkspaceSplitView : NSSplitView
@property(nonatomic,weak) NSView *documentPane;
@property(nonatomic,copy) NSArray<NSValue *> *excludedRects;
@end
