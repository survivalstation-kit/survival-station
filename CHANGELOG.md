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

## 1.4.0 (2026-11-02)

- **Search the whole kit.** A search box on the home page and a **Search** link on every page. One search covers:
  - the emergency cards, radio and help pages, section by section;
  - the Survival Data guide titles and their sections;
  - your own documents;
  - the full text of every library book, in each language.

  It ignores accents ("agua" finds "água"), highlights the words found, and offers to pass the question to the AI. It doesn't look inside PDFs.
- The radio card's "Much more in Survival Data" now links straight to the one radio guide there (*Radio Monitoring*) and to the library's articles on amateur radio in emergencies. The Radio page has the same links.
- A link like `chat.html?q=…` fills in the question on the AI page without sending it.

## 1.3.0 (2026-11-02)

- **New Radio page** (home tile 📡, English and Português), made to be printed and kept with the radios:
  - how to call for help, and in which order to try channels;
  - the 3-3-3 listening plan;
  - the frequencies to have: ham 2 m and 70 cm calling, the 22 FRS/GMRS channels, marine 16/9/22A, weather radio, MURS, aviation 121.5, FM and CB, with Brazil notes;
  - who may transmit where, and the license each country needs;
  - setting up a **Baofeng UV-5R** (keys, menus, saving a channel with the keypad) and a **TIDRADIO TD-H3 PLUS** (versions, phone app, wireless copy);
  - range and battery tips, and a checklist for before a disaster.
- **Channel file for CHIRP** (`portal/radio/survival-channels.csv`): every frequency on the page in one import. Channels the radios may only listen to are set to receive only.
- The emergency cards and the Help page link to it.

## 1.2.1 (2026-11-02)

- **Pages refresh themselves after an update.** The AI server sends the pages with no caching rules, so after an update a browser could keep showing its saved copy of the old pages: the old version tag, and a map page that didn't know about the 1.2.0 map server. Each page now checks the kit's version and, if it changed, loads the page, scripts and styles fresh and reloads once. Browsers still holding pages from before 1.2.1 need one **Ctrl+F5** (Ctrl+Shift+R; on a phone, reload the page).

## 1.2.0 (2026-11-02)

- **Fixed: on Windows, street maps over 2 GB didn't show, only the world map.** The AI server, which also sends the portal pages, can't send files over 2 GB on Windows. Tested: 1.9 GB works; 2.1 GB and 4.1 GB return "not found". That covers USA, Canada, Canada south of 60 and Brazil. Kits with such a map now carry a small map server (`tools\win\pmtiles.exe`, the same tool that cuts the maps), and `START-WINDOWS.bat` starts it on port 8092. The map page uses it only for maps it can't load directly, so Mac and Linux work as before. **Verify / repair** adds it to kits that already have a big map. Phones on the hotspot use it too; click **Allow** if the firewall asks again.
- `maps/index.json` now records each map's zoom levels and area.
- **"Go to…" menu on the map** (top left): jumps to the world or to any region on the kit. The map reopens where it was last left, so before this a new region could sit out of view.

## 1.1.2 (2026-11-02)

- **Fixed: the Survival-Data page didn't open its sections.** Its lists start hidden, but the first click on a heading "hid" them again, so nothing seemed to happen until a second click. The builder now patches that page on every build, and **Verify / repair** patches kits that already have it.

## 1.1.1 (2026-11-02)

- **Test drive speed** shows one decimal on slow drives (1.5 MB/s instead of 2 MB/s).

## 1.1.0 (2026-11-01)

- **New "Download method" choice** in the builder window (and `-Staging` on the command line):
  - **Automatic** (the default) tests the drive's write speed for about 3 seconds at the start of the build:
    - 150 MB/s or faster (a fast USB SSD or 10 Gbps port): everything goes straight to the drive.
    - 25–150 MB/s: maps are prepared on this computer's disk and copied over; downloads go straight to the drive.
    - Under 25 MB/s: maps and downloads are both prepared on this computer and copied over.
  - **Prepare on this computer, then copy to the drive**: always stage.
  - **Straight to the drive**: never stage.
