# mile_by_mile_for_elten

A Ruby implementation of the "Mile by Mile" board game (aka Mille Bornes) —
the engine behind an Elten app for blind users (see `elten_app/`).

## Structure

```
lib/mile_by_mile.rb              — entry point, requires all engine files
lib/mile_by_mile/card.rb         — base card class
lib/mile_by_mile/cards/
  distance_card.rb                — distance cards (25/50/75/100/200 miles)
  hazard_card.rb                  — hazard cards (played against an opponent)
  remedy_card.rb                  — remedy cards (played on yourself)
  safety_card.rb                  — safety/immunity cards (yourself, permanent)
  remove_all_safeties_card.rb     — optional "strip all immunities" card
lib/mile_by_mile/car.rb          — car/horse state
lib/mile_by_mile/deck.rb         — deck, built strictly from the rules' card counts
lib/mile_by_mile/player.rb       — player: hand + car
lib/mile_by_mile/team.rb         — team sharing one car
lib/mile_by_mile/game.rb         — turn engine, all game rules
lib/mile_by_mile/variants/horse_deck.rb — "horses" variant
test/mile_by_mile_test.rb        — smoke tests (minitest, stdlib)
```

Card names are plain English strings (gettext source/msgid). The engine
itself has no gettext dependency — translation happens only in the Elten
UI layer (`elten_app/`), see its README for the ru/pl locale.

## Note on deck size

The rules text states the total as "105 or 106 cards", but summing the
per-type counts as listed gives 107 (108 with the optional card). This
implementation follows the itemized per-type counts, not the stated total.

## Running tests

```bash
ruby test/mile_by_mile_test.rb
```

## Next

- Elten port (voice interface for blind users) — done, see `elten_app/`.
  Bot-only for now (multiplayer is on hold per Dawid Pieper — the
  signalling protocol is being redesigned).
- Multiplayer: bot signalling first, then real players — will build on
  `Program#signal`/`#signaled` from elten3, once the protocol is ready.
- Sounds are in `elten_app/audio/` (see that README for the naming scheme
  and a note on how Elten resolves sound asset names).
