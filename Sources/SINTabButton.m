#import "SINTabButton.h"
@implementation SINTabButton
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame]))[self registerForDraggedTypes:@[@"com.sin.aiprompt.document"]];return self;}
- (void)mouseDown:(NSEvent *)event {
    NSPoint start=event.locationInWindow;
    while(YES){NSEvent *next=[self.window nextEventMatchingMask:NSEventMaskLeftMouseUp|NSEventMaskLeftMouseDragged];
        if(next.type==NSEventTypeLeftMouseUp){[self sendAction:self.action to:self.target];return;}
        if(hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y)<4)continue;
        NSPasteboardItem *item=NSPasteboardItem.new;[item setString:self.identifier forType:@"com.sin.aiprompt.document"];
        NSDraggingItem *drag=[[NSDraggingItem alloc] initWithPasteboardWriter:item];NSBitmapImageRep *bitmap=[self bitmapImageRepForCachingDisplayInRect:self.bounds];[self cacheDisplayInRect:self.bounds toBitmapImageRep:bitmap];NSImage *image=[[NSImage alloc] initWithSize:self.bounds.size];[image addRepresentation:bitmap];[drag setDraggingFrame:self.bounds contents:image];[self beginDraggingSessionWithItems:@[drag] event:next source:self];return;
    }
}
- (void)otherMouseDown:(NSEvent *)event {if(event.buttonNumber==2&&self.closeDocument)self.closeDocument(self.identifier);else [super otherMouseDown:event];}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {return NSDragOperationMove;}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {return [sender.draggingPasteboard stringForType:@"com.sin.aiprompt.document"]?NSDragOperationMove:NSDragOperationNone;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {NSString *source=[sender.draggingPasteboard stringForType:@"com.sin.aiprompt.document"];if(!source||!self.moveDocument)return NO;self.moveDocument(source,self.identifier);return YES;}
@end
