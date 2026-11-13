# Working on SimHelp

Keep app and documentation text in English. Use SimHelp for visible branding and TheSkeezad for the personal adaptation author. Preserve required license and dependency notices.

Use the component layout documented in README.md. Keep secrets and generated outputs in ignored local directories. Never rename authentication or wire-protocol constants as a cosmetic change.

Run `python scripts/check_android_text.py` and `python scripts/audit_ios_english.py` after changing user-facing strings. Build the affected app after changing source paths, manifests, package names, or project settings. Verify call audio and permissions on real devices separately from compilation.
