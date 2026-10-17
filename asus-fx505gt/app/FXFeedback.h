// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#include "FXFeedbackPolicy.hpp"
#include "FXProfileABI.h"
// All calls on the main thread. No key injection, hardware writes or permission prompts.
@interface FXFeedbackController : NSObject
@property BOOL screenCentered;
- (void)showCode:(uint32_t)code feedback:(fx::Feedback)feedback detail:(NSString *)detail;
- (void)observeCode:(uint32_t)code profile:(const FXProfileSnapshot *)profile deadline:(NSTimeInterval)deadline;
- (void)dismiss;
@end
