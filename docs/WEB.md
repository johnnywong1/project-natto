# Playing in a browser (GitHub Pages)

The game exports to the web (Godot 4.7 single-threaded Web build, Compatibility renderer), so
anyone can play **solo** at `https://<user>.github.io/project-natto/` with no install.

## One-time setup
1. Push `main` to GitHub (the repo must be public, or on a plan that allows Pages for private repos).
2. Repo **Settings → Pages → Source = "GitHub Actions"**.
3. The workflow `.github/workflows/pages.yml` runs on every push to `main` (or by hand under
   Actions → "Deploy web build to GitHub Pages"), exports the `Web` preset and publishes it.

## What works in a browser
- Solo play, saves (kept in the browser's storage for that site, per browser), sound after the
  first click, Esc menu, settings (fullscreen toggle; window size/vsync rows are hidden).
- "Host a game" and "Quit" are hidden: a browser tab can't run a server or close itself.
- "Join a game" works **only with a WebSocket address** (see below).

## WebSocket transport (alongside ENet)
ENet (UDP) stays the default for desktop. WebSocket is an alternative that also works through
browsers, proxies and most tunnels:
- Menu: tick **WebSocket** on the Host or Join page. Joining an address that starts with
  `ws://` or `wss://` picks it automatically.
- Command line: `--transport=ws` with `--host`, `--join=<address>` and `--port=<n>`, e.g.
  `godot --headless --path . -- --host --transport=ws --port=7777 --autostart=1`
- A browser can only be a *client* of a WebSocket host. For browser multiplayer later, run a
  headless host somewhere reachable and put it behind `wss://` (TLS), because a page served over
  https can't open plain `ws://` connections.
- LAN discovery (UDP broadcast) is desktop-only. `tools/lag_proxy.py` is UDP, so lag profiles
  apply to ENet only.
- Tests: `python tools/run_tests.py --only lobby-ws` runs the whole sign-in/lobby story over WebSocket.

## Building by hand
Install the Godot 4.7.2 export templates, then:
`godot --headless --path . --export-release "Web" build/web/index.html`
and serve `build/web/` with any static server (`python -m http.server`). `build/` is git-ignored.
