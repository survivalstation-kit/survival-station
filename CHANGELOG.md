# Changelog

Every portal page shows the version next to the Survival Station name, and the builder window, start window and build log show it too. It is set in one place, `portal/version.js`.

To release a new version:
1. Raise the number in `portal/version.js`:
   - patch (1.0.**1**) for fixes,
   - minor (1.**1**.0) for new features,
   - major (**2**.0.0) for changes that need a rebuilt drive.
2. Add a section below.
3. Commit, and tag the commit `vX.Y.Z`.

Kits pick up the new version with **Verify / repair** or **Check for updates**.

## 1.0.0 (2026-11-01)

The first version.

**On the drive**
- Local AI: llama.cpp with Qwen3-4B, Llama-3.2-1B and Qwen3-8B. It runs on Windows, Mac and Linux (x64 and arm64), with no install.
- The AI looks questions up in the offline library first and cites its sources as [1] and [2].
- Offline library (Kiwix) in English and Portuguese, from medical guides up to complete Wikipedia.
- Offline maps: a world overview on every drive, plus street maps. USA, Canada and Alaska are cut along the border so they don't overlap.
- Emergency cards in English and Portuguese, the Portuguese set with Brazil-specific cards. Survival-Data. Android apps.
- Phone access over a hotspot. An iPhone and iPad guide, with copy-paste setup for the phone AI apps (`models/PHONE-AI-SETUP.txt`).
- A Help page, a My kit page, and a portal in two languages.

**Building and looking after a drive**
- Builder window (`MAKE-USB.bat`):
  - every item as a checkbox, with today's size and a live total that shows whether it fits;
  - Lite, Standard and Full quick picks;
  - items that include others grey out the smaller ones;
  - your own map area;
  - formatting as exFAT.
- Install to a USB drive or to a folder on the computer, with a desktop shortcut.
- Overall progress bar with time left, in the build window, the taskbar title, the builder window and the My kit page.
- `BUILD-CHOICES.txt` on every drive, to finish a stopped build: the choices are ticked again, or use Resume.
- Check for updates: newer library editions, AI engine, maps over a year old, Survival-Data and app pages.
- Verify / repair: checks every file, including incomplete library books and maps found offline, refreshes the app files and downloads again what is broken or missing.
- `COPY-KIT.bat`: copies a finished kit to another drive or computer with no internet, and can resume.
- Logs for every build, size check and copy, in `logs/`.
- Text-mode alternatives: `MAKE-USB.bat text` and `make-usb.py`.
