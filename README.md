# OpenTCG (private)

A multi-game trading card game table grown from [OpenMTG](https://github.com/Coral-coder/openmtg):
the same deterministic lockstep core and app shell, with a rules engine per game.

| Path | What |
| --- | --- |
| `lib/main.dart` | The game picker. Magic opens OpenMTG's app (package `mtg_ui`). |
| `lib/lorcana/` | Lorcana's menu, table, card view, store and session (on tcg_app's `MatchSession`). |
| `packages/lorcana/` | Disney Lorcana rules engine (pure Dart, deterministic), built on `tcg_core`. |
| `docs/lorcana-comprehensive-rules-2.2.0.txt` | The official Comprehensive Rules (v2.2.0, effective July 9, 2026), text extracted from disneylorcana.com. |
| `data/` | Card data snapshots. |

Shared packages (`tcg_core`, `tcg_app`) come from openmtg as git dependencies. For local work
next to an openmtg checkout, a git-ignored `pubspec_overrides.yaml` points them at `../openmtg`.

Private: card data and images for games without a fan content policy are bundled here, which is
why this repository isn't public. Note that anything hosted from it (a website) is public.

## Working on it

    flutter pub get
    (cd packages/lorcana && dart test && dart run bin/chaos.dart --games 200 && tool/xplat_check.sh)
    flutter test
    flutter run -d chrome

Card images are Ravensburger's, shown on the web as HTML image elements: their server doesn't
allow cross-origin reads, which a canvas would need.
