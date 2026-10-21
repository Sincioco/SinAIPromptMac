#import "SINWorkspaceSplitView.h"
#import <QuartzCore/QuartzCore.h>

@implementation SINWorkspaceSplitView
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)index {
    // AppKit expands a hidden adjacent pane when a divider is positioned. Pane
    // visibility belongs to the View commands, including when Contents sits
    // between navigation and the document.
    NSMutableArray *hidden=NSMutableArray.new;for(NSView *view in self.subviews)if(view.hidden)[hidden addObject:view];
    [super setPosition:position ofDividerAtIndex:index];
    BOOL restored=NO;for(NSView *view in hidden)if(!view.hidden){view.hidden=YES;restored=YES;}
    if(restored)[super adjustSubviews];
}
- (NSView *)hitTest:(NSPoint)point {
    NSPoint local=[self convertPoint:point fromView:self.superview];
    for(NSValue *value in self.excludedRects)if(NSPointInRect(local,value.rectValue))return nil;
    NSView *hit=[super hitTest:point];
    // Preserve divider dragging and native previews; the empty right pane
    // forwards mouse input to the editor underneath it.
    if(hit==self.documentPane)return nil;
    if(hit==self && NSPointInRect(local,self.documentPane.frame))return nil;
    return hit;
}
- (void)setExcludedRects:(NSArray<NSValue *> *)rects {
    _excludedRects=[rects copy];self.wantsLayer=YES;
    if(!rects.count){self.layer.mask=nil;return;}
    NSMutableArray<NSValue *> *holes=NSMutableArray.new;
    for(NSValue *value in rects){
        NSRect rect=NSIntersectionRect(self.bounds,value.rectValue);if(NSIsEmptyRect(rect))continue;
        // Union overlapping holes so even-odd filling cannot expose their overlap.
        for(NSInteger i=holes.count-1;i>=0;i--)if(NSIntersectsRect(rect,holes[i].rectValue)){rect=NSUnionRect(rect,holes[i].rectValue);[holes removeObjectAtIndex:i];i=holes.count;}
        [holes addObject:[NSValue valueWithRect:rect]];
    }
    CGMutablePathRef path=CGPathCreateMutable();CGPathAddRect(path,NULL,self.bounds);
    for(NSValue *value in holes)CGPathAddRect(path,NULL,value.rectValue);
    CAShapeLayer *mask=CAShapeLayer.layer;mask.frame=self.bounds;mask.path=path;mask.fillRule=kCAFillRuleEvenOdd;
    self.layer.mask=mask;CGPathRelease(path);
}
@end
