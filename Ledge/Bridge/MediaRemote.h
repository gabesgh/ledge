// Private MediaRemote.framework. Only used on macOS 14 – 15.3: from 15.4 it
// refuses callers without Apple's entitlement, and Ledge falls back to AppleScript.
#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

typedef void (^MRNowPlayingInfoBlock)(CFDictionaryRef _Nullable info);

void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t _Nonnull queue, MRNowPlayingInfoBlock _Nonnull block);
void MRMediaRemoteSetElapsedTime(double elapsedTime);
Boolean MRMediaRemoteSendCommand(uint32_t command, CFDictionaryRef _Nullable options);
