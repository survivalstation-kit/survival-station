# Third-party notices

Survival Station's own code and pages are under the MIT licence (see `LICENSE`). Everything below is made by
others. The builder **downloads it from its original source** onto your kit; none of it is included in this
repository. Each part keeps its own licence. **When you share a kit (COPY-KIT), you are passing these parts on,
so these terms travel with it** — this file is copied onto every kit for that reason.

Licences can change: check the linked pages for the current terms.

**Use at your own risk.** Survival Station brings together free material published by others, listed below,
with short summaries of public emergency guidance written for the kit (the emergency cards, radio page and
tools). None of it has been reviewed by medical, legal or emergency professionals for this kit. All of it,
Survival Station's own code and pages and everything it downloads, is provided "as is", without warranty of any
kind. The authors and contributors of Survival Station accept no responsibility or liability for errors,
misinformation, misuse, the answers it gives, or the accuracy, completeness or legality of any third-party
material, which is the responsibility of its publishers and of whoever builds or shares a kit.

## Programs on the kit

| Part | Licence | Source |
|---|---|---|
| llama.cpp (`llama-server`, the AI engine) | MIT | https://github.com/ggml-org/llama.cpp |
| whisper.cpp (`whisper-server`, speech to text; Voice extra) | MIT | https://github.com/ggml-org/whisper.cpp |
| kiwix-serve (library server) | **GPL-3.0** | https://github.com/kiwix/kiwix-tools |
| Caddy (secure https address; Voice extra) | Apache-2.0 | https://github.com/caddyserver/caddy |
| go-pmtiles (`pmtiles`, map server for big maps) | BSD-3-Clause | https://github.com/protomaps/go-pmtiles |
| MapLibre GL JS (map viewer) | BSD-3-Clause | https://github.com/maplibre/maplibre-gl-js |
| PMTiles JS | BSD-3-Clause | https://github.com/protomaps/PMTiles |
| Protomaps basemaps (map style) | BSD-3-Clause (code) | https://github.com/protomaps/basemaps |
| Protomaps basemaps-assets (fonts and icons) | fonts: SIL Open Font License; see the repository | https://github.com/protomaps/basemaps-assets |
| qrcode-generator (QR code on the home page) | MIT | https://github.com/kazuhikoarase/qrcode-generator |

**GPL-3.0 (kiwix-serve):** the program is passed on unchanged. Its complete source code is available at the
address above, for the version on the kit (see the Kiwix releases page); this notice is the offer of source.

**Used only while building, not put on the kit:** Poppler's `pdftotext` (GPL-2.0-or-later; Windows build:
https://github.com/oschwartz10612/poppler-windows, MIT packaging) to make the search index of the PDFs.

## AI models

| Model | Licence | Notes |
|---|---|---|
| Qwen3-4B, Qwen3-8B (Alibaba) | Apache-2.0 | https://huggingface.co/Qwen |
| **Llama 3.2 1B** (Meta) | **Llama 3.2 Community License** | Built with Llama. Licence: https://www.llama.com/llama3_2/license/ — Acceptable Use Policy: https://www.llama.com/llama3_2/use-policy/ . Anyone you share a kit with is bound by them too. |
| **Gemma 3 4B** (Google) | **Gemma Terms of Use** | https://ai.google.dev/gemma/terms — Prohibited Use Policy: https://ai.google.dev/gemma/prohibited_use_policy . These terms pass on with every copy. |
| Whisper "small" (OpenAI), speech to text | MIT | https://github.com/openai/whisper |

The model files are the GGUF conversions published on Hugging Face (bartowski, ggml-org, ggerganov).

## Library, maps and data

| Content | Licence |
|---|---|
| Wikipedia, Wikivoyage, Wikibooks, Wiktionary, Wikiversity (via Kiwix) | CC BY-SA (text); images under their own licences. Credits are inside each book. |
| Appropedia, MDWiki, Energypedia | CC BY-SA |
| **iFixit** guides | **CC BY-NC-SA: non-commercial** — don't sell kits that contain them. |
| Project Gutenberg | Public domain in the USA; the "Project Gutenberg" name is a trademark with its own terms. Check your country's copyright rules. |
| "zimgit" collections (medicine, water, food, post-disaster, knots) | Collections of documents by many publishers; each document keeps its publisher's terms. |
| Maps: OpenStreetMap data, cut from Protomaps builds | ODbL — © OpenStreetMap contributors (shown on the map). https://www.openstreetmap.org/copyright |
| Place names for the map search: GeoNames | CC BY 4.0 — https://www.geonames.org (credited on the map). |

## Optional: Survival-Data (not ticked by default)

https://github.com/PR0M3TH3AN/Survival-Data states **no licence**, and its collection includes commercial books
that are still under copyright as well as public-domain government manuals. Survival Station only downloads it
when you tick it. **Whether you may keep or share it depends on your country's law and the rights of each
book: that decision and responsibility are yours.**

## Android apps (optional extra, to install on phones)

| App | Licence | Source |
|---|---|---|
| Kiwix for Android | GPL-3.0 | https://github.com/kiwix/kiwix-android |
| PocketPal AI | MIT | https://github.com/a-ghorbani/pocketpal-ai |
| Organic Maps | Apache-2.0 | https://github.com/organicmaps/organicmaps |
