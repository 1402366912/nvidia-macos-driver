// SPDX-License-Identifier: MIT
// Independent vector drawing; no ASUS/Windows artwork or binary is embedded.
#import "FXFeedback.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreGraphics/CoreGraphics.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include <cmath>
extern bool FXIsConsoleUser();
extern uint64_t FXSessionGeneration();

namespace {
// Family geometry measured from ASUS FAQ 1042539 Windows 10 VivoBook raster.
// 270px panel, ~7px corner, center at 68.4% of image height. NOT FX505GT proof.
// Mapping reference pixels to AppKit points is provisional until native QA.
constexpr CGFloat side=270, corner=7;
constexpr NSTimeInterval hold=1.5, fade=0.18;
NSString *titleFor(uint32_t code) {
    switch(code-FX_FN_EVENT_BASE) {
        case 1: case 2: case 3:return @"Volume";
        case 4:return @"Microphone"; case 5:return @"Fan mode";
        case 6:return @"Internal display"; case 7:case 8:return @"Brightness";
        case 9:return @"Display mode"; case 10:return @"Touchpad";
        case 11:return @"Sleep"; case 12:return @"Wi-Fi + Bluetooth";
        case 13:case 14:return @"Keyboard lighting"; default:return @"Fn";
    }
}
bool audioProperty(AudioObjectID device,AudioObjectPropertySelector selector,AudioObjectPropertyScope scope,void *value,UInt32 size) {
    AudioObjectPropertyAddress property={selector,scope,kAudioObjectPropertyElementMaster};
    UInt32 actual=size;
    return AudioObjectHasProperty(device,&property) && AudioObjectGetPropertyData(device,&property,0,nullptr,&actual,value)==noErr && actual==size;
}
fx::Feedback outputFeedback() {
    fx::Feedback value; AudioDeviceID device=kAudioObjectUnknown,current=kAudioObjectUnknown;
    if(!audioProperty(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,&device,sizeof(device)) || device==kAudioObjectUnknown) return value;
    Float32 volume=-1; UInt32 mute=2;
    bool hasVolume=audioProperty(device,kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyScopeOutput,&volume,sizeof(volume)) && fx::validLevel(volume);
    bool hasMute=audioProperty(device,kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,&mute,sizeof(mute)) && mute<=1;
    if(!audioProperty(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,&current,sizeof(current)) || current!=device) return value;
    if(hasVolume || hasMute) { value.state=fx::FeedbackState::Readback; value.level=hasVolume?volume:-1; value.on=hasMute?static_cast<int>(mute):-1; }
    return value;
}
fx::Feedback brightnessFeedback() {
    fx::Feedback value; io_iterator_t iterator=IO_OBJECT_NULL;
    if(IOServiceGetMatchingServices(kIOMasterPortDefault,IOServiceMatching("AppleBacklightDisplay"),&iterator)!=KERN_SUCCESS) return value;
    io_service_t panel=IOIteratorNext(iterator),extra=IOIteratorNext(iterator);
    bool unique=IOIteratorIsValid(iterator) && panel && !extra; IOObjectRelease(iterator);
    if(extra) IOObjectRelease(extra);
    if(unique) {
        // Match the tested ABI3 action's parameter preference; dsyp is power,
        // never brightness. This only reads and validates the driver's range.
        const CFStringRef choices[]={CFSTR("bklt"),CFSTR(kIODisplayBrightnessKey)};
        for(CFStringRef parameter:choices) {
            SInt32 actual=-1,minimum=-1,maximum=-1;
            if(IODisplayGetIntegerRangeParameter(panel,0,parameter,&actual,&minimum,&maximum)!=kIOReturnSuccess) continue;
            double level=fx::normalizedLevel(actual,minimum,maximum);
            if(fx::validLevel(level)) { value.state=fx::FeedbackState::Readback; value.level=level; break; }
        }
        // Discard a sample if the unique internal panel changed during readback.
        io_iterator_t current=IO_OBJECT_NULL;
        if(IOServiceGetMatchingServices(kIOMasterPortDefault,IOServiceMatching("AppleBacklightDisplay"),&current)!=KERN_SUCCESS) value=fx::Feedback{};
        else {
            io_service_t first=IOIteratorNext(current),second=IOIteratorNext(current);
            if(!IOIteratorIsValid(current) || !first || second || !IOObjectIsEqualTo(first,panel)) value=fx::Feedback{};
            if(first) IOObjectRelease(first); if(second) IOObjectRelease(second); IOObjectRelease(current);
        }
    }
    if(panel) IOObjectRelease(panel);
    return value;
}
void line(NSPoint a,NSPoint b) { NSBezierPath *p=[NSBezierPath bezierPath]; p.lineWidth=3; p.lineCapStyle=NSRoundLineCapStyle; [p moveToPoint:a]; [p lineToPoint:b]; [p stroke]; }
void rectangle(NSRect rect,CGFloat radius) { NSBezierPath *p=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius]; p.lineWidth=3; [p stroke]; }
void oval(NSRect rect) { NSBezierPath *p=[NSBezierPath bezierPathWithOvalInRect:rect]; p.lineWidth=3; [p stroke]; }
void icon(uint32_t key,fx::Feedback feedback) {
    // Original simple line artwork in a 64x64 logical coordinate system.
    switch(key) {
        case 1:case 2:case 3: {
            NSBezierPath *p=[NSBezierPath bezierPath]; p.lineWidth=3;
            [p moveToPoint:NSMakePoint(9,25)]; [p lineToPoint:NSMakePoint(20,25)]; [p lineToPoint:NSMakePoint(33,14)];
            [p lineToPoint:NSMakePoint(33,50)]; [p lineToPoint:NSMakePoint(20,39)]; [p lineToPoint:NSMakePoint(9,39)]; [p closePath]; [p stroke];
            if(feedback.on==1) { line(NSMakePoint(43,24),NSMakePoint(57,40)); line(NSMakePoint(43,40),NSMakePoint(57,24)); }
            else if(fx::knownSwitch(feedback) && feedback.on==0) { NSBezierPath *waves=[NSBezierPath bezierPath]; waves.lineWidth=3; [waves appendBezierPathWithArcWithCenter:NSMakePoint(31,32) radius:15 startAngle:-55 endAngle:55]; [waves stroke]; if(feedback.level<0 || feedback.level>0.5) { NSBezierPath *outer=[NSBezierPath bezierPath]; outer.lineWidth=3; [outer appendBezierPathWithArcWithCenter:NSMakePoint(31,32) radius:25 startAngle:-50 endAngle:50]; [outer stroke]; } }
            break;
        }
        case 4:
            rectangle(NSMakeRect(24,25,16,29),8); line(NSMakePoint(32,10),NSMakePoint(32,20)); line(NSMakePoint(23,10),NSMakePoint(41,10));
            { NSBezierPath *p=[NSBezierPath bezierPath]; p.lineWidth=3; [p appendBezierPathWithArcWithCenter:NSMakePoint(32,32) radius:15 startAngle:180 endAngle:360]; [p stroke]; }
            if(feedback.on==1) line(NSMakePoint(13,13),NSMakePoint(51,53)); break;
        case 5:
            oval(NSMakeRect(27,27,10,10));
            for(int i=0;i<3;++i) { NSAffineTransform *t=[NSAffineTransform transform]; [t translateXBy:32 yBy:32]; [t rotateByDegrees:i*120]; [t translateXBy:-32 yBy:-32]; [NSGraphicsContext saveGraphicsState]; [t concat]; NSBezierPath *p=[NSBezierPath bezierPath]; [p moveToPoint:NSMakePoint(32,38)]; [p curveToPoint:NSMakePoint(47,47) controlPoint1:NSMakePoint(54,61) controlPoint2:NSMakePoint(61,42)]; [p curveToPoint:NSMakePoint(32,38) controlPoint1:NSMakePoint(40,39) controlPoint2:NSMakePoint(37,40)]; [p fill]; [NSGraphicsContext restoreGraphicsState]; } break;
        case 6:case 9:
            rectangle(NSMakeRect(6,22,47,31),2); line(NSMakePoint(29,22),NSMakePoint(29,13)); line(NSMakePoint(19,13),NSMakePoint(39,13));
            if(key==9) rectangle(NSMakeRect(36,6,22,24),1);
            if(key==6 && feedback.on==0) line(NSMakePoint(8,12),NSMakePoint(55,58)); break;
        case 7:case 8:
            oval(NSMakeRect(20,20,24,24)); for(int i=0;i<8;++i) { double a=i*3.141592653589793/4; line(NSMakePoint(32+20*cos(a),32+20*sin(a)),NSMakePoint(32+27*cos(a),32+27*sin(a))); } break;
        case 10: {
            // The official FAQ has a bold vertical pad with two bottom buttons.
            // Original paths, approximately 105x117 points after scaling.
            NSBezierPath *pad=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(12,9,40.8,45.8) xRadius:2 yRadius:2];
            pad.lineWidth=4.2; pad.lineJoinStyle=NSRoundLineJoinStyle;
            [pad moveToPoint:NSMakePoint(12,21)]; [pad lineToPoint:NSMakePoint(52.8,21)];
            [pad moveToPoint:NSMakePoint(32.4,9)]; [pad lineToPoint:NSMakePoint(32.4,21)]; [pad stroke]; break;
        }
        case 11: {
            NSBezierPath *p=[NSBezierPath bezierPath]; [p moveToPoint:NSMakePoint(43,54)]; [p curveToPoint:NSMakePoint(43,10) controlPoint1:NSMakePoint(0,62) controlPoint2:NSMakePoint(0,2)]; [p curveToPoint:NSMakePoint(43,54) controlPoint1:NSMakePoint(20,22) controlPoint2:NSMakePoint(20,42)]; p.lineWidth=3; [p stroke]; break;
        }
        case 12:
            for(int r=13;r<=29;r+=8) { NSBezierPath *p=[NSBezierPath bezierPath]; p.lineWidth=3; [p appendBezierPathWithArcWithCenter:NSMakePoint(24,16) radius:r startAngle:48 endAngle:132]; [p stroke]; }
            oval(NSMakeRect(21,13,6,6)); line(NSMakePoint(48,11),NSMakePoint(48,49)); line(NSMakePoint(48,49),NSMakePoint(59,39)); line(NSMakePoint(59,39),NSMakePoint(40,22)); line(NSMakePoint(40,39),NSMakePoint(59,22)); line(NSMakePoint(59,22),NSMakePoint(48,11));
            if(fx::knownSwitch(feedback) && feedback.on==0) line(NSMakePoint(7,9),NSMakePoint(60,57)); break;
        case 13:case 14:
            // Sibling-owner photo: four upper keys, two lower keys and a space bar.
            rectangle(NSMakeRect(5,10,54,30),2);
            for(int col=0;col<4;++col) [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(12+col*12,27,5,6) xRadius:0.7 yRadius:0.7] fill];
            for(int col=0;col<2;++col) [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(12+col*36,17,5,6) xRadius:0.7 yRadius:0.7] fill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(24,17,17,6) xRadius:0.7 yRadius:0.7] fill];
            { NSBezierPath *sun=[NSBezierPath bezierPath]; sun.lineWidth=3; [sun appendBezierPathWithArcWithCenter:NSMakePoint(32,40) radius:10 startAngle:0 endAngle:180]; [sun stroke]; }
            for(int i=0;i<5;++i) { double a=i*3.141592653589793/4; line(NSMakePoint(32+15*cos(a),40+15*sin(a)),NSMakePoint(32+21*cos(a),40+21*sin(a))); } break;
        default:break;
    }
}
}
@interface FXFeedbackPanel : NSPanel
@end
@implementation FXFeedbackPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
@interface FXFeedbackView : NSView
@property uint32_t code;
@property fx::Feedback feedback;
@property(copy) NSString *caption;
@end
@implementation FXFeedbackView
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    // Opacity follows the retained legacy ATK resource's center alpha; the
    // 270-point shape/position remains the later ASUS FAQ family reference.
    BOOL opaque=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    [[NSColor colorWithWhite:0 alpha:opaque?1.0:193.0/255.0] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:corner yRadius:corner] fill];
    [[NSColor colorWithWhite:1 alpha:NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast?0.8:0.15] setStroke];
    NSBezierPath *border=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:corner yRadius:corner]; border.lineWidth=1; [border stroke];
    [NSColor.whiteColor set];
    [NSGraphicsContext saveGraphicsState]; NSAffineTransform *transform=[NSAffineTransform transform]; uint32_t key=self.code-FX_FN_EVENT_BASE; CGFloat scale=(key==10 || key==13 || key==14)?2.34:1.8; [transform translateXBy:(side-64*scale)/2 yBy:95]; [transform scaleBy:scale]; [transform concat]; icon(self.code-FX_FN_EVENT_BASE,self.feedback); [NSGraphicsContext restoreGraphicsState];
    // Unknown is visibly different from Off: never use the last requested state.
    bool known=self.feedback.state==fx::FeedbackState::Readback &&
        ((key==7 || key==8 || key==13 || key==14)?fx::validLevel(self.feedback.level):fx::knownSwitch(self.feedback));
    if(!known) {
        NSString *mark=self.feedback.state==fx::FeedbackState::Cancelled?@"×":
            (self.feedback.state==fx::FeedbackState::Disabled?@"–":
             (self.feedback.state==fx::FeedbackState::Dispatched || self.feedback.state==fx::FeedbackState::Accepted?@"…":@"?"));
        [[NSColor colorWithWhite:1 alpha:0.65] setStroke]; oval(NSMakeRect(side-37,side-37,23,23));
        [mark drawInRect:NSMakeRect(side-31,side-35,18,23) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:17 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.whiteColor}];
    }
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.alignment=NSTextAlignmentCenter;
    NSDictionary *title=@{NSFontAttributeName:[NSFont systemFontOfSize:18 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:paragraph};
    [titleFor(self.code) drawInRect:NSMakeRect(10,62,side-20,25) withAttributes:title];
    NSDictionary *caption=@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.88 alpha:1],NSParagraphStyleAttributeName:paragraph};
    [self.caption drawInRect:NSMakeRect(8,21,side-16,36) withAttributes:caption];
    if(fx::validLevel(self.feedback.level)) {
        [[NSColor colorWithWhite:0.48 alpha:1] setFill]; NSRect track=NSMakeRect(8,6,side-16,4); [[NSBezierPath bezierPathWithRoundedRect:track xRadius:2 yRadius:2] fill];
        track.size.width*=self.feedback.level; [NSColor.whiteColor setFill]; [[NSBezierPath bezierPathWithRoundedRect:track xRadius:2 yRadius:2] fill];
    }
}
@end
@interface FXFeedbackController () {
    FXFeedbackPanel *_panel;
    FXFeedbackView *_view;
    NSTimer *_timer;
    uint64_t _serial;
}
@end
@implementation FXFeedbackController
- (instancetype)init {
    self=[super init]; if(!self) return nil;
    _panel=[[FXFeedbackPanel alloc] initWithContentRect:NSMakeRect(0,0,side,side) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _panel.opaque=NO; _panel.backgroundColor=NSColor.clearColor; _panel.hasShadow=NO; _panel.ignoresMouseEvents=YES;
    _panel.level=NSStatusWindowLevel; _panel.hidesOnDeactivate=NO; _panel.animationBehavior=NSWindowAnimationBehaviorNone;
    _panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorIgnoresCycle;
    _view=[[FXFeedbackView alloc] initWithFrame:NSMakeRect(0,0,side,side)]; _panel.contentView=_view;
    [_view setAccessibilityElement:YES]; [_view setAccessibilityRole:NSAccessibilityStaticTextRole];
    return self;
}
- (void)dismiss { ++_serial; [_timer invalidate]; _timer=nil; [_panel orderOut:nil]; _panel.alphaValue=1; }
- (void)showCode:(uint32_t)code feedback:(fx::Feedback)feedback detail:(NSString *)detail {
    if(!fx::feedbackCode(code) || !FXIsConsoleUser()) { [self dismiss]; return; }
    feedback=fx::sanitizedFeedback(feedback);
    ++_serial; [_timer invalidate];
    _view.code=code; _view.feedback=feedback;
    NSString *caption=@"Not confirmed\nSee menu status";
    if(detail.length) caption=detail;
    else if(feedback.state==fx::FeedbackState::Readback) {
        if(code<=FX_FN_EVENT_BASE+3) caption=feedback.on==1?@"Muted · OS reports":(fx::validLevel(feedback.level)?[NSString stringWithFormat:@"%d%% · OS reports%@",static_cast<int>(std::lround(feedback.level*100)),fx::knownSwitch(feedback)?@"":@"\nMute state unknown"]:(feedback.on==0?@"Unmuted · OS reports":@"Mute and level unknown"));
        else if(code==FX_FN_EVENT_BASE+4 && fx::knownSwitch(feedback)) caption=feedback.on?@"Muted · default input":@"Unmuted · default input";
        else if(code==FX_FN_EVENT_BASE+6 && fx::knownSwitch(feedback)) caption=feedback.on?@"On · driver reports":@"Off · driver reports";
        else if(code==FX_FN_EVENT_BASE+12 && fx::knownSwitch(feedback)) caption=feedback.on?@"On · OS reports":@"Off · OS reports\nOther radios not measured";
        else if(fx::validLevel(feedback.level)) caption=[NSString stringWithFormat:@"%d%% · driver reports",static_cast<int>(std::lround(feedback.level*100))];
    } else if(feedback.state==fx::FeedbackState::Accepted) caption=@"Request accepted\nActual state unmeasured";
    else if(feedback.state==fx::FeedbackState::Dispatched) caption=@"Request sent\nCompletion not confirmed";
    else if(feedback.state==fx::FeedbackState::Cancelled) caption=@"Cancelled";
    else if(feedback.state==fx::FeedbackState::Disabled) caption=@"Session action disabled";
    _view.caption=caption; [_view setAccessibilityLabel:[NSString stringWithFormat:@"%@. %@",titleFor(code),caption]]; _view.needsDisplay=YES;
    NSScreen *screen=nil;
    for(NSScreen *candidate in NSScreen.screens) if(CGDisplayIsBuiltin([candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue])) { screen=candidate; break; }
    if(!screen) screen=NSScreen.mainScreen?:NSScreen.screens.firstObject;
    if(!screen) { [self dismiss]; return; }
    NSRect frame=screen.frame,visible=screen.visibleFrame;
    CGFloat x=NSMidX(frame)-side/2,y=NSMinY(frame)+frame.size.height*(self.screenCentered?0.5:(1-0.684))-side/2;
    x=MAX(NSMinX(visible),MIN(x,NSMaxX(visible)-side));
    y=MAX(NSMinY(visible),MIN(y,NSMaxY(visible)-side));
    [_panel setFrameOrigin:NSMakePoint(x,y)];
    _panel.alphaValue=1; [_panel orderFrontRegardless];
    const uint64_t serial=_serial, generation=FXSessionGeneration(); __weak FXFeedbackController *weakSelf=self;
    _timer=[NSTimer timerWithTimeInterval:hold repeats:NO block:^(NSTimer *timer) {
        (void)timer; FXFeedbackController *strongSelf=weakSelf; if(!strongSelf || strongSelf->_serial!=serial) return;
        if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { [strongSelf dismiss]; return; }
        // Timer-owned dismissal avoids a stale animation completion hiding a newer key.
        // Reduce Motion disables the optional short fade.
        if(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) { [strongSelf dismiss]; return; }
        __block unsigned step=0;
        strongSelf->_timer=[NSTimer timerWithTimeInterval:fade/6 repeats:YES block:^(NSTimer *fadeTimer) {
            FXFeedbackController *owner=weakSelf;
            if(!owner || owner->_serial!=serial) { [fadeTimer invalidate]; return; }
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser() || ++step>=6) { [owner dismiss]; return; }
            owner->_panel.alphaValue=1.0-static_cast<double>(step)/6;
        }];
        [[NSRunLoop mainRunLoop] addTimer:strongSelf->_timer forMode:NSRunLoopCommonModes];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)observeCode:(uint32_t)code profile:(const FXProfileSnapshot *)profile deadline:(NSTimeInterval)deadline {
    const uint64_t generation=FXSessionGeneration();
    if(NSProcessInfo.processInfo.systemUptime>deadline) return;
    fx::Feedback feedback; NSString *detail=nil;
    switch(code-FX_FN_EVENT_BASE) {
        case 1:case 2:case 3:feedback=outputFeedback(); break;
        case 7:case 8:feedback=brightnessFeedback(); break;
        case 5:
            if(profile && !(profile->flags&FXFnF5EnabledFlag)) detail=@"Fan shortcut disabled\nCurrent mode unknown";
            else if(profile && profile->lastRequestStatus!=FXAccepted) detail=@"Request not acknowledged\nCurrent mode unknown";
            else if(profile && profile->lastAcceptedProfile<=FXSilent) {
                NSString *name=profile->lastAcceptedProfile==FXNormal?@"Normal":(profile->lastAcceptedProfile==FXSilent?@"Silent":@"Overboost");
                detail=[NSString stringWithFormat:@"Last acknowledged: %@\nCurrent mode unknown",name];
            } else detail=@"No acknowledged mode\nCurrent mode unknown";
            break;
        case 9:detail=@"Display-mode key observed\nResult not verified"; break;
        case 10:detail=@"Touchpad key observed\nResult not verified"; break;
        case 13:case 14:detail=@"Lighting key observed\nLevel not available"; break;
        default:break;
    }
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser() || NSProcessInfo.processInfo.systemUptime>deadline) return;
    [self showCode:code feedback:feedback detail:detail];
}
@end
