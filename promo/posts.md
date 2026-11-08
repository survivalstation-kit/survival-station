# Ready-to-post texts

Drafts for announcing Survival Station. Before posting anywhere, **read that community's rules**. Many
don't allow self-promotion from new accounts, want a specific flair or a weekly thread, or ban links in titles.
Post one community at a time, answer questions, and don't paste the same text everywhere: tailored posts get
read, while copies get flagged as spam.

Link: https://github.com/survivalstation-kit/survival-station

Tone: calm and factual. Mention the official 72-hour advice; avoid "lockdown", "collapse" or doomsday wording.

---

## Hacker News: "Show HN"

**Title:** Show HN: Survival Station – an offline AI, library and maps on a USB stick, no install

**Text:**

Survival Station builds a USB stick (or a folder) that runs an emergency kit on any laptop with no internet and
nothing to install: llama.cpp with a small local model, Kiwix (Wikipedia, medical encyclopedias, water and
first-aid guides), Protomaps vector maps with offline place search, and emergency cards. Phones on the laptop's
hotspot use it all in the browser.

Some parts I found interesting to build:

- The AI looks the question up in the offline library before answering, and cites the articles. With the
  complete Wikipedia it matched almost anything, so it now searches the focused medical and survival books
  first and gives the kit's own checked emergency card to the model as source [1]. Safety-critical numbers
  (bleach dose, CPR rate) must come from those sources; a small test set checks this before each release.
- Windows' llama-server can't serve files over 2 GB, so big map files go through `pmtiles serve`.
- Phones only get the microphone on https, so the kit runs Caddy with its own local CA for speech to text
  (whisper.cpp).
- Search inside 243 PDFs with a word index sharded by first two letters, fetched page by page with HTTP Range.

The builder is PowerShell (Windows); a finished kit runs on Windows, macOS and Linux. English and Portuguese.
MIT licensed. Feedback welcome, especially from people who work in emergency medicine or disaster response.

---

## Reddit r/preppers or r/preparedness

**Title:** A free, open-source "information kit" on a USB stick: offline first aid, maps, radio guide and AI, no internet needed

**Text:**

Many governments now advise households to be ready for at least 72 hours on their own. Food, water and a torch
are on every list. Information usually isn't, and it's the first thing to go when the internet and phone
networks are down.

I built Survival Station to fill that gap. You build it once on a Windows computer while you have internet; then
it runs from the stick on any laptop:

- First aid and survival guides (medical encyclopedias, water treatment, post-disaster guides, Wikipedia)
- Offline maps with place search, including "nearest hospital"
- Emergency cards: CPR, bleeding, burns, safe water, signals. Printable
- A radio page with emergency frequencies and Baofeng/TIDRADIO setup, plus a CHIRP channel file
- Tools: CPR rhythm, bleach drops for water, SOS flash and whistle, sunrise and sunset
- A local AI assistant that cites the library (optional; it can be wrong, and the kit says so)
- Phones on the laptop's hotspot can use all of it

It's free and open source. Copying a finished kit to someone else's stick needs no internet, so one person can
equip a whole street. Happy to answer questions, and I'd like to hear what's missing.

https://github.com/survivalstation-kit/survival-station

---

## Reddit r/LocalLLaMA

**Title:** Offline RAG on a USB stick: llama.cpp + Kiwix (full Wikipedia + medical books) for emergencies, no install

**Text:**

Survival Station runs llama-server (Qwen3-4B by default, Llama-3.2-1B for old laptops, Gemma 3 4B with mmproj
for photos) against a local Kiwix library, from a USB stick, on Windows/macOS/Linux with no install.

Lessons on the retrieval side:
- Full-text search over the complete English Wikipedia (119 GB) returns noise for short emergency questions:
  "bleeding" found a song, "bleach" found oil refining. Searching the focused books first (MDWiki, WikiMed,
  water and medicine collections) and requiring most of the question's words in a paragraph fixed most of it.
- For safety-critical numbers, the kit's own checked emergency card goes in as source [1], and the system prompt
  forbids numbers that aren't in the sources. A 15-question test checks doses and key facts before each release.
- whisper.cpp for voice, served through Caddy so phones get the microphone over https.

