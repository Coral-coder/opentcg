# riftbound

A deterministic rules engine for **Riftbound**, Riot Games' League of Legends trading card game,
on the shared `tcg_core` match contract (the same seed and moves give the same game on every
device, so it can be played in lockstep online).

- **Rules:** the Riftbound Core Rules, last updated 2026-10-09
  ([PDF](https://cmsassets.rgpub.io/sanity/files/dsfx7636/news_live/5c7946f7c3b8c6e0faff85ab6dadc6d2e721ea94.pdf),
  from the official [Rules Hub](https://playriftbound.com/en-us/rules-hub/)); the extracted text is
  `docs/riftbound-core-rules.txt` at the repository root, and code comments cite it as "CR n".
  Mode of play: 1v1 Duel (CR 487).
- **Card data:** [Riftcodex](https://riftcodex.com), an open, unofficial fan API
  (`https://api.riftcodex.com/cards`, every page). The raw dump is
  `data/riftbound-cards.raw.json`; `bin/build_db.dart` turns it into `data/riftbound-cards.json`
  and `data/riftbound-coverage.json`. Card text, names and images are © Riot Games.

## What's implemented

Setup and mulligans; the turn (awaken, beginning, hold scoring, channel, draw, main, ending);
runes (exhaust for Energy, recycle for Power, paid automatically, including Reaction abilities
that add resources); playing units, gear and spells; the chain with Priority and Reactions;
showdowns with Focus; Standard Moves (Ganking); combat (Assault, Shield, Tank, Backline, stun,
damage assignment, recall); conquering and holding, the final-point rule, Burn Out, winning at 8.

Keywords: Accelerate, Action, Reaction, Assault, Shield, Tank, Ganking, Deflect, Temporary,
Vision, Backline, Deathknell, Legion, Repeat.

A card counts as supported only when every line of its text is understood (`bin/card.dart --dump`
shows how each supported card is read). Not yet: Hidden, Ambush, Equip and other equipment rules,
XP and Level, Empower, Flow, Weaponmaster, multi-mode spells, most "as you play" costs.

Simplifications: payments pick runes automatically; combat damage is assigned automatically
(legally, killing as many units as it can); repeated spells reuse their first targets; when two
battlefields are contested at once the lower one is resolved first.

## Tools

    dart run bin/build_db.dart ../../data/riftbound-cards.raw.json ../../data
    dart run bin/card.dart "Jinx, Demolitionist" ~yasuo   # how cards are read
    dart run bin/card.dart --legends | --decks | --supported | --dump
    dart run bin/chaos.dart --games 300                  # bot games, replayed and compared
    tool/xplat_check.sh                                  # Dart VM vs JavaScript fingerprints
