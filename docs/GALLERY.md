# SimpleTimer gallery

One view of the experience: time a session or let a stopwatch run on iPhone, review your week, and keep it in reach from the Mac menu bar and Apple Watch.

![Stopwatch, Activity, Mac menu bar and Apple Watch](release-images/overview.jpg)

Open a full-resolution screen: [Stopwatch](release-images/stopwatch.png) · [Timer](release-images/dashboard-running.png) · [Activity](release-images/activity.png) · [Mac menu bar](release-images/mac-panel.png) · [Apple Watch](release-images/watch.png) · [Watch widget](release-images/watch-widget.png) · [Live Activity](release-images/live-activity.png).

These are real app screens in dark mode: iPhone and Apple Watch from paired simulators, and the Mac drop-down from the Mac app. The Activity example uses 110 synthetic sessions: two complete weeks plus the two days before capture, which keeps the streak going. The featured complete week contains 56 sessions, 20h 15m tracked, 91% completed and a 17 day streak. The stopwatch is a synthetic "Chapter three" session. The Live Activity is shown paused because the simulator hides running seconds on the Lock Screen. The device frames and the menu bar strip are decorative; no personal device screens or history are used.

## Updating the gallery

The [layout](gallery/overview.html) and [styles](gallery/gallery.css) place the original screenshots without redrawing the interface. All text uses Libre Caslon Text, loaded from Google Fonts: bold for headlines, regular spaced capitals for the small masthead and tagline. The masthead uses the app icon, so capture with network access. Serve this repository locally, open the layout at a 1600 × 1100 viewport and capture it to `release-images/overview.jpg`.

Capture current controls, use a populated complete week for Activity, and check every image at full size. Strip image metadata before publishing. Keep private captures, timer backups, signing files and device identifiers out of this folder.