MIT licensed: https://github.com/survivalstation-kit/survival-station

---

## Reddit r/selfhosted or r/opensource

**Title:** Survival Station: a self-contained offline knowledge kit (AI, Wikipedia, maps) that runs from a USB stick

**Text:**

No Docker, no install, no internet after the build. One start file brings up llama-server, kiwix-serve, a
PMTiles map server, optional whisper.cpp and Caddy (https for phones), and a small web portal with search across
everything, including inside PDFs. Phones join over the laptop's hotspot. A builder window picks what goes on the
stick, shows sizes, tests the drive's speed, verifies and repairs a kit, and copies kits offline.

MIT licensed, English and Portuguese: https://github.com/survivalstation-kit/survival-station

---

## Reddit r/amateurradio

**Title:** Free offline emergency kit with a radio page: frequencies, Baofeng UV-5R / TD-H3 setup and a CHIRP CSV

**Text:**

Survival Station is an open-source emergency kit that runs from a USB stick with no internet. Its radio page
covers: what to do first, a calling script, the 3-3-3 listening plan, 2 m / 70 cm calling frequencies,
FRS/GMRS, marine, weather and MURS, plus who may transmit where. It also has UV-5R keypad programming and TD-H3
PLUS notes, and a CHIRP channel file where everything outside the ham bands is receive-only.

Corrections from licensed operators are very welcome, especially for frequencies outside North America.

https://github.com/survivalstation-kit/survival-station

---

## Brasil (r/brasil, grupos de preparação, radioamadores)

**Título:** Kit de emergência gratuito num pendrive: primeiros socorros, mapas, rádio e IA, sem internet

**Texto:**

Vários governos recomendam que cada casa esteja pronta para pelo menos 72 horas por conta própria. Água, comida
e lanterna estão em todas as listas; informação confiável quando a internet e o celular caem, quase nunca.

O Survival Station é um kit gratuito e de código aberto que roda direto de um pendrive, em português:

- Guias de primeiros socorros e sobrevivência, Wikipédia em português e enciclopédias médicas, offline
- Mapas offline com busca, inclusive "hospital mais próximo"
- Cartões de emergência: RCP, sangramento, queimaduras, picada de cobra, enchente, deslizamento, com SAMU 192,
  Bombeiros 193 e Defesa Civil 199
- Página de rádio com frequências e configuração de Baofeng/TIDRADIO
- Ferramentas: ritmo da RCP, gotas de água sanitária para a água, SOS com luz e apito
- Assistente de IA local que cita as fontes (pode errar, e o kit avisa)
- Os celulares conectados ao roteador do notebook usam tudo pelo navegador

Monte uma vez num computador Windows com internet; depois funciona em qualquer notebook. Copiar o kit para o
pendrive de outra pessoa não precisa de internet.

https://github.com/survivalstation-kit/survival-station

---

## Short post (Mastodon, X, Facebook, WhatsApp)

**English:** Governments advise being ready for 72 hours on your own. Survival Station is a free, open-source
emergency kit on a USB stick: first aid, offline maps, radio guide and a local AI, with no internet needed.
Phones join over the laptop's hotspot. https://github.com/survivalstation-kit/survival-station

**Português:** Os governos recomendam estar pronto para 72 horas por conta própria. O Survival Station é um kit de
emergência gratuito num pendrive: primeiros socorros, mapas offline, guia de rádio e IA local, sem internet.
https://github.com/survivalstation-kit/survival-station

---

## Asking to be listed

**Kiwix community** (forum or GitHub discussions): a short note that the kit packages kiwix-serve with a curated
offline library for emergencies, with a link. Ask whether they keep a list of projects built on Kiwix.

**"Awesome" lists** (for example awesome-selfhosted, or offline and preparedness lists): open a pull request that
adds one line in the list's format, e.g.

`- [Survival Station](https://github.com/survivalstation-kit/survival-station) - Offline emergency kit on a USB stick: local AI with cited sources, Kiwix library, maps, emergency cards. ([Source Code](https://github.com/survivalstation-kit/survival-station)) MIT PowerShell/JavaScript`

Check each list's rules first: some require a project to be a few months old or to have a minimum number of stars.
