# Changelog

Every portal page shows the version next to the Survival Station name, and the builder window, start window and build log show it too. It is set in one place, `portal/version.js`.

To release a new version:
1. Raise the number in `portal/version.js`:
   - patch (1.0.**1**) for fixes,
   - minor (1.**1**.0) for new features,
   - major (**2**.0.0) for changes that need a rebuilt drive.
2. Add a section below.
3. Commit, and tag the commit `vX.Y.Z`.

Kits pick up the new version with **Verify / repair** or **Check for updates** (from the latest GitHub release when there is internet, from 1.21.0 on).

## 1.37.0 (2026-11-08)

- **Hiren's BootCD PE** added to the optional bootable systems (MAKE-BOOTABLE.bat): a Windows (WinPE) rescue environment with Windows-native repair, partition, backup and recovery tools. Downloaded from the official site and checked against its official SHA-256.
  - **Personal recovery use only.** It is built on **Microsoft Windows PE** (restricted redistribution) and bundles third-party tools under various terms, so the menu, the on-drive README, the Help page and `THIRD-PARTY-NOTICES.md` all warn: use it for your own computer, but **do not share or copy kits that contain it** (the free Linux systems remain fine to share).
  - Sergei Strelec's WinPE and MediCat USB were **not** added: they have no clean, verifiable official download, and they bundle commercial/cracked software, which would not fit a freely shareable open-source kit. Any ISO you obtain legally can still be dropped into the drive's `ISO\` folder by hand and Ventoy will list it.
## 1.36.0 (2026-11-08)

- **"No AI" option on the start menu (Windows).** Type **0** when the kit asks which model to start, and it runs **without loading the AI** - faster, far less memory, good for old computers or when you only need the reference. The **library, offline map, search, emergency cards, tools, books and the rest still work** over http://localhost:8080; only the chat and photo features are off.
  - A small static web server (`setup\portal-server.ps1`) serves the pages in this mode, since normally the AI program serves them. It supports HTTP range requests, so the offline map (PMTiles) still loads, and blocks path traversal. This computer only; phones still need AI mode.
  - The home page shows **"AI: off (No-AI mode)"** and a clear notice (not "still loading"); the chat page explains how to turn the AI on (restart and pick a model instead of 0). The map tile stays available.
  - The same static server now also powers the zero-models fallback, so a kit with no AI model still serves the map and search instead of only opening files.
## 1.35.1 (2026-11-08)

- **`BOOTABLE-DRIVE.txt`** added to the kit root: a plain-text guide (English and Portuguese) to making the stick bootable, starting a computer from it, and scanning for viruses (ClamAV and Kaspersky), readable in any text editor without opening the portal. It ships on every kit.

## 1.35.0 (2026-11-08)

- **Virus scanning added to the bootable drive.**
  - **ClamAV** (free, open source): MAKE-BOOTABLE.bat writes `clamav-scan.sh` to the drive. From Linux Mint you run it to scan a computer's disk from outside Windows (install, update signatures, scan, list what it finds).
  - **Kaspersky Rescue Disk** added to the optional systems menu: a bootable antivirus that updates its own signatures and scans. It has no published checksum and is refreshed daily, so it is downloaded over HTTPS from Kaspersky's official domain (verified by host, not checksum) with a clear note; Kaspersky is a Russian company and some organisations avoid it.
  - Help, the on-drive `ISO\READ-ME.txt` and `THIRD-PARTY-NOTICES.md` explain both and when to use an offline scan.
## 1.34.0 (2026-11-08)

- **MAKE-BOOTABLE.bat now offers several systems on one drive** (Ventoy lists each in its boot menu; pick which to start). Besides Linux Mint, optional and all free, each downloaded from its official site and checked against its official SHA-256:
  - **SystemRescue** - repair a broken Windows/Linux start-up, recover deleted files, and **reset the password of a local Windows account you are locked out of** (includes chntpw).
  - **Rescuezilla** - back up and restore a whole disk with simple screens.
  - **Memtest86+** - test the computer's memory (RAM) for faults.
  - **antiX** - a very light Linux for old or slow computers.
  - **Kali Linux** - a security-testing system, **for checking the security of your own network and devices, or ones you have written permission to test** (for example your own Wi-Fi). Using it against anything else is illegal and is the user's responsibility; the kit's "use at your own risk" terms apply.
  - Each resolver finds the project's current version and checksum at run time, so downloads stay up to date. Run MAKE-BOOTABLE.bat again to add or update systems; nothing is erased once the drive is bootable.
- Help, the on-drive `ISO\READ-ME.txt` and `THIRD-PARTY-NOTICES.md` updated, with the authorised-use note for Kali.
## 1.33.1 (2026-11-08)

- **Verify / repair now checks the official guides** (`portal\guides`) and downloads any that are missing. Before, only a build or an update fetched them, so a kit that was only verified said "0 to fix" without them.

## 1.33.0 (2026-11-08)

- **Bootable stick (optional): `MAKE-BOOTABLE.bat`** (Windows). Makes a USB drive able to start a computer whose own disk or Windows has failed, into **Linux Mint XFCE**, where the whole kit runs (`bash START-LINUX.sh`) and files can be copied from the computer's disk to safety.
  - Installs **Ventoy** (free, open source): a small boot section plus the normal exFAT partition, so the kit works on Windows, Mac and Linux exactly as before. Downloads the newest **Linux Mint XFCE** (~2.9 GB) into `ISO\`. Both are checked against their official SHA-256 checksums (Ventoy's program is not code-signed). Ventoy only looks in `ISO\`, so its start menu stays fast even with a big kit.
  - Safety: only USB drives are offered (never the computer's own or system disks); it shows the drive's name, size and whether it holds a kit, and needs **ERASE** typed to continue. It runs from a copy in TEMP, so it works even when started from the stick it erases. On a stick that is already bootable it erases nothing and only adds or updates Linux Mint.
  - It erases the stick the first time: copy the kit to the computer with COPY-KIT (This computer) first, and back afterwards. Ventoy's non-destructive install can't be used, because it does not support exFAT on Windows.
  - Help (new section "Starting a computer from the stick"), README, LEIA-ME, `ISO\READ-ME.txt` on the stick, and `THIRD-PARTY-NOTICES.md` (Ventoy GPL-3.0, Linux Mint).
## 1.32.0 (2026-11-08)

- **Two new emergency cards**, English and Portuguese, from Ready.gov and CDC guidance: **Nuclear explosion or radiation** (drop and cover from a flash, get inside, stay inside 24 hours, stay tuned, removing contamination, potassium iodide only when told) and **Chemical leak, toxic gas or chemical attack** (upwind and uphill, sheltering in place, removing and washing off contamination; Brazil: 192, 193 and Disque-Intoxicação 0800 722 6001). The AI finds them like the other cards.
- **Official guides on every kit** (`portal/guides`, about 23 MB, listed on the Books page): US Army **FM 3-11.4 NBC Protection** (approved for public release), FEMA's **Planning Guidance for Response to a Nuclear Detonation** (2022) and **the First 72 Hours** (2023). Chosen to fill what Survival-Data lacks (chemical and biological protection, current nuclear guidance). Existing kits get them with Check for updates.
- Firearms operator manuals were left out on purpose: they are not released to the public (distribution C), even though copies circulate online. Survival-Data already has the public marksmanship manuals.
## 1.31.0 (2026-11-08)

- **📖 Books** (new page and tile):
  - **The Art of War** by Sun Tzu, all 13 chapters, in **English and Portuguese**: a new translation made for the kit **from the original Chinese** (public domain), released into the public domain (CC0), so it has no copyright issue anywhere. Chapter titles in Chinese, a button to switch language, and **🔊 Listen**: the device reads a chapter or the whole book aloud with its own voice, offline, highlighting each paragraph, with pause and stop.
  - Not based on Lionel Giles's 1910 translation or its LibriVox recordings: Giles died in 1958, so his translation is still protected in Brazil, Portugal, Europe and other countries until 2029.
  - **Further reading** (links only, nothing copied): Robert Greene's *The 48 Laws of Power*, *The Laws of Human Nature* and *The 33 Strategies of War* (find in a library or Open Library), and free public-domain classics on the same themes on Project Gutenberg: Marcus Aurelius's *Meditations*, Machiavelli's *The Prince*, Le Bon's *The Crowd*, Laozi's *Tao Te Ching*.
## 1.30.0 (2026-11-08)

- **More practical knowledge in the library** (English), chosen to fill gaps the kit didn't cover, with nothing duplicated:
  - **Standard** (+~3 GB): expert questions and answers from Stack Exchange on cooking and food preserving, homebrewing, gardening and growing food, woodworking, arts and crafts, the outdoors, amateur radio, pets and sustainable living; **Simple English Wikipedia** (no pictures) and **PhET** interactive science and maths, for children and learners.
  - **Full** (+~10 GB): home improvement and repair, motor vehicle repair and engineering Q&A; **English Wikibooks** (how-to books and the Cookbook, no pictures); the old **Project Gutenberg books on farming** (crops, livestock, beekeeping, forestry).
  - **Optional** (tick by hand, 12 GB): the old Gutenberg books on **trades**: building, machines, metalwork, crafts, cooking and preserving.
  - The complete Gutenberg collection already contains both subject sets, so a kit with it never downloads them again.
  - Left out on purpose: outdated medicine books, medical Q&A, and sites without a clear licence.
- THIRD-PARTY-NOTICES.md, README and LEIA-ME list them.
## 1.29.1 (2026-11-08)

- The user's own data (`my-data\`: checklists, supplies, shared map pins; `favorites.vault`) can never be committed to the repository, even if the project folder is used as a kit.

## 1.29.0 (2026-11-08)

- **Shared map pins**: tap a spot on the map, then **📍 Pin it for everyone**, and choose water, shelter, meeting point, danger, medical help, food, power or other, with a name and a note. Everyone connected to the kit, on the computer and on phones, sees the pins (refreshed every 15 seconds); tap a pin for its details or to remove it.
  - A small new server, setup/share-server.ps1 (port 8094), keeps them on the kit in my-data\pins.json. It listens on the network so phones reach it, answers only the kit's own pages, checks every pin (position, type, lengths; at most 500), and stops with the kit. The secure address passes /share to it. Windows may ask once to allow "Windows PowerShell" through the firewall.
  - Started by START-WINDOWS.bat; closed by the shutdown button, the start window and the next start. On Mac and Linux kits, or a page opened as a file, pins stay on that device.
## 1.28.0 (2026-11-08)

- **✅ Checklists** (new page): go-bag (per person, 3 days), supplies at home (2 weeks), documents, and before you evacuate. Tick what is ready, add your own items, untick a list, print. Based on Ready.gov (FEMA), Red Cross and Defesa Civil lists.
- **📦 Supplies** (new page): your stored water, food, medicines, batteries and more, with quantity, place and expiry date. Expired items turn red and those expiring within 30 days orange; the **home page warns** when something expires soon. Tips on rotating stock, medicines and batteries. Prints as a list.
- Checklists and supplies are saved on the device and, on the computer running the kit, also on the stick (my-data\), so they survive a cleared browser and travel with copies of the kit (new /data endpoint in the kit helper, which keeps the page's data exactly as sent).
- **🔋 Power calculator** on the Tools page: charges from a power bank, what a solar panel gives on a sunny day, how long a laptop runs the kit; tips to make power last; generator and carbon-monoxide safety (CDC / Red Cross).
- **🫂 Psychological first aid** (new page, English and Portuguese): look, listen, link; what to say and not say; calming techniques; children; normal reactions; looking after yourself; help lines (CVV 188, 988). Based on the WHO "Psychological First Aid" guide. In the kit-wide search.
- **🗣️ Phrasebook** (new page): 44 picture cards in English, Portuguese and Spanish (urgent, health with a 0–10 pain scale, needs, people, answers with numbers). Tap one to show it full screen; 🔊 has the device say it.
- Help page and home page tiles for all of them.
## 1.27.2 (2026-11-08)

- Help page: the print pack line mentions the Morse code chart, and the Morse line mentions both translators (text to dots and dashes, and back).

## 1.27.1 (2026-11-08)

- **Text to Morse translator** in the Tools page's Morse code section: type a message and see it as dots and dashes (letters separated by spaces, words by /). **Copy** puts it on the clipboard as plain . and - so it pastes anywhere; the buttons flash or beep it. Accents are dropped (Ação becomes ACAO) and characters with no Morse code are listed as left out.
## 1.27.0 (2026-11-08)

- **Morse code guide** on the Tools page (English and Portuguese):
  - the full chart: letters, numbers and common punctuation;
  - timing (dot 1, dash 3, gaps 1 / 3 / 7) and sending slowly and evenly;
  - how to send with a torch or phone light, whistle or horn, a mirror in the sun, a radio, and **when trapped** (tap a pipe or wall in groups of three, then listen; whistle before shouting);
  - signals to know: SOS, K, R, AR, SK, ? and the error signal;
  - how to read incoming Morse, a **translator** from dots and dashes to text, and **ear practice** (a random letter, then the answer);
  - learning tips.
- **SOS is now sent as one run** (···–––···, no gaps between the letters), as the distress signal should be, by the flash and beep buttons.
- The **print pack** has a one-page **Morse code chart** with the key signals, ticked by default. The Help page mentions the guide.
## 1.26.1 (2026-11-08)

- **Pluggable transports explained** on the Private browsing page (English and Portuguese): what obfs4, WebTunnel, Snowflake and meek each disguise Tor as, which to try first, how to get a private obfs4 bridge (@GetBridgesBot, frontdesk@torproject.org) in the hardest places, and that they are already built into Tor Browser. Checked against the Tor Browser manual. The Help page mentions them.
## 1.26.0 (2026-11-08)

- **Private browsing page** (new tile 🕶️, English and Portuguese): how to use **Tor Browser** and **Proton VPN Free** when some internet is left, checked against the Tor Project's and Proton's own pages:
  - which one to use, and what they do not protect (nothing makes you untraceable);
  - Tor Browser on a computer (download, install to a USB stick, connect, security levels, New Identity);
  - when Tor is blocked: built-in bridges (obfs4, webtunnel, snowflake, meek) and how to ask for one;
  - Tor on Android, and Onion Browser on iPhone;
  - Proton VPN Free step by step (account, app, Quick Connect, Kill Switch, Stealth protocol), its limits, and why to avoid unknown free VPNs;
  - safe habits.
- **Private favorites** (new tile 🔐): addresses to keep secret, such as sites to open in Tor Browser, **encrypted with your password** in the browser (AES-256, PBKDF2) before they are saved. On the computer running the kit, the encrypted copy is also kept on the stick (avorites.vault, outside the pages phones can reach), so it travels with the kit. **Copy** puts an address on the clipboard to paste into Tor Browser (which cannot open the kit's pages); it locks itself after 5 minutes without use. A forgotten password cannot be recovered.
- The Help page and the kit-wide search include both.
## 1.25.0 (2026-11-08)

- **A clear shutdown bar on the home page**, on the computer running the kit: a red **⏻ Shut down the kit** button with the reminder that closing the browser does NOT stop the kit (the AI, library and maps keep running and using the battery). The start window says the same.
- **Help page brought up to date** (English and Portuguese): My kit and Check the kit, the CPR metronome, Low power, Meshtastic, how to shut down (button, key, closing the window), the home page's update check and updates from GitHub, the help shown when the kit isn't running, and new entries in Problems ("Library: offline" right after starting, "Could not reach the kit helper", servers still running after closing the browser).
## 1.24.1 (2026-11-08)

- **"Could not reach the kit helper" after updating a running kit.** A kit updated while it runs keeps its old start window and helper until its next start, so the new **Shut down the kit** button could not work yet. The button now says exactly that (shut down with a key in the black window, then start again), and the builder says so at the end of an update when the kit is running.
## 1.24.0 (2026-11-08)

- **Closing the start window with its X now shuts the kit down too** (Windows). Before, only a key press in it did: closing it with X left the AI, library, map, voice and secure servers running with no window to stop them. A small hidden watcher (setup/watch-kit.ps1) now closes them as soon as the start window closes, however it closes.
- **⏻ Shut down the kit** button on the home page, on the computer running the kit: it asks first, then closes every server, the helper and the start window.
- Closing the browser still leaves the kit running, on purpose: phones on the same Wi-Fi may be using it, and the browser can be reopened.
## 1.23.1 (2026-11-08)

- **"Library: offline" right after starting, although it works.** The library server starts with the AI but takes a while to open big books from a USB stick, and the home page checked only once, for 2.5 seconds. It now waits up to 5 seconds, then keeps checking every 5 seconds and shows the library as running (and its tile as available) as soon as it answers.
## 1.23.0 (2026-11-08)

- **Meshtastic (LoRa texting) on the Radio page**, in English and Portuguese: text messages and GPS positions with no phone network, no internet and no licence, passed from device to device. It covers:
  - what it is good for, range and battery;
  - which frequency version to buy (915 MHz in the Americas, 868 MHz in Europe) and easy ready-made devices;
  - setup step by step: firmware (flasher.meshtastic.org), the app, Bluetooth PIN, the **region** (US, **BR_902** for Brazil, EU_868, ANZ; required before it transmits), names, a **private family channel** with a random key shared by QR code, position sharing, and testing;
  - use in an emergency, and links to the library's Meshtastic, LoRa and MeshCore articles.

  Checked against Meshtastic's official documentation.
- **Meshtastic for Android** joins the Android apps extra (pps/android/Meshtastic.apk, the F-Droid build that needs no Google services). Kits that already have the apps get it with **Check for updates**.
## 1.22.0 (2026-11-08)

- **Check for updates on the home page.** A new **🔄 Check for updates** button next to the status pills compares the kit with the latest release on GitHub (needs internet):
  - up to date: it says so, with the version;
  - newer version out: on the computer running the kit, **Update now** opens the builder's "Check for updates" there; on a phone, it says how to update from the computer;
  - no internet: it says updates need a connection, and that the kit works fine without them.
- **When the AI is not running, the home page says how to start it.** Browsers do not let a page start programs, so when the home page is opened as a file (the kit not started), it shows:
  - the kit's folder, with a button to copy its path;
  - which start file to double-click (Windows, Mac, Linux), and what to do if it says "No AI found";
  - it keeps checking, and switches to the full kit by itself as soon as the AI answers.
## 1.21.1 (2026-11-08)

- **Downloads from GitHub no longer stop the build when GitHub's download link fails.** GitHub's normal link for some big files (for example the PocketPal AI app) can answer "504 Gateway Time-out" for a while, which ended the build with "curl error 22". The builder now fetches the same file through GitHub's API route instead, with a fresh address on every retry.
## 1.21.0 (2026-11-08)

- **Updates straight from GitHub when there is internet.** **Check for updates** and **Verify / repair** now also look at the latest release on GitHub (github.com/survivalstation-kit/survival-station):
  - if it is newer than the builder's own folder, they download it (a few MB) and update the kit's pages, start files and tools from it;
  - so a kit can update itself, even when the builder is opened from the kit (the **My kit** page or the kit's own MAKE-USB.bat);
  - with no internet, they use the builder's folder as before.
- **Never older over newer:** a builder from an older copy no longer replaces newer pages on a kit; it keeps them and says so.
- The **My kit** page says when a newer version is out on GitHub, when the device has internet.

  Kits from before 1.21.0 need one update the old way (MAKE-USB.bat from a newer copy, then Check for updates); after that they update from GitHub on their own.
## 1.20.0 (2026-11-08)

- **Weather page** (new tile ⛅ on the home page), for when there is still some connection, even only a phone's mobile data:
  - 7-day forecast, the next hours and current conditions from Open-Meteo (free, no account), for a place you search, the last point you marked on the map, or your GPS;
  - official alerts from the US National Weather Service for places in the USA, and links to the official services elsewhere;
  - simple warning flags (heavy rain, strong gusts, thunderstorms, heat, hard frost, freezing rain, heavy snow), clearly marked as unofficial;
  - the **last forecast stays saved on the device**, so it still shows (with its date) when the connection goes;
  - "weather without internet" tips: signs in the sky and wind, and listening for weather radio;
  - English and Portuguese, metric or US units.

  Privacy: the place you ask about is sent to open-meteo.com (and weather.gov in the USA). Nothing is sent until you ask for a forecast.
## 1.19.1 (2026-11-08)

- **"Use at your own risk" everywhere.** One clear statement, in English and Portuguese:
  - Survival Station brings together free material published by others, with short summaries of public emergency guidance, none of it reviewed by professionals for this kit;
  - it is a reference tool, not a substitute for emergency services, and the AI can be wrong;
  - it is provided "as is", and its authors and contributors accept no responsibility or liability for errors, misinformation, misuse or its answers.

  It now appears in:
  - **every kit page**, at the bottom (short form under the chat's question box, and in the map's credits);
  - printed family plans and the print pack;
  - the start window;
  - the README, LEIA-ME, Help, `THIRD-PARTY-NOTICES.md`, the flyers, the post texts and the video script.

## 1.19.0 (2026-11-08)

- **Safer, more accurate AI answers.** With the complete Wikipedia on the kit, the library lookup found unrelated articles (a song for "bleeding", oil refining for "bleach"), and one answer gave about 12 times the safe bleach dose. Now:
  - **The kit's own emergency card comes first.** The card that matches the question is source [1], even with the library lookup off. The AI is told to follow its steps and copy its numbers exactly. Cards have extra words for their subject (e.g. "massagem cardíaca" finds the RCP card).
  - **The focused books are searched first**: medical encyclopedias, the water, medicine and post-disaster guides, Appropedia. The whole library is searched only in the reader's own language and only when no card matched. With a card, articles must name its subject in their title.
  - **Relevance:** words must match at the start of a word ("arm" no longer matches "warm"), and articles need most of the question's words. Common verbs ("make", "need", "fazer") don't count as subjects.
  - **No guessed safety numbers:** doses, amounts of bleach or chemicals, times and temperatures only when they appear in the sources; otherwise the AI points to the Emergency cards or Tools page.
- **`tests/chat-safety.js`**: 15 emergency questions (11 English, 4 Portuguese) through the real chat page, checking the right card, no off-topic sources, and key facts in the answer. It passed 15 of 15 with Qwen3-4B and the full library.
- **README and LEIA-ME** open with screenshots, the official 72-hour preparedness advice, and a 5-step Quick Start.
- **`promo/` folder for spreading the word:**
  - printable flyers in English and Portuguese, HTML and PDF, with a QR code;
  - ready-to-post texts for Hacker News, Reddit, Brazilian communities and short social posts;
  - a video script.

## 1.18.1 (2026-11-08)

- Published at https://github.com/survivalstation-kit/survival-station.
- `LICENSE` is now the standard MIT text alone, so GitHub recognises it as MIT. The note that downloaded parts keep their own licences stays in the README and `THIRD-PARTY-NOTICES.md`.

## 1.18.0 (2026-11-07)

Ready to publish as open source.

- **MIT licence** (`LICENSE`) for Survival Station's own code and pages.
- **`THIRD-PARTY-NOTICES.md`**: every program, AI model, book collection, map and data source the builder downloads, with its licence and source:
  - the Llama 3.2 and Gemma 3 terms and use policies, with "Built with Llama";
  - kiwix-serve's GPL-3.0 source offer;
  - iFixit's non-commercial licence;
  - OpenStreetMap and GeoNames credits.

  It and the licence go onto every kit, so a shared kit carries them.
- **Survival-Data is now optional and not ticked by default.** Its repository states no licence and includes commercial books still under copyright. The builder downloads it only when ticked, its name in the list says why, and kits that already have it keep it. The home page hides its tile when it isn't on the kit.
- **Safety disclaimer** in the README, LEIA-ME and a new "About this kit" section of the Help page: a reference tool, not a substitute for emergency services, doctors or official instructions; radio only as the law allows; provided "as is".

## 1.17.0 (2026-11-02)

- **Copy kit estimates how long the copy will take**, from the real speed of both drives.
  - It reads the kit's biggest file for 2 seconds (past Windows' cache, so it's the drive's real speed) and writes a test file to the destination for 3 seconds (then deletes it).
  - The slower drive sets the pace; copying within one drive counts at half speed; every file adds a little time, since sticks are slow with many small files.
  - It shows in the window, for example "Time: about 49 min (reads 68 MB/s, writes 1,511 MB/s; the kit's drive is the slower one)", in the confirmation, and on the command line. Each pair of drives is measured once.
- **While copying**, the copy window shows the percentage, size copied, current speed and time left, also in its title bar, and how long it took at the end. robocopy's file list goes to the log.
- Tested: copying the 186.9 GB D: kit to this computer is estimated at about 49 minutes. An 8 GB test copy showed live progress and finished correctly.

## 1.16.0 (2026-11-02)

- **Starting the kit closes one that is still running.** An earlier start that was never shut down, or one started from another copy of the kit, kept its ports and ran a second AI. Now `START-WINDOWS.bat` (through `setup/stop-old-kit.ps1`) and `START-MAC.command` / `START-LINUX.sh` first close the old one, and say so in the start window:
  - its AI, library, map, speech and secure (Caddy) servers;
  - the My kit helper;
  - its old start window.
- Only the kit's own programs are closed. The map tool is closed only while serving maps, so a build that is cutting a map keeps running; Caddy only with the kit's settings.
- Tested: a second start closed all of the first start's programs and its window, then came up by itself.

## 1.15.0 (2026-11-02)

- **The 🎤 works on phones too: the kit has a secure address**, `https://<address>:8443/`.
  - Browsers only allow the microphone on https (or on the computer itself), so the Voice extra now also brings **Caddy**, a small web server that serves the whole kit over https. Its own certificate authority stays on the kit (`tools/caddy-data`).
  - Behind it, Caddy passes `/library` to the library, `/tiles` to the big-map server, `/voice` to speech to text (which still listens on the computer only), and the rest to the AI server.
  - Phones show a one-time "not private" warning for the kit's own certificate: choose Advanced / Show details and continue.
  - The start window lists the secure addresses. The home page shows the address next to the QR code, and tapping 🎤 on the plain address offers a link to it.
  - Plain `http://…:8080` works as before.
