# Physical iPhone audio check — pending

Use the actual candidate build after TestFlight upload. These steps have not been performed on a physical phone.

1. With microphone and speech recognition allowed, speak a short Japanese answer. Confirm the level changes and the transcript is reasonable. Stop and use the recording.
2. Tap 「録音を聞く」 before sending. Confirm the recorded voice is audible, pause/resume works, and a second recording contains the new voice and transcript.
3. Submit a disposable test answer. Reopen it after relaunch and play it, checking that the beginning and end are present.
4. Repeat playback with the Ring/Silent switch silent and media volume audible. Confirm output through the built-in speaker, then a connected headset. Disconnect the headset and confirm playback pauses until manually resumed.
5. Start one voice, then another. Only the most recently selected voice should play. Start recording while a previous voice is loading or playing; it must not begin playing into the recording.
6. Make an empty/silent recording and confirm it cannot be uploaded as a successful voice attachment. Test a quietly spoken recording separately.
7. Check an existing voice answer reported as silent. Do not modify or delete it. Record whether it becomes audible with the playback fix, displays a decoding error, or still contains silence.

A user's actual recording is only needed for the last step if they choose to share or play it. Local synthetic test fixtures already verify native decoding, measured signal, and server byte preservation.
