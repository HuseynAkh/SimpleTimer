# Privacy

SimpleTimer stores sessions, settings and history in its local app container. It does not run analytics, advertising or a network server, and has no AI API integration or API key.

The paired Apple Watch receives the current timer and session presets through Apple's WatchConnectivity. Complete history stays on the iPhone.

Export is explicit. AI reports contain dates, durations, pauses and outcomes, plus session names only if enabled. JSON backups contain full finished-session records, including names. Review a report before sharing it. Once you share it, the destination app's privacy rules apply.

Temporary AI reports are stored in the app's temporary directory; a new report replaces the previous temporary report. Saved exports outside the app remain until you remove them. Device backups may contain app data according to your system settings. Deleting SimpleTimer removes its local app data. Export a backup first if you want to keep history.

## Publishing changes

Use your GitHub no-reply address for Git commits. In GitHub email settings, enable **Keep my email addresses private** and **Block command line pushes that expose my email**. Configure this checkout before committing:

```sh
git config user.email YOUR_GITHUB_NOREPLY_ADDRESS
git config core.hooksPath .githooks
```

The hooks check effective author and committer identities, staged files, commit messages and every commit reachable from a pushed branch or tag. They reject personal email addresses, private signing files and image metadata. The automated workflow repeats these checks after a push; local hooks provide the check before publication. Hooks can be bypassed, so keep them enabled and do not use `--no-verify` to publish.

After a history reset, use a fresh clone. Merging an old checkout can bring removed history back.
