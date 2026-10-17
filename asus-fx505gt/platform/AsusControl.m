#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#include "FXProfileABI.h"
static NSString *const helper=@"/Library/PrivilegedHelperTools/ASUSPlatform/";
static NSDictionary *properties(const char *cls){
 io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(cls));if(!s)return @{};
 CFMutableDictionaryRef d=NULL;IORegistryEntryCreateCFProperties(s,&d,kCFAllocatorDefault,0);IOObjectRelease(s);return CFBridgingRelease(d)?:@{};
}
static BOOL readProfile(FXProfileSnapshot *snapshot){
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(FX_PROFILE_SERVICE));if(!service)return NO;
 io_connect_t c=IO_OBJECT_NULL;IOReturn r=IOServiceOpen(service,mach_task_self(),FX_PROFILE_CONNECT_TYPE,&c);IOObjectRelease(service);if(r)return NO;
 size_t size=sizeof(*snapshot);r=IOConnectCallStructMethod(c,FXQuery,NULL,0,snapshot,&size);IOServiceClose(c);return r==kIOReturnSuccess&&size==sizeof(*snapshot)&&snapshot->version==FX_PROFILE_ABI_VERSION;
}
static NSDictionary *run(NSString *name,NSArray *args){
 NSTask *t=[NSTask new];t.launchPath=@"/usr/bin/sudo";t.arguments=[@[@"-n",([name isEqualToString:@"fxprofile"]?@"/Library/PrivilegedHelperTools/org.fx505gt.fxprofile":[helper stringByAppendingString:name])] arrayByAddingObjectsFromArray:args];
 NSPipe *p=[NSPipe pipe];t.standardOutput=p;t.standardError=p;t.standardInput=[NSFileHandle fileHandleWithNullDevice];
 NSError *e=nil;if(![t launchAndReturnError:&e])return @{@"status":@(-1),@"text":e.localizedDescription?:@"启动失败"};
 NSData *d=[p.fileHandleForReading readDataToEndOfFile];[t waitUntilExit];return @{@"status":@(t.terminationStatus),@"text":[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@""};
}
@interface Control:NSObject<NSApplicationDelegate,NSMenuDelegate>
@property(strong) NSStatusItem *status;@property(strong) NSMenu *menu;@property(strong) NSMenuItem *rpmItem,*normalItem,*awakeItem,*loginItem;@property(strong) NSMutableArray<NSMenuItem*> *fans;
@property(strong) NSWindow *window;@property(strong) NSTextField *rpm,*stateLabel;@property(strong) NSSegmentedControl *fanControl;@property(strong) NSSwitch *awakeSwitch;
@property(strong) NSTask *lease;@property(strong) NSPipe *leaseInput,*leaseOutput;@property BOOL changing,restoreAfterWake,wakeSeen;
@property(strong) NSTask *alwaysLease;@property(strong) NSPipe *alwaysInput,*alwaysOutput;
@property(strong) NSMenuItem *alwaysItem;@property(strong) NSSwitch *alwaysSwitch;
@end
@implementation Control
-(NSString*)loginPath{return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/local.asus.platform.ui.plist"];}
-(NSMenuItem*)item:(NSString*)title action:(SEL)action tag:(NSInteger)tag menu:(NSMenu*)menu{
 NSMenuItem *i=[[NSMenuItem alloc]initWithTitle:title action:action keyEquivalent:@""];i.target=self;i.tag=tag;[menu addItem:i];return i;
}
-(void)setup{
 [[NSDistributedNotificationCenter defaultCenter]addObserver:self selector:@selector(sleepNow:) name:@"org.fx505gt.sleep-request" object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];


 self.status=[[NSStatusBar systemStatusBar]statusItemWithLength:NSVariableStatusItemLength];
 NSImage *im=[NSImage imageWithSystemSymbolName:@"fanblades" accessibilityDescription:@"华硕控制"];im.template=YES;self.status.button.image=im;self.status.button.toolTip=@"FX505GT · 风扇与睡眠";
 self.menu=[NSMenu new];self.menu.delegate=self;self.menu.autoenablesItems=NO;self.status.menu=self.menu;
 [self item:@"华硕 FX505GT" action:nil tag:0 menu:self.menu].enabled=NO;
 self.rpmItem=[self item:@"正在读取风扇…" action:nil tag:0 menu:self.menu];self.rpmItem.enabled=NO;
 [self.menu addItem:NSMenuItem.separatorItem];NSMenuItem *fi=[self item:@"风扇模式" action:nil tag:0 menu:self.menu];NSMenu *fm=[NSMenu new];fm.autoenablesItems=NO;fi.submenu=fm;self.fans=[NSMutableArray new];
 for(NSArray *a in @[@[@"静音",@2],@[@"平衡",@0],@[@"增强",@1]])[self.fans addObject:[self item:a[0] action:@selector(fan:) tag:[a[1]integerValue] menu:fm]];
 [self.menu addItem:NSMenuItem.separatorItem];self.normalItem=[self item:@"合盖睡眠" action:@selector(normal:) tag:0 menu:self.menu];self.awakeItem=[self item:@"合盖保持运行" action:@selector(awake:) tag:0 menu:self.menu];
 self.alwaysItem=[self item:@"一直保持运行（禁止系统睡眠）" action:@selector(always:) tag:0 menu:self.menu];
 [self item:@"立即睡眠" action:@selector(sleepNow:) tag:0 menu:self.menu];
 [self.menu addItem:NSMenuItem.separatorItem];[self item:@"设置…" action:@selector(settings:) tag:0 menu:self.menu];self.loginItem=[self item:@"登录时打开" action:@selector(login:) tag:0 menu:self.menu];[self item:@"退出" action:@selector(quit:) tag:0 menu:self.menu];
 [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];[self refresh];
 [self restoreStartup];
 if([NSProcessInfo.processInfo.arguments containsObject:@"--show-settings"])[self settings:nil];
}
-(void)restorePowerPreferences{
 if([NSUserDefaults.standardUserDefaults boolForKey:@"LidKeepRunning"])[self awake:nil];
 else if([NSUserDefaults.standardUserDefaults boolForKey:@"AlwaysKeepRunning"])[self always:nil];
}
-(void)restoreStartup{
 NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"PreferredFanProfile"];
 if(!saved||saved.integerValue<0||saved.integerValue>2){[self restorePowerPreferences];return;}
 self.changing=YES;NSString *arg=saved.integerValue==2?@"silent":saved.integerValue==1?@"overboost":@"normal";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=run(@"fxprofile",@[@"set",arg]);dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;NSLog(@"ASUS_FAN startup status=%@",r[@"status"]);[self refresh];[self restorePowerPreferences];});});
}
-(BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)flag{[self settings:nil];return YES;}
-(void)menuWillOpen:(NSMenu*)m{[self refresh];}
-(void)refresh{
 NSDictionary *d=properties("AsusSMC"),*power=properties("IOPMrootDomain");
 NSString *cpu=d[@"CPUFanRPM"]?[NSString stringWithFormat:@"%@",d[@"CPUFanRPM"]]:@"—";NSString *gpu=d[@"GPUFanRPM"]?[NSString stringWithFormat:@"%@",d[@"GPUFanRPM"]]:@"—";
 NSString *rpm=[NSString stringWithFormat:@"CPU %@ · GPU %@ 转/分",cpu,gpu];self.rpmItem.title=rpm;self.rpm.stringValue=rpm;
 FXProfileSnapshot snapshot={0};BOOL queried=readProfile(&snapshot);NSNumber *mode=queried&&snapshot.acceptedCount?@(snapshot.lastAcceptedProfile):nil;for(NSMenuItem *i in self.fans){i.state=mode&&mode.integerValue==i.tag?NSControlStateValueOn:NSControlStateValueOff;i.enabled=!self.changing&&queried&&snapshot.supportedProfiles!=0;}
 NSArray *modes=@[@2,@0,@1];NSUInteger ix=mode?[modes indexOfObject:mode]:NSNotFound;self.fanControl.selectedSegment=ix==NSNotFound?-1:(NSInteger)ix;
 BOOL dis=[d[@"FX505GTLidSleepDisabled"]boolValue];BOOL all=[power[@"SleepDisabled"]boolValue];self.alwaysItem.state=all?NSControlStateValueOn:NSControlStateValueOff;self.alwaysSwitch.state=all?NSControlStateValueOn:NSControlStateValueOff;self.normalItem.state=dis?NSControlStateValueOff:NSControlStateValueOn;self.awakeItem.state=dis?NSControlStateValueOn:NSControlStateValueOff;self.awakeSwitch.state=dis?NSControlStateValueOn:NSControlStateValueOff;
 self.stateLabel.stringValue=all?@"一直保持运行：系统睡眠已暂停。":(dis?@"合盖保持运行；仍可通过 F11 手动睡眠。":@"按系统设置睡眠；合盖即睡。 ");
 self.alwaysItem.enabled=!self.changing;self.alwaysSwitch.enabled=!self.changing;self.normalItem.enabled=!self.changing;self.awakeItem.enabled=!self.changing;self.awakeSwitch.enabled=!self.changing;self.fanControl.enabled=!self.changing&&queried&&snapshot.supportedProfiles!=0;
 self.loginItem.state=[[NSFileManager defaultManager]fileExistsAtPath:self.loginPath]?NSControlStateValueOn:NSControlStateValueOff;
}
-(void)error:(NSString*)s{NSAlert *a=[NSAlert new];a.messageText=@"设置未完成";a.informativeText=s.length?s:@"请检查平台服务是否已安装。";[NSApp activateIgnoringOtherApps:YES];[a runModal];}
-(void)fan:(NSMenuItem*)sender{[self setFan:sender.tag];}
-(void)fanSegment:(NSSegmentedControl*)s{NSArray *m=@[@2,@0,@1];if(s.selectedSegment>=0)[self setFan:[m[s.selectedSegment]integerValue]];}
-(void)setFan:(NSInteger)mode{
 if(self.changing)return;self.changing=YES;[self refresh];NSString *arg=mode==2?@"silent":mode==1?@"overboost":@"normal";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=run(@"fxprofile",@[@"set",arg]);dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;if([r[@"status"]intValue]==0)[NSUserDefaults.standardUserDefaults setInteger:mode forKey:@"PreferredFanProfile"];[self refresh];if([r[@"status"]intValue]!=0)[self error:r[@"text"]];});});
}
-(void)awakeSwitchChanged:(NSSwitch*)s{if(s.state==NSControlStateValueOn)[self awake:s];else[self normal:s];}
-(void)awake:(id)sender{
 if(self.changing||self.lease)return;[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"LidKeepRunning"];
 self.changing=YES;self.leaseInput=[NSPipe pipe];self.leaseOutput=[NSPipe pipe];NSTask *t=[NSTask new];self.lease=t;t.launchPath=@"/usr/bin/sudo";t.arguments=@[@"-n",[helper stringByAppendingString:@"AsusAwake"],@"--lid-hold"];t.standardInput=self.leaseInput;t.standardOutput=self.leaseOutput;t.standardError=self.leaseOutput;
 NSError *e=nil;if(![t launchAndReturnError:&e]){self.changing=NO;self.lease=nil;[self error:e.localizedDescription];[self refresh];return;}
 NSPipe *o=self.leaseOutput;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSData *d=[o.fileHandleForReading availableData];NSString *s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"";dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;[self refresh];if(![s containsString:@"READY"]){[self.leaseInput.fileHandleForWriting closeFile];self.lease=nil;[self error:s];}if([NSUserDefaults.standardUserDefaults boolForKey:@"AlwaysKeepRunning"]&&!self.alwaysLease)[self always:nil];});});[self refresh];
}
-(void)normal:(id)sender{
 if(self.changing)return;[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"LidKeepRunning"];self.changing=YES;NSTask *t=self.lease;if(t){[self.leaseInput.fileHandleForWriting closeFile];self.lease=nil;self.leaseInput=nil;self.leaseOutput=nil;}
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(t)[t waitUntilExit];NSDictionary *r=@{@"status":@0,@"text":@""};dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;[self refresh];if([r[@"status"]intValue]!=0)[self error:r[@"text"]];});});[self refresh];
}
-(void)always:(id)sender {
 if(self.changing)return;
 if(self.alwaysLease){self.changing=YES;NSTask *t=self.alwaysLease;[self.alwaysInput.fileHandleForWriting closeFile];self.alwaysLease=nil;self.alwaysInput=nil;self.alwaysOutput=nil;[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"AlwaysKeepRunning"];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[t waitUntilExit];dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;[self refresh];});});[self refresh];return;}
 self.changing=YES;[self refresh];self.alwaysInput=[NSPipe pipe];self.alwaysOutput=[NSPipe pipe];NSTask *t=[NSTask new];self.alwaysLease=t;
 t.launchPath=@"/usr/bin/sudo";t.arguments=@[@"-n",[helper stringByAppendingString:@"AsusAwake"],@"--hold"];t.standardInput=self.alwaysInput;t.standardOutput=self.alwaysOutput;t.standardError=self.alwaysOutput;
 NSError *error=nil;if(![t launchAndReturnError:&error]){self.changing=NO;self.alwaysLease=nil;[self refresh];[self error:error.localizedDescription];return;}
 NSPipe *out=self.alwaysOutput;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSData *d=[out.fileHandleForReading availableData];NSString *text=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"";dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;if([text containsString:@"READY"])[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"AlwaysKeepRunning"];else{[self.alwaysInput.fileHandleForWriting closeFile];self.alwaysLease=nil;[self error:text];}[self refresh];});});
}
-(void)restoreAwakeAfterSleep {
 if(self.restoreAfterWake&&self.wakeSeen&&!self.changing){self.restoreAfterWake=NO;[self always:nil];NSLog(@"ASUS_SLEEP restored previous always-running choice");}
}
-(void)didWake:(NSNotification*)n{self.wakeSeen=YES;[self restoreAwakeAfterSleep];}
-(void)sleepNow:(id)sender{
 if(self.changing)return;
 self.restoreAfterWake=[properties("IOPMrootDomain")[@"SleepDisabled"]boolValue];self.wakeSeen=NO;self.changing=YES;
 NSTask *lease=self.alwaysLease;if(lease){[self.alwaysInput.fileHandleForWriting closeFile];self.alwaysLease=nil;self.alwaysInput=nil;self.alwaysOutput=nil;}
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  if(lease)[lease waitUntilExit];NSDictionary *r=run(@"AsusAwake",@[@"--sleep"]);
  dispatch_async(dispatch_get_main_queue(),^{self.changing=NO;NSLog(@"ASUS_SLEEP status=%@ result=%@",r[@"status"],r[@"text"]);
   if([r[@"status"]intValue]!=0){self.wakeSeen=YES;[self restoreAwakeAfterSleep];[self error:r[@"text"]];}
   else [self restoreAwakeAfterSleep];[self refresh];});
 });
}
-(NSTextField*)label:(NSString*)s small:(BOOL)small{NSTextField *t=[NSTextField labelWithString:s];t.font=[NSFont systemFontOfSize:small?11:13];if(small)t.textColor=NSColor.secondaryLabelColor;return t;}
-(void)settings:(id)sender{
 if(!self.window){
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,480,390) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"华硕控制";self.window.releasedWhenClosed=NO;[self.window center];
 NSStackView *stack=[NSStackView new];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=15;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.window.contentView addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:26],[stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-26],[stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:22]]];
 NSTextField *title=[self label:@"FX505GT · 风扇与睡眠" small:NO];title.font=[NSFont boldSystemFontOfSize:17];[stack addArrangedSubview:title];self.rpm=[self label:@"读取转速…" small:NO];[stack addArrangedSubview:self.rpm];
 self.fanControl=[NSSegmentedControl segmentedControlWithLabels:@[@"静音",@"平衡",@"增强"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(fanSegment:)];[stack addArrangedSubview:self.fanControl];
 [stack addArrangedSubview:[self label:@"风扇由固件自动调节，模式决定温控策略。" small:YES]];
 NSStackView *row=[NSStackView new];row.orientation=NSUserInterfaceLayoutOrientationHorizontal;row.spacing=14;[row addArrangedSubview:[self label:@"合盖保持运行" small:NO]];self.awakeSwitch=[NSSwitch new];self.awakeSwitch.target=self;self.awakeSwitch.action=@selector(awakeSwitchChanged:);[row addArrangedSubview:self.awakeSwitch];[stack addArrangedSubview:row];
 NSStackView *allRow=[NSStackView new];allRow.orientation=NSUserInterfaceLayoutOrientationHorizontal;allRow.spacing=14;[allRow addArrangedSubview:[self label:@"一直保持运行" small:NO]];self.alwaysSwitch=[NSSwitch new];self.alwaysSwitch.target=self;self.alwaysSwitch.action=@selector(always:);[allRow addArrangedSubview:self.alwaysSwitch];[stack addArrangedSubview:allRow];
 [stack addArrangedSubview:[self label:@"合盖选项不拦手动睡眠；一直运行才暂停系统睡眠。" small:YES]];self.stateLabel=[self label:@"" small:YES];[stack addArrangedSubview:self.stateLabel];
 NSButton *b=[NSButton buttonWithTitle:@"打开系统电池设置…" target:self action:@selector(battery:)];[stack addArrangedSubview:b];
 }[self refresh];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
-(void)battery:(id)sender{[[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.battery"]];}
-(void)login:(id)sender{
 NSFileManager *fm=NSFileManager.defaultManager;NSError *e=nil;if([fm fileExistsAtPath:self.loginPath])[fm removeItemAtPath:self.loginPath error:&e];else{[fm createDirectoryAtPath:[self.loginPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&e];NSDictionary *d=@{@"Label":@"local.asus.platform.ui",@"ProgramArguments":@[[NSBundle.mainBundle executablePath]],@"RunAtLoad":@YES};NSData *p=[NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:&e];if(p)[p writeToFile:self.loginPath options:NSDataWritingAtomic error:&e];}if(e)[self error:e.localizedDescription];[self refresh];
}
-(void)quit:(id)sender{[NSApp terminate:nil];}
-(void)applicationWillTerminate:(NSNotification*)n{[self.leaseInput.fileHandleForWriting closeFile];[self.alwaysInput.fileHandleForWriting closeFile];}
@end
int main(int argc,char **argv){@autoreleasepool{NSApplication *a=NSApplication.sharedApplication;static Control *d;d=[Control new];a.delegate=d;[a setActivationPolicy:NSApplicationActivationPolicyAccessory];[a finishLaunching];[d setup];[a run];}}
