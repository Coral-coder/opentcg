#!/usr/bin/env python3
"""Saves what Riftcodex's card list leaves out of Equipment: their Effect Text and Might Bonus.

An Equipment (CR 150) has rules text, an Effect Text box that its unit gains while it's attached
(CR 136) and a Might Bonus (CR 137). Riftcodex (data/riftbound-cards.raw.json) carries only the
rules text, so "B.F. Sword" would read as an Equipment that does nothing. Riot's official card
gallery has both; this reads the gallery page's embedded data and keeps, for every card with a
Might Bonus, that bonus and its Effect Text (as HTML, which bin/build_db.dart normalises).

    tool/riftbound_gallery.py data/riftbound-gallery.json [PAGE.html]

With PAGE.html it reads a saved copy of the gallery page instead of downloading it.
"""
import json
import re
import sys
import urllib.request

URL = 'https://riftbound.leagueoflegends.com/en-us/card-gallery/'


def main() -> None:
    out = sys.argv[1]
    if len(sys.argv) > 2:
        page = open(sys.argv[2], encoding='utf-8').read()
    else:
        req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0 (opentcg data builder)'})
        with urllib.request.urlopen(req, timeout=120) as r:
            page = r.read().decode('utf-8')
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', page, re.S)
    if m is None:
        sys.exit('The gallery page has no __NEXT_DATA__ block (its layout changed?)')
    data = json.loads(m.group(1))
    items = None
    for blade in data['props']['pageProps']['page']['blades']:
        if isinstance(blade, dict) and isinstance(blade.get('cards'), dict) and 'items' in blade['cards']:
            items = blade['cards']['items']
            break
    if items is None:
        sys.exit('No card list found in the gallery data')
    cards = {}
    for i in items:
        bonus = ((i.get('mightBonus') or {}).get('value') or {}).get('id')
        if bonus is None:
            continue
        effect = ((i.get('effect') or {}).get('richText') or {}).get('body', '')
        name = i['name']
        prev = cards.get(name)
        if prev is not None and prev != {'effect': effect, 'mightBonus': bonus}:
            sys.exit(f'Two printings of {name} disagree')
        cards[name] = {'effect': effect, 'mightBonus': bonus}
    doc = {
        'source': URL,
        'about': 'Effect Text (CR 136) and Might Bonus (CR 137) of every Equipment, from Riot\'s official card gallery; '
                 'card data and text are Riot Games\'. Written by tool/riftbound_gallery.py, read by packages/riftbound/bin/build_db.dart.',
        'cards': {k: cards[k] for k in sorted(cards)},
    }
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write('\n')
    print(f'{len(cards)} cards with a Might Bonus → {out}')


if __name__ == '__main__':
    main()