- **The library now answers under `/library/`** (`http://<address>:8090/library/`), so it can sit behind the secure address. The pages and start files were changed together; restart the kit after updating.
- `setup/network.ps1` writes the kit's addresses and Caddy's settings when the kit starts. Phones connecting by IP send no server name, so Caddy is told which certificate to show.
- Tested through the secure address: pages, a streamed AI answer, library search and articles, a big-map tile, the self-test, and 🎤 with speech to text ("How do I purify water with bleach after a flood?", transcribed exactly).
- The Voice extra grows to about 400 MB (Caddy is ~50 MB per system). Kits that already have Voice get Caddy through **Verify / repair**.

## 1.14.0 (2026-11-02)

- **Family emergency plan** (home tile 👪, English and Português):
  - each person's blood type, allergies, medicines and health needs;
  - emergency contacts (including one far away), where to meet (near home, in the neighbourhood, out of town);
  - doctor and insurance, documents, utility shut-offs, pets and notes.

  It's kept in the browser as you type. It can be printed as clean tables or downloaded as a file. On the computer running the kit it can be **saved on the stick, locked**, and loaded back with the password.
- **Private documents**:
  - IDs, insurance papers and other personal files go in the kit's new `private/` folder, outside the web pages, so phones on the hotspot can never reach them.
  - **PRIVATE-DOCS.bat** (and the My kit page) locks them with a password (AES-256, in OpenSSL's format): Mac and Linux open them with `bash launch/private-docs.sh` or plain `openssl`. A wrong password is refused.
  - Opening decrypts copies into a folder on the computer, never back onto the stick. Closing deletes them, and offers to lock changed or new files back first.
  - Tested: Windows ⇄ OpenSSL in both directions, an 8 MB scan, accented passwords.
- **Print pack** (home tile 🖨️): the emergency cards, the radio essentials and frequencies, the family plan and how to start the kit, each on its own page. Untick what you don't need; "Save as PDF" makes a file for phones.
- **Fixed in the kit helper:**
  - The first visit to My kit took about 10 seconds: the helper loaded Windows' storage module on its first call.
  - Pages couldn't post JSON to the helper: it now answers the browser's CORS check, still only for the kit's own pages.
  - A PowerShell 5.1 trap is avoided: listing the files of a folder that doesn't exist yet searched the whole folder above it.

## 1.13.0 (2026-11-02)

- **Low power mode.**
  - **⚡ Low power** switch on the home page: dark pages (less power on phone screens), the chat answers without the library lookup (it can still be ticked), and answers are capped at 400 words.
  - **On battery, the start files pick the smallest model** (Llama-3.2-1B) as the default and say so. Windows checks the battery with Win32_Battery, Mac with `pmset`, Linux with `/sys/class/power_supply`.
  - The home page shows the **battery level and time left** where the browser tells it (the computer itself), and suggests low power once when running on battery.

## 1.12.0 (2026-11-02)

- **Check the kit** on the My kit page: **▶ Test everything** starts each part and checks that it really answers, then shows ✓ works, ✗ problem (with what to do) or – not on this kit. It checks:
  - the pages' version;
  - the AI, with its speed;
  - photos;
  - the library and an article from it;
  - every map, including the over-2 GB ones through the map server;
  - place search, Survival-Data and its PDF search, and the emergency cards;
  - read-aloud voices, the voice server, and the addresses phones can use.

  It works on phones too. Worth doing after building or copying a kit, and before storing it. Tested: every part passed with everything running, and with the library or map server stopped it reported exactly those.

## 1.11.0 (2026-11-02)

- **QR code for phones** on the home page ("Use it on a phone"): point a phone camera at it to open the kit, with nothing to type.
  - On the computer it shows the computer's network address. The start files write the addresses to `portal/kit-address.json` each time the kit starts, the one with a gateway (a phone hotspot) first; the others are listed as fallbacks.
  - On a connected phone it shows the address that phone uses, so it can be passed on.
  - Tested: the code reads back as the kit's address (`http://192.168.x.x:8080/`).
- The QR library (qrcode-generator 1.4.4, 57 KB) is downloaded with the map viewer. **Verify / repair** adds it to existing kits.

## 1.10.0 (2026-11-02)

- **CPR rhythm** at the top of the Tools page:
  - a click and a pulsing circle at 110 compressions a minute (guidelines: 100–120);
  - **30:2** mode counts to 30, then says "Give 2 breaths now" for 6 seconds, then starts again;
  - **hands-only** mode never stops;
  - a reminder every 2 minutes to swap rescuers;
  - the steps (where to push, how deep, when to stop), and the screen kept awake where allowed.

  Timed against the audio clock: measured at 110.1 a minute, with a 6.0-second breath pause.

## 1.9.0 (2026-11-02)

- **The AI can look at photos.**
  - New model **Gemma 3 4B** (Standard and Full tiers, or tick it in the builder window): 2.3 GB plus an 812 MB vision part in `models/mmproj/`. The start menu marks it `[photos / fotos]` and loads the vision part with it.
  - With it running, a **📷** button appears in the chat: take or pick a photo, optionally add a question, and send. The photo is shrunk to about 900 px first, which is much faster. A small copy stays in the chat history.
  - Every photo answer carries a warning: never eat a wild plant or mushroom because of a photo, and treat every snake bite as an emergency. The AI is told to say how sure it is.
  - Tested: a death cap photo → "Do not eat these mushrooms… can cause severe illness or death" (though it named the wrong species). Answers took 19–24 seconds on this computer.
- **Voice.**
  - **🔊 Listen** under each answer, and a *Read answers aloud* option, use the device's own voices on every computer and phone.
  - **🎤 Speak** on the computer running the kit records the question, turns it into text with whisper.cpp (the new **Voice** extra: ~200 MB, Windows and Linux) and sends it. Tested: "How do I purify water with bleach after a flood?" was transcribed exactly in about 4 seconds.
  - On phones, 🎤 explains how to dictate with the keyboard instead, because browsers only allow the microphone on the computer itself.
- The AI is told to put the "get emergency help" line first only when the question describes life-threatening signs. Gemma had been adding it to every answer.
- Builder catalogue version 4: the builder window refreshes it to show the new model and the Voice extra.

## 1.8.0 (2026-11-02)

- **New Tools page** (home tile 🛠️, English and Português). Everything works without the AI or internet:
  - **Make water safe with bleach:** drops for any amount of water, for Brazilian água sanitária 2–2.5% (Ministry of Health: 2 drops per litre) or US bleach 6% / 8.25% (EPA table), doubled for cloudy water, with the 30-minute wait and smell check.
  - **Water and food for your group:** litres and kcal for adults and children over N days, with rice, beans or cans as examples.
  - **Signal for help:**
    - full-screen SOS flashing (screen kept awake where allowed);
    - a loud whistle tone: three blasts, the international distress signal;
    - SOS beeps;
    - any short message in Morse code, by light or sound.
  - **Sun, directions and daylight:** sunrise, sunset, solar noon, daylight left and where the sun is now, for the last point tapped or found on the Map, typed coordinates, or GPS on the computer itself. It also has finding north with a shadow stick or the noon sun, and a compass on devices and connections that allow it.
- Tested against published times: Chicago 21 June 05:16 / 20:30, Toronto 21 December 07:48 / 16:44, Rio 2 November 05:07 / 18:07, and midnight sun in Tromsø.

## 1.7.0 (2026-11-02)

- **Place search on the map.** A box at the top left finds:
  - towns of 500+ people worldwide, so the world map can be searched too;
  - in countries with a street map on the kit: every town and neighbourhood, hospitals and clinics, airports, mountains, lakes and parks.

  Results show the type, state, country and distance from where the map is looking, biggest and closest first. Picking one flies there, drops the marker and shows the coordinates to read out. Accents don't matter ("sao paulo"), and some big cities are found by their other names ("Lisbon").
- **"hospital" or "airport"** (or "aeroporto") alone lists the nearest ones to where the map is looking.
- The builder makes the list from GeoNames (free, CC BY 4.0) after the maps: 14 MB for the world list plus the country files, kept in `%TEMP%\survival-station-tools`. It goes in `portal/maps/places/`: about 30 MB for Brazil, 67 MB for USA + southern Canada. Adding a map rebuilds it, and **Verify / repair** adds it to existing kits.
- The last point tapped or found on the map is remembered, for the coming Tools page.

## 1.6.0 (2026-11-02)

- **Exact phrases in the search: put them in quotes**, for example `"praia de ipanema"` or `"rolling boil" minutes`. A result must have those words in that order, next to each other, as whole words. Accents, capitals, line breaks and punctuation between the words are ignored. Words outside the quotes still help ranking. The whole phrase is highlighted.
  - It applies everywhere: kit pages, Survival-Data titles, inside the PDFs (pages are checked for the actual phrase), your documents and the library.
  - The library server ignores quotes, so for a phrase the page takes its top 30 results and keeps the articles that really contain it. It reads the whole article when the excerpt doesn't show the phrase.
  - Tested: `"praia de ipanema"` finds 10 articles that all contain it; `"ipanema de praia"` finds nothing.
- A "Searching…" line shows until all results are in.
- Short words like "de" are highlighted only inside their phrase, not inside every longer word.

## 1.5.0 (2026-11-02)

- **Search looks inside the Survival-Data PDFs.** Results show the guide, the page, a short excerpt with the words highlighted, and links that open the PDF at that page. Other pages with the same words are listed too.
  - Tested on the current Survival-Data: "tourniquet" finds Emergency War Surgery and the First Aid manuals, and "snake bite" finds the snakebite section of the US Army survival manual.
  - A table of contents gives way to the page with the actual text. Guides that Survival-Data keeps in two sections show once.
  - 19 of its 243 PDFs are scans (pictures of pages) with no text, so they can only be found by title.
- **How:** the builder reads the text of every PDF once, with Poppler's pdftotext, and writes a word index to `portal/survival-data/search-index/` (about 100 MB, 66 seconds in testing). The search page loads only the parts of the index for the words searched, and fetches only the matching page's text. Poppler (42 MB) is downloaded on first use and kept in `%TEMP%\survival-station-tools`, so it isn't put on the drive.
  - New builds create the index after Survival-Data.
  - **Verify / repair** creates it on kits that already have Survival-Data.
  - When Survival-Data is updated, the index is rebuilt.

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
