"""Resolve one sans-serif face for Pillow (cards, text measurement) and libass (ASS overlays).

Order: the plan's brand.fonts override, Arial (macOS), DejaVu Sans, Liberation Sans. The same file feeds both
renderers, so a lower-third box measured by Pillow fits the text libass draws.
"""
import os
import sys
from dataclasses import dataclass
from PIL import ImageFont

CANDIDATES = [
    ('/System/Library/Fonts/Supplemental/Arial Bold.ttf', '/System/Library/Fonts/Supplemental/Arial.ttf'),
    ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
    ('/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf', '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'),
]


@dataclass
class Font:
    bold: str
    regular: str
    family: str
    dir: str


def family_of(path):
    """The family name libass matches on, read from the font file itself."""
    return ImageFont.truetype(path, 12).getname()[0]


def resolve(override=None):
    override = override or {}
    pairs = []
    if override.get('bold') or override.get('regular'):
        pairs.append((override.get('bold') or override.get('regular'), override.get('regular') or override.get('bold')))
    pairs += CANDIDATES
    tried = []
    for bold, regular in pairs:
        if os.path.isfile(bold) and os.path.isfile(regular):
            return Font(bold=bold, regular=regular, family=family_of(regular), dir=os.path.dirname(os.path.abspath(regular)))
        tried.append(f'{bold}, {regular}')
    print('no usable font found; set brand.fonts.bold and brand.fonts.regular. Tried:\n  ' + '\n  '.join(tried), file=sys.stderr)
    sys.exit(2)
