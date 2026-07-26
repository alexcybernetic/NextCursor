import AppKit

// Native-cursor suppression is scoped to a process's WindowServer connection,
// so WindowServer restores the cursor when that process exits. A stuck cursor
// therefore means a NextCursor process is still alive and not restoring it.
//
// Note that CGDisplayShowCursor cannot help here, and this script no longer
// calls it: hide counts belong to the connection that raised them, so a
// separate recovery process can only decrement its own count, never another
// process's.

let matches = NSWorkspace.shared.runningApplications.filter { application in
    application.bundleIdentifier?.hasPrefix("com.nextcursor.") == true
}

guard !matches.isEmpty else {
    print("No running NextCursor process. Nothing is holding the cursor hidden.")
    exit(0)
}

for application in matches {
    let label = application.bundleIdentifier ?? "unknown"
    if application.terminate() {
        print("Asked \(label) (pid \(application.processIdentifier)) to quit.")
    } else if application.forceTerminate() {
        print("Force-terminated \(label) (pid \(application.processIdentifier)).")
    } else {
        print("Could not terminate \(label) (pid \(application.processIdentifier)).")
    }
}
