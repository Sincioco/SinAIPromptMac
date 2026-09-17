#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
// Parse ES modules with JavaScriptCore's installed syntax checker. No JS runtime
// package is required. Dynamic import remains; only static module declarations
// are removed so the public JSC script grammar can validate the function bodies.
int main(int argc,const char *argv[]){@autoreleasepool{
    JSContext *context=JSContext.new;NSUInteger count=0;
    NSRegularExpression *imports=[NSRegularExpression regularExpressionWithPattern:@"(?m)^import\\s+[^;]+;[ \\t]*" options:0 error:nil];
    NSRegularExpression *exports=[NSRegularExpression regularExpressionWithPattern:@"(?m)^export\\s+(?:\\{[^}]*\\}(?:\\s+from\\s+[^;]+)?;|default\\s+)?" options:0 error:nil];
    for(int i=1;i<argc;i++){NSString *path=[NSString stringWithUTF8String:argv[i]];NSError *error=nil;NSString *source=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];if(!source){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
        source=[imports stringByReplacingMatchesInString:source options:0 range:NSMakeRange(0,source.length) withTemplate:@""];
        source=[exports stringByReplacingMatchesInString:source options:0 range:NSMakeRange(0,source.length) withTemplate:@""];
        source=[source stringByReplacingOccurrencesOfString:@"import.meta" withString:@"({url:'sin-asset://app/'})"];
        NSString *wrapped=[NSString stringWithFormat:@"(async function(){\n%@\n})",source];
        JSStringRef script=JSStringCreateWithCFString((__bridge CFStringRef)wrapped);JSValueRef exception=NULL;
        BOOL valid=JSCheckScriptSyntax(context.JSGlobalContextRef,script,NULL,1,&exception);JSStringRelease(script);
        if(!valid){JSValue *value=[JSValue valueWithJSValueRef:exception inContext:context];fprintf(stderr,"%s: %s\n",path.UTF8String,value.toString.UTF8String);return 1;}count++;
    }
    printf("PASS: %lu JavaScript modules parse with Apple JavaScriptCore\n",(unsigned long)count);return 0;
}}
