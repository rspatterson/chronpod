# ChronPod

**A free, open-source podcast player and legal-news reader for iPhone and iPad, adapted from [AntennaPod](https://github.com/AntennaPod/AntennaPod).**

ChronPod brings AntennaPod's approach to iOS: no account, no tracking, and your subscriptions stored on your device. It also has a built-in **ChronLaw** directory of legal-news topics.

## Features (version 0.2)

- **ChronLaw Breaking News on the Home screen.** The first time ChronPod opens, it subscribes to the ChronLaw *Breaking News* feeds.
- **ChronLaw Topics.** A checkbox list of more than 200 legal-news topics, from Administrative Law to Workers' Compensation, works like AntennaPod's OPML import screen. Tick the topics you want and tap **Done**.
  - ChronPod downloads the topic list from `https://chronlaw.com/rss/chronlaw.opml`. Replace that file on the website and every user gets the new list.
  - If the website has no list, ChronPod uses the copy built into the app (`ChronPod/Resources/chronlaw.opml`).
- **Headlines only, by design.** For news topics ChronPod shows the headline, publisher and date, and nothing more. Tapping a headline opens the story on the publisher's own website. ChronPod never copies or displays article text, the same approach the ChronLaw web pages have always taken.
- **Direct article links.** News stories open on the publisher's own website, not through Google's redirect links. This uses the same method as the ChronLaw tt-rss plugin.
- **Discover.** Popular podcasts appear on Home, as in AntennaPod. The Add Podcast screen shows Apple's **Top Podcasts** by category (News, Government, True Crime, Business, History and more) and by country.
- **Search several directories at once.** Searches Apple Podcasts and fyyd, plus Podcast Index if you enter your own free API key in Settings. Results are merged and duplicates removed, like AntennaPod's combined search.
- **Preview before subscribing.** Tap any search or chart result to see the show's description and latest episodes, then subscribe.
- **Episodes tab.** Every episode from every podcast in one list, filtered by Unplayed, In Progress, Downloaded or Favorites, with search and swipe actions (queue, mark played, favorite).
- **Auto-download and cleanup.** Turn on auto-download per podcast. Optionally delete downloads after playing.
- **Background refresh.** iOS refreshes your feeds in the background a few times a day.
- **Podcasts.**
  - Find shows through Apple's public podcast directory, or add any RSS/Atom feed by its address.
  - Stream or download episodes.
  - Background and lock-screen playback.
  - Playback speeds from 0.75× to 3×.
  - Adjustable skip intervals (5–60 seconds).
  - Sleep timer.
  - Remembers where you stopped in each episode.
- **Queue.** Line up episodes and reorder them; ChronPod plays the queue in order.
- **OPML import and export.** Bring your subscriptions over from AntennaPod (Settings → Import/Export → OPML export) or from any other podcast app.

## How the build works (no Mac needed)

Each time code is pushed to this repository, GitHub builds the app on a free Mac (see `.github/workflows/build.yml`). The build:

1. Runs the unit tests in `ChronPodCore` (feed parsing, OPML, dates, Google News links).
2. Generates the Xcode project from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Builds the app for the iPhone Simulator.
4. Builds an **unsigned `ChronPod-unsigned.ipa`** and attaches it to the run.

To get the `.ipa`, open the **Actions** tab, click the latest successful run, and download **ChronPod-unsigned-ipa** under *Artifacts*.

## Installing on an iPhone

Apple only lets an iPhone run apps that are signed. To install the unsigned `.ipa`, a sideloading tool signs it with your own Apple ID:

- **[Sideloadly](https://sideloadly.io/)** (Windows or Mac): connect the iPhone by USB, drag in the `.ipa`, and sign in with your Apple ID.
- **[AltStore](https://altstore.io/)** (Windows or Mac): installs AltStore on the phone, which can then install and refresh the `.ipa`.

With a free Apple ID, sideloaded apps must be refreshed every 7 days. A paid Apple Developer account ($99/year) extends that to one year and allows TestFlight distribution.

## Project layout

| Path | What it is |
|---|---|
| `ChronPodCore/` | Swift package: models, RSS/Atom parser (ported from AntennaPod's `parser/feed`), OPML, date parsing, Google News helpers, podcast search. Has unit tests and no UI code. |
| `ChronPod/` | The iOS app: SwiftUI screens, player (AVPlayer + lock-screen controls), downloads, subscription library. |
| `ChronPod/Resources/chronlaw.opml` | Built-in copy of the ChronLaw topic list. |
| `web/rss/chronlaw.opml` | The same list, ready to upload to chronlaw.com. |
| `tools/convert_opml.py` | Converts a tt-rss OPML export to current Google News feed addresses. |
| `project.yml` | XcodeGen description of the Xcode project. |

## Building on a Mac (optional)

```bash
brew install xcodegen
xcodegen generate
open ChronPod.xcodeproj
```

Choose your team under *Signing & Capabilities*, pick an iPhone or simulator, and press Run.

## Updating the ChronLaw topic list

1. In tt-rss, export the feeds to OPML.
2. Run `python3 tools/convert_opml.py tt-rss.opml chronlaw.opml` (optional, but it tidies the addresses).
3. Upload `chronlaw.opml` to the site so it is served at `https://chronlaw.com/rss/chronlaw.opml`. On Cloudflare Pages, put it in a folder named `rss` in the site you upload.

ChronPod checks for the list each time it starts.

## Roadmap

These AntennaPod features are next. Contributions are very welcome:

- Chapters (Podcasting 2.0 and ID3)
- Video playback
- Statistics
- gpodder.net / Nextcloud sync
- New-episode notifications
- More per-feed settings (playback speed, skip intro/outro, episode cleanup)
- Home-screen widgets and CarPlay

## License and credits

ChronPod is free software under the **GNU General Public License v3.0 or later** (see `LICENSE`). It adapts the design and logic of **AntennaPod**, © the AntennaPod contributors, also licensed under GPL-3.0. ChronPod is an independent project and is not affiliated with or endorsed by the AntennaPod team.

News headlines and articles belong to their publishers. Nothing in ChronPod is legal advice; anyone facing a current legal issue should consult a licensed attorney.
