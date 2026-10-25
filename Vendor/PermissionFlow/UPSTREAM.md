# PermissionFlow

Source: https://github.com/jaywcjlove/PermissionFlow
Version: 2.11.4
Commit: 65434c9ae04dba97cf52c1dffbe3e4e62b547c82
License: MIT, preserved in LICENSE

Included targets: PermissionFlow and SystemSettingsKit, with their original resources

## Local changes

- Trailing whitespace is normalized

- Package.swift exposes only the macOS targets used by Puv
- Swift 6.1 enables IsolatedDeinit for the upstream isolated destructor; Swift 6.2 and later use the stable feature
- SettingsWindowTracker follows the privacy list add/remove row when Accessibility can read the System Settings hierarchy
- Unavailable hierarchy or an unrecognized layout retains the original Window Server geometry fallback
- Internal hierarchy inspection runs at most twice per second, except after a window move

## Update

Compare these two targets against the pinned upstream commit, then reapply the SettingsWindowTracker changes and run the Puv verification script
