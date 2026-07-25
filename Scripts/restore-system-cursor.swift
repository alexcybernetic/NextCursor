import CoreGraphics

// CGDisplayHideCursor and CGDisplayShowCursor use a balanced global count.
// Run this only if NextCursor was force-killed while its cursor was active.
_ = CGDisplayShowCursor(CGMainDisplayID())
