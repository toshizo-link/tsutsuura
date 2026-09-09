# Independent code review notes

The recorder review checked locking, tap lifetime, explicit AAC finalization, failure cleanup, permission/callback generations, and shared-session teardown. It identified retained transcript on re-recording; the final source clears the transcript when a new real capture begins. No other actionable recorder issue remained after that correction.

The playback review identified an older slow media download stealing playback after a newer tap. A shared playback-intent token is now reserved synchronously at the tap, checked when bytes arrive, and invalidated by later selections or recording start. An old card can only cancel its own pending intent. The reviewer confirmed the revised ordering, shared-session ownership and deferred finish-callback guards without remaining actionable behavioral findings.

Visual QA identified dark preview text over a translucent cyan fill on the dark dotted background. The preview now uses the existing opaque light sky card color and retains dark text with a square outline. Final visual evidence is saved separately after the affected UI rerun.

Reviews and tests used repository code and synthetic audio. They do not establish physical microphone or speaker behavior, or the condition of any existing user's recording.
