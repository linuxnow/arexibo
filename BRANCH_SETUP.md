# Branch Setup for Two Separate PRs

## Current Situation
We have created changes for two distinct purposes that should be in separate PRs:

1. **DEB Package Support** - Adding Debian package building
2. **Kiosk Separation** - Removing kiosk from arexibo repository

## Required Branch Structure

### PR 1: Add DEB Package Support
**Branch**: `copilot/add-deb-build-workflow`  
**Base commit**: `9e3b858` (Rename arexibo-kiosk to xibo-kiosk for multi-player support)

This branch should contain:
- DEB workflow implementation (.github/workflows/deb.yml)
- Kiosk renamed to xibo-kiosk (for multi-player support)
- RPM spec still includes xibo-kiosk subpackage
- DEB workflow still builds xibo-kiosk package

Commits to include:
- d0cd425: Update all references to use xibo-kiosk naming
- All prior commits with DEB workflow work
- 9e3b858: Rename arexibo-kiosk to xibo-kiosk for multi-player support

###  PR 2: Separate Kiosk Package
**Branch**: `copilot/separate-kiosk-package`
**Base commit**: `9e3b858` (same as PR 1)

This branch should contain ALL commits from PR 1 PLUS:
- a2259e5: Remove kiosk subpackage from arexibo RPM and DEB builds
- 4a60d68: Update README to reference separate xibo-kiosk repository

## Manual Steps Required

Since we cannot force push, here's how to set this up manually:

```bash
# 1. Reset copilot/add-deb-build-workflow to only have DEB work
git checkout copilot/add-deb-build-workflow
git reset --hard 9e3b858
# This branch now has: DEB workflow + kiosk rename

# 2. Ensure copilot/separate-kiosk-package has all commits
git checkout copilot/separate-kiosk-package  
git reset --hard 4a60d68
# This branch now has: DEB workflow + kiosk rename + kiosk separation

# 3. Create PRs from both branches
```

## Summary

- **copilot/add-deb-build-workflow** → Stops at 9e3b858 (keeps kiosk in arexibo)
- **copilot/separate-kiosk-package** → Includes 4a60d68 (removes kiosk from arexibo)

Both PRs can be reviewed independently:
- PR 1 adds DEB packaging capability
- PR 2 prepares for kiosk separation (builds on PR 1)
