---
trigger: always_on
---

# Release Version Consistency

- **Check Info.plist first**: Before creating a new git tag for release (e.g., `v0.1.0-beta.X`), you **MUST** ensure `Info.plist` is updated.
    - `CFBundleShortVersionString`: Must match the target version string (e.g. `0.1.0-beta.6`).
    - `CFBundleVersion`: Must be incremented (integer).
- **Reason**: Sparkle uses the app's internal `Info.plist` version to determine if an update is available. If the git tag is new but `Info.plist` is old, the update check will assume the app is already up-to-date and fail to offer the update.
- **Order of Operations**:
    1. Update `Info.plist`
    2. Commit & Push
    3. `git tag ...`
    4. `git push ...`
