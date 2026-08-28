# MileByMile for Elten

A port of the game to the Elten 3.0 API (following the AudioMemory /
Purrposterous samples from pajper). Bot-only mode for now — multiplayer
is on hold at Dawid Pieper's request until the new signalling protocol
is ready.

## Structure

```
__app.rb                          — entry point + Elten3AppInfo manifest
__manifest.json                   — duplicate manifest (matches the samples' convention)
lib/mile_by_mile/                 — COPY of the game engine from ../lib/mile_by_mile
                                     (kept in sync via ../sync_engine.sh)
lib/mile_by_mile_elten/
  bot.rb                          — AI opponent
  audio.rb                        — play_app_sound wrapper, sound name contract
  ui.rb                           — menu, player/bot turns, help
fuzz_bot_vs_bot.rb                — runs N bot-vs-bot games outside Elten
                                     (catches crashes in bot logic against the real engine)
harness_ui_smoke.rb               — runs the full MileByMileElten::UI class outside
                                     Elten via stubs for _/selector/alert/EditBox
Audio/                            — sound assets (flat, see naming note below)
locale/                           — ru/pl gettext catalogs (po + compiled mo)
```

## Important: don't edit the engine here

`lib/mile_by_mile/` inside `elten_app/` is a copy. Make changes in the
top-level `lib/mile_by_mile/`, then run `../sync_engine.sh` to copy them
here. Otherwise the two copies drift apart.

## Bot AI

Turn priority: 1) repair/start/un-reverse your own car, 2) play a safety
card you don't have yet (keeps your turn), 3) play a hazard on the
leader if it would actually do something (target lacks the matching
immunity, condition applies), 4) the longest legal distance card,
5) any card in hand as a last resort (after the engine fix, any card
that can't take effect is simply discarded instead of crashing the game).

## Testing the bot for crashes

```bash
ruby fuzz_bot_vs_bot.rb 1000
```

Runs 1000 bot-vs-bot games outside the Elten runtime (engine only, no
Program/UI widgets needed), checking that the bot's decisions never
raise an exception inside the game.

```bash
ruby harness_ui_smoke.rb 100
```

Runs 100 full games through the actual `MileByMileElten::UI` class
(menu, human turn, bot turn, help) using minimal stand-ins for the
Elten API (`_`, `selector`, `alert`, `EditBox`, `Program`), so the UI
integration itself is covered, not just the engine.

## Localization (po/mo)

Source language in the code is English (`_('...')` msgid). `locale/ru.po`
and `locale/pl.po` are the Russian and Polish translations, compiled to
`locale/ru.mo` / `locale/pl.mo` via `msgfmt`. Card names are translated
via `_(card.name)` in the UI layer — the engine itself
(`lib/mile_by_mile`) has no gettext dependency, so it stays
self-contained and testable outside Elten.

Rebuild after editing a `.po` file:

```bash
cd locale
msgfmt -c -o ru.mo ru.po
msgfmt -c -o pl.mo pl.po
```

## Sound — an important finding

In `elten3/src/eapi/program.rb`, sound assets are looked up by basename
only, extension stripped (`add_sound_asset` always does
`File.basename(path, ext)`), and the physical loader
(`collect_physical_sound_assets`) scans the `Audio/` folder WITHOUT
recursing into subfolders (`Dir.children`, not `Dir.glob("**/*")`). So
all the files you sent (`cars/fail/tire.ogg`, `horses/success/tire.ogg`,
etc.) got flattened into `elten_app/Audio/` with unique names like
`cars_fail_tire.ogg`, `horses_success_tire.ogg`, `prot_tire.ogg`, to
avoid a basename collision (`tire` existed in 5 different subfolders).
If your packaging tool works differently (e.g. keeps the relative path
as the name), let me know and I'll rewire the names in `audio.rb`.

Naming scheme: `<variant>_<0|25|50|75|100|200>`, `<variant>_bibip`,
`<variant>_welcome`, `<variant>_fail_<key>`, `<variant>_success_<key>`,
`prot_<key>`, `wow`. `variant` = `cars`/`horses`. `key` = `ready` (engine),
`tank` (fuel), `tire` (wheel), `wheel` (u-turn), `seat` (accident),
`speed` (speed limit), `pass` (skip turn).

## What's new in this round

- Card theme (cars/horses) and distance (700/1000 miles) selection at
  the start of a game.
- Drawing a card still happens automatically, but is now voiced and
  panned to the right (`Audio#card_drawn`, `pan: 82`) — as if you're
  reaching for the deck on your right.
- Right before the human's turn, the screen reader speaks one combined
  line: what the bot did + what you just drew + "Your turn" — e.g.
  `Bot moved 50 miles. You drew 100 miles. Your turn.` (translated into
  ru/pl).

## What's new in this round

- Rules screen now uses Elten's `display_text` (a ReadOnly MultiLine
  EditBox dialog) instead of a hand-rolled `show_text` that did not exist
  in the Elten 3 API — opening Rules used to raise NoMethodError on a real
  runtime. The harness now exercises that path (regression check).
- Sound assets moved from `audio/` to `Audio/`: both
  `build-eltenapp.rb` (packages only `Audio/**` as sound records) and
  `collect_physical_sound_assets` (scans the `Audio` folder at runtime)
  match on the capital name, so the lowercase folder meant zero sounds in
  a packaged app on case-sensitive platforms.

## Next

- Real multiplayer on top of `Program#signal`/`#signaled` — once Pieper
  ships the new signalling protocol.
- Online leaderboard via `server_table` (like AudioMemory) — not wired
  up yet.
