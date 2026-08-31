# Playback Track Diff

Compares two versions of a show playback track. It reads the SMPTE LTC stripe off
whichever channel carries it, lines the programme audio up to the sample, and
reports every insert, cut, replacement and loop — and, above all, whether the
audio still lands on the timecode the cues are programmed to. It does the same
across two whole folders, pairing tracks on their cue number.

**It has no back end.** Everything — container parsing, LTC decoding,
fingerprinting, alignment — runs in the browser. No audio is ever uploaded and
there is nothing to run on a server. `index.html` is the entire application:
typefaces are embedded in it, so the page makes no network request of any kind
once it has loaded.

---

## Putting it on etchlive.com

etchlive.com is served by GitHub Pages, so this is a folder in the repo that
already serves it — no new hosting, no DNS, no build step.

**Find the repo:** it's the one whose *Settings → Pages* shows `etchlive.com`
as the custom domain (it will also contain a `CNAME` file with `etchlive.com`
in it).

### Without touching a terminal

1. Open that repo on github.com.
2. **Add file → Upload files**.
3. Drag this whole `diff` folder into the drop area. GitHub keeps the folder
   structure, so you end up with `diff/index.html` and the rest beside it.
4. Write a commit message and **Commit changes**.
5. Wait for the Pages deploy (the amber dot next to the commit turns into a
   green tick — usually under a minute).

It is then live at **https://etchlive.com/diff/**

### With git

```bash
git clone https://github.com/<you>/<the-repo>.git
cd <the-repo>
cp -R /path/to/diff .
git add diff && git commit -m "Add Playback Track Diff" && git push
```

### Linking to it from the landing page

Drop this wherever it fits:

```html
<a href="/diff/">Playback Track Diff — check a drop against what you rehearsed</a>
```

---

## Updating it later

Replace `diff/index.html` and commit. Anyone who has used the page before is
running a cached copy, so also bump the version string at the top of `sw.js`:

```js
const CACHE = 'playback-track-diff-v3';   // was v2
```

That retires the old cache. Returning users get a small "A newer version is
ready — Reload" prompt rather than being silently stuck on the old build.

---

## What each file is for

| File | Why it's here |
|---|---|
| `index.html` | The entire application, typefaces included. Everything else is optional. |
| `sw.js` | Service worker. Keeps the tool working on a dead venue connection after the first visit. |
| `manifest.json` | Lets it install to the dock / home screen as an app. |
| `icon-*.png`, `apple-touch-icon.png` | Icons for the tab, the dock and the installed app. |

Delete everything except `index.html` and it still works — you just lose the
offline cache and the install prompt.

## Notes

- **It also works straight off disk.** Double-clicking `index.html` opens a
  fully working copy — handy on a laptop at FOH, or on a stick. The only thing
  you lose is the service worker, which browsers only allow over http(s).
- **Any static host will do.** Netlify, Cloudflare Pages, S3, a folder on a web
  server — it is plain static files with no server-side anything. If you move it,
  the only requirement is that `sw.js` sits at the same path as `index.html`,
  because a service worker can only cover its own directory and below.
- **Supabase isn't involved.** Nothing to configure, no keys in the page. If you
  later want the crew to share a history of drop-checks, or the page behind the
  Etch login, that's the point at which it earns its place — not before.
- **Large compressed files.** WAV and AIFF are parsed natively and streamed, so
  length costs nothing. MP3, FLAC and friends go through the browser's own
  decoder, which unpacks the whole file into memory — for a very long compressed
  file, export a WAV instead.
