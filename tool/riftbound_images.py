#!/usr/bin/env python3
"""Copies every Riftbound card image into the website, small enough to load fast.

Riot's image server (cmsassets.rgpub.io) doesn't allow cross-origin reads, so a browser could
only show its images as HTML elements laid over the game canvas, and every such element costs
the page a full-screen graphics layer: enough of them and a phone's browser runs out of memory
and reloads the tab. Images served by the site itself are drawn straight onto the canvas.

    tool/riftbound_images.py data/riftbound-cards.json OUT_DIR [--limit N]

Writes OUT_DIR/<key>.webp for each card, keyed by riftboundImageKey in
lib/riftbound/riftbound_card.dart (FNV-1a of the card name). Images already in OUT_DIR are
kept, so a cached OUT_DIR only fetches new cards.
"""
import concurrent.futures
import io
import json
import os
import sys
import urllib.request

from PIL import Image

WIDTH = 420  # The short side in pixels: portrait cards 420 wide, landscape battlefields 420 tall.


def key(name: str) -> str:
    """FNV-1a, 32-bit, over the UTF-8 bytes; must match riftboundImageKey in Dart."""
    h = 0x811C9DC5
    for b in name.encode('utf-8'):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f'{h:08x}'


def fetch(urls: list[str], path: str) -> str | None:
    """The first of [urls] that loads."""
    err = None
    for url in urls:
        err = _fetch(url, path)
        if err is None:
            return None
    return err


def _fetch(url: str, path: str) -> str | None:
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'opentcg-site-builder'})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        im = Image.open(io.BytesIO(data)).convert('RGB')
        short = min(im.width, im.height)
        scale = WIDTH / short
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        tmp = path + '.tmp'
        im.save(tmp, 'WEBP', quality=80, method=4)
        os.replace(tmp, path)
        return None
    except Exception as e:  # A missing image only means that card falls back to its text frame.
        return f'{url}: {e}'


def main() -> None:
    argv = sys.argv[1:]
    limit = int(argv[argv.index('--limit') + 1]) if '--limit' in argv else None
    args = [a for i, a in enumerate(argv) if not a.startswith('--') and (i == 0 or not argv[i - 1].startswith('--'))]
    cards = json.load(open(args[0]))['cards']
    out = args[1]
    os.makedirs(out, exist_ok=True)
    todo, seen = [], {}
    for c in cards:
        name = c['n']
        k = key(name)
        if k in seen and seen[k] != name:
            sys.exit(f'Image key collision: {name!r} and {seen[k]!r}')
        seen[k] = name
        urls = [p[2] for p in c.get('pr') or [] if len(p) > 2 and p[2]]
        if urls and not os.path.exists(os.path.join(out, k + '.webp')):
            todo.append((urls, os.path.join(out, k + '.webp')))
    if limit is not None:
        todo = todo[:limit]
    print(f'{len(cards)} cards, {len(todo)} images to fetch')
    failed = []
    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        for err in pool.map(lambda t: fetch(*t), todo):
            if err:
                failed.append(err)
    for f in failed[:20]:
        print('failed:', f)
    have = sum(1 for f in os.listdir(out) if f.endswith('.webp'))
    print(f'{have} images in {out}, {len(failed)} failed')


if __name__ == '__main__':
    main()
