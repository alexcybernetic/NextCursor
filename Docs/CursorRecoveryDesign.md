# Cursor recovery design

This document records the safety boundary for any future global cursor replacement. The global-registration work currently performs read-only inventory only; it does not globally register, remove, or reset cursor entries.

## Verified inventory boundary

The read-only backend resolves only:

- `CGSMainConnectionID`
- `CGSCursorNameForSystemCursor`
- `CGSCopyRegisteredCursorImages`

It deliberately excludes every `CoreCursor*` API. On macOS 26.5.2, `CoreCursorCopyImages` can lazily register a missing numeric cursor and is therefore not a read-only operation.

The bounded inventory covers the system-name table and named candidates `com.apple.cursor.2` through `com.apple.cursor.43`. It cannot enumerate arbitrary third-party registration names because WindowServer exposes no registry enumeration API.

## Required transaction boundary

A same-executable guardian must be the sole owner of cursor mutations, the recovery lock, journal writes, verification, rollback, and restoration. The UI process communicates over an inherited Unix socket and never receives a filesystem path from the guardian.

The recovery root belongs in Application Support with mode `0700`. Files use mode `0600`, directory-relative `openat` operations, `O_NOFOLLOW | O_CLOEXEC`, owner/type validation, bounded sizes, atomic rename, and directory `fsync` after publication.

No cursor mutation may occur until an immutable snapshot is complete and an `applying` phase record is durable. Restoration classifies every current fingerprint independently:

| Current fingerprint | Action |
| --- | --- |
| NextCursor replacement | Restore the captured original |
| Captured original | No operation |
| Different from both | Preserve the foreign value |
| Unreadable | Retain the journal and require recovery |

`CoreCursorUnregisterAll` must never be called automatically.

## Current blocker

`CGSCopyRegisteredCursorImages` returns the effective raster value, geometry, animation timing, and representations. It does not return registration provenance, scope, owner, source metadata, or whether the value is an Apple built-in or a third-party override.

Current WindowServer registration semantics do not provide an exact reversible global override:

- global registration replaces the existing dictionary mapping rather than stacking above it;
- the named remover has no ownership check or previous-value stack;
- Apple `com.apple.coregraphics.*` names are rejected by the per-name remover;
- copied images are reconstructed as DeviceRGB raster values and do not preserve all adaptive/source metadata;
- re-registering copied pixels restores appearance but not the original registry semantics.

Accordingly, the activation gate must reject global replacement with the currently observable evidence. A crash journal cannot compensate for information destroyed by the mutation itself.

## Evidence required before mutation

At least one of these must be proven for every target name:

1. The original mapping survives under a removable NextCursor-owned override, or
2. the original provenance and complete registration semantics can be captured and restored.

Until then, global Apple cursor registration remains disabled. Any registry-semantics experiment must use a unique `com.nextcursor.probe.<UUID>` name in a bounded guardian and must not touch an Apple cursor name.
