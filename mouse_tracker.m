#import <Cocoa/Cocoa.h>

struct State {
  int leftToggleMargin;
  int rightToggleMargin;
  NSRect activeWindowRect;
  CGPoint lastCursorLocation;
  AXUIElementRef application;
};

BOOL cursorIsInBounds(CGPoint location, NSRect bounds) {
  return
    location.x >= bounds.origin.x && location.x <= bounds.origin.x + bounds.size.width &&
    location.y >= bounds.origin.y && location.y <= bounds.origin.y + bounds.size.height;
}

CGEventRef eventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon)
{
  CGPoint location = CGEventGetLocation(event);
  struct State* state = (struct State*) refcon;

  NSRect openArea = {
    .origin = {
      .x = state -> activeWindowRect.origin.x,
      .y = state -> activeWindowRect.origin.y
    },
    .size = {
      .height = state -> activeWindowRect.size.height,
      .width = state -> leftToggleMargin
    }
  };
  NSRect closeArea = {
    .origin = {
      .x = state -> activeWindowRect.origin.x + state -> rightToggleMargin,
      .y = state -> activeWindowRect.origin.y
    },
    .size = {
      .height = state -> activeWindowRect.size.height,
      .width = state -> activeWindowRect.size.width - state -> rightToggleMargin
    }
  };

  if (cursorIsInBounds(location, openArea) && !cursorIsInBounds(state -> lastCursorLocation, openArea)) {
    NSLog(@"open");
  }
  else if (cursorIsInBounds(location, closeArea) && !cursorIsInBounds(state -> lastCursorLocation, closeArea)) {
    NSLog(@"close");
  }
  state -> lastCursorLocation = location;

  return event;
}

void setActiveWindowRect(struct State* state) {
  AXError err;

  AXUIElementRef frontWindow;
  err = AXUIElementCopyAttributeValue(state -> application, kAXMainWindowAttribute, &frontWindow);
  if (err != kAXErrorSuccess) {
    NSLog(@"error getting the app's main window");
  }

  AXValueRef value;

  err = AXUIElementCopyAttributeValue(frontWindow, kAXPositionAttribute, &value);
  if (err != kAXErrorSuccess) {
    NSLog(@"error getting the main window's position");
  }
  AXValueGetValue(value, kAXValueCGPointType, (void *) &(state -> activeWindowRect.origin));
  CFRelease(value);

  err = AXUIElementCopyAttributeValue(frontWindow, kAXSizeAttribute, &value);
  if (err != kAXErrorSuccess) {
    NSLog(@"error getting the main window's size");
  }
  AXValueGetValue(value, kAXValueCGSizeType, (void *) &(state -> activeWindowRect.size));
  CFRelease(value);

  CFRelease(frontWindow);
}

void windowChangeObserverCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notificationName, void* contextData) {
  struct State* state = (struct State*) contextData;
  setActiveWindowRect(state);
  NSLog(@"window_changed");
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    struct State state;

    if (argv[1] != NULL && argv[2] != NULL) {
      state.leftToggleMargin = [[NSString stringWithFormat:@"%s", argv[1]] intValue];
      state.rightToggleMargin = [[NSString stringWithFormat:@"%s", argv[2]] intValue];
    } else {
      state.leftToggleMargin = 50;
      state.rightToggleMargin = 250;
    }

    state.lastCursorLocation.x = 0;
    state.lastCursorLocation.y = 0;

    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    ProcessSerialNumber psn;
    pid_t pid;

    // get the Sublime Text psn from the list of running apps
    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSArray* apps = [workspace runningApplications];
    for (NSRunningApplication* a in apps) {
      if ([a.localizedName isEqualToString:@"Sublime Text"]) {
        pid = a.processIdentifier;
        GetProcessForPID(pid, &psn);
      }
    }

    // initialize the new window change observer
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    state.application = app;

    AXObserverRef observer;
    AXError err = AXObserverCreate(pid, windowChangeObserverCallback, &observer);
    if (err != kAXErrorSuccess) {
      NSLog(@"error initializing observer");
    }

    AXObserverAddNotification(observer, app, kAXWindowResizedNotification, &state);
    AXObserverAddNotification(observer, app, kAXWindowMovedNotification, &state);
    AXObserverAddNotification(observer, app, kAXWindowCreatedNotification, &state);
    AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification, &state);

    CFRunLoopAddSource(
      [runLoop getCFRunLoop],
      AXObserverGetRunLoopSource(observer),
      kCFRunLoopDefaultMode
    );

    // get the initial window's rect
    setActiveWindowRect(&state);

    // initialize the tap for the psn of Sublime Text
    CFMachPortRef tap = CGEventTapCreateForPSN(
      &psn,
      kCGHeadInsertEventTap,
      kCGEventTapOptionListenOnly,
      CGEventMaskBit(kCGEventMouseMoved),
      (CGEventTapCallBack) eventTapFunction,
      &state
    );

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(NULL, tap, 0);

    CFRunLoopAddSource(
      [runLoop getCFRunLoop],
      runLoopSource,
      kCFRunLoopDefaultMode
    );
    CGEventTapEnable(tap, YES);
    [runLoop run];

    CFRelease(app);
  }
  return 0;
}