- **"Test drive speed" button** shows the drive's write speed and what Automatic will do with it.
- Any file without room on the computer's disk goes straight to the drive. Staged files are copied with the progress table, and the staging folder is emptied when the build finishes. A half-finished download already on the drive continues where it is.

## 1.0.9 (2026-11-01)

- **Maps retry after a dropped connection.** A brief network drop ("connection was aborted") stopped the whole build. Now the map starts again after 15 seconds, up to 3 tries, and the reason is shown in plain words. The map tool can't resume, but cutting a map on the computer's disk is fast (about 50 MB/s in testing), so a retry costs minutes.

## 1.0.8 (2026-11-01)

- **Big maps no longer crawl on USB sticks.** The map tool writes in random order, and on a USB stick Windows first fills the whole file with zeros, so a 9 GB map could receive almost nothing for many minutes. Maps are now cut on the computer's own disk and then copied to the drive in one go, with progress. If the computer's disk is too full, they're cut straight onto the drive as before.
- **Map progress is real.** It follows the bytes the map tool writes. The tool's own percentage only changes when big chunks finish, so the table could sit at 0%.
- **A stuck map is restarted.** With no map data for 10 minutes, the map tool restarts once, then the build stops with a clear message.
- **Downloads and map cutting stop together with the build.** Closing the build window used to leave them running in the background, still writing to the drive.
- **Only one builder window at a time.** Opening MAKE-USB again brings the open window to the front. Two windows reading the same busy drive made both freeze.

## 1.0.7 (2026-11-01)

- **The builder window reliably opens in front.** The 1.0.5 fix (topmost + activate) doesn't always get past Windows' rule against windows jumping in front, and the window could still open behind others. It now also minimizes and restores itself once on opening, which Windows always brings to the front.

## 1.0.6 (2026-11-01)

- **Build progress is now a table with grid lines**, redrawn in place every half second. One row covers the current file or map, and one the whole build. Columns: a progress bar with the percentage, downloaded so far, speed and time left. It replaces curl's own display, whose columns ("% Xferd", "Dload") were hard to read.
- Speeds show as KB/s or MB/s with decimals (944 KB/s, 1.48 MB/s).
- The build log keeps one line per finished file instead of every update. Without a console window to redraw, a plain progress line appears every 15 seconds.

## 1.0.5 (2026-11-01)

- **The builder window opens in front.** Started from MAKE-USB.bat, it used to open behind other windows, so "Opening the builder window..." looked stuck.
- The black MAKE-USB window now says to check the taskbar if the builder isn't visible, and that it closes by itself when the builder closes.

## 1.0.4 (2026-11-01)

- **The build window shows live progress again.** Each download has curl's own display, updated every second: percent, MB received, speed and time left for that file. Maps show a live line with their percentage and the time so far.
- After each file, one line shows where the whole build stands: "42% of the build done: 7.4 of 17.6 GB, about 12h 42m left". The window title, the builder window and the My kit page still show the overall figures.
- Removed the slow overall bar at the top of the build window. On big builds it barely moved, so the build looked stuck.

## 1.0.3 (2026-11-01)

- The time left shows days for long builds ("1d 3h"), and hours and minutes below a day ("12h 42m"). This applies in the build window, the taskbar title, the builder window and the My kit page.

## 1.0.2 (2026-11-01)

- **Fixed: builds of more than about 2 GB stopped right away** with "Cannot convert value … to type System.Int32". The time-left calculation in the progress bar used a 32-bit number. The same trap was fixed in the download speed, the map progress, and the size labels in the builder window and copy tool.

## 1.0.1 (2026-11-01)

- **Removed the "Survivors guide" library book.** It turned out to be the Vampire Survivors video-game wiki, added by mistake because of its file name. The AI's library lookup could quote game items as survival advice. **Verify / repair** and **Check for updates** remove it from drives that already have it, with no internet needed.
- The start windows now name the model for old computers (Llama-3.2-1B).
- Tested and **not added:** Qwen3-1.7B. It's twice as fast as Qwen3-4B, but it gave unsafe water-safety advice even with a library passage.
- Known limit: the "zimgit" books (water, medicine, food, after a disaster, knots) are collections of PDF manuals. They can be opened and read, but they have no search index, so the AI can't quote them.

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
