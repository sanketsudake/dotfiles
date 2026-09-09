"""Load a plan.json into a Ctx: the resolved brand, geometry and timing every stage reads."""
import json
import os
from dataclasses import dataclass


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


@dataclass
class Ctx:
    plan: dict
    work: str
    W: int
    H: int
    strip: int
    strip_color: str
    fps: int
    master: str
    brand: dict
    fb: str
    fr: str
    accent: tuple
    ink: tuple
    muted: tuple
    bg: tuple
    light: tuple
    accent_ass: str
    src_start: float
    src_end: float
    card_dur: float
    open_dur: float
    end_dur: float
    xf: float
    callout_dur: float
    out: str


def load(path):
    """Read the plan, create and enter its work dir (v1 did this at import time), and build the Ctx."""
    plan = json.load(open(path))
    work = os.path.abspath(plan.get('workdir', os.path.dirname(os.path.abspath(path))))
    os.makedirs(work, exist_ok=True)
    os.chdir(work)
    brand = plan.get('brand', {})
    accent = hexrgb(brand.get('accent', '#3b5bfd'))
    return Ctx(
        plan=plan,
        work=work,
        W=plan.get('width', 1920),
        H=plan.get('height', 1080),
        strip=plan.get('chrome_top', 0),
        strip_color=plan.get('strip_color', '0b1220'),
        fps=plan.get('fps', 30),
        master='master.mov',
        brand=brand,
        fb=brand.get('font_bold', '/System/Library/Fonts/Supplemental/Arial Bold.ttf'),
        fr=brand.get('font_regular', '/System/Library/Fonts/Supplemental/Arial.ttf'),
        accent=accent,
        ink=hexrgb(brand.get('ink', '#0b1220')),
        muted=hexrgb(brand.get('muted', '#788296')),
        bg=hexrgb(brand.get('card_bg', '#f8fafc')),
        light=hexrgb(brand.get('light', '#d5d9e2')),
        accent_ass='%02X%02X%02X' % (accent[2], accent[1], accent[0]),  # ASS colours are BGR
        src_start=plan.get('src_start', 0.0),
        src_end=plan.get('src_end', 0.0),
        card_dur=plan.get('card_dur', 2.4),
        open_dur=plan.get('open_dur', 3.2),
        end_dur=plan.get('end_dur', 5.0),
        xf=plan.get('xfade', 0.45),
        callout_dur=plan.get('callout_dur', 5.0),
        out=plan.get('out_prefix', 'final'),
    )
