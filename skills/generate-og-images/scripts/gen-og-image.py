#!/usr/bin/env python3
"""
gen-og-image.py

Generate 1200x630 social-share (Open Graph / Twitter) images for blog posts and
talks. Hugo's embedded opengraph/twitter_cards templates pick up the result with
zero config: a page-bundle resource named ``feature.png`` becomes ``og:image`` and
upgrades the Twitter card to ``summary_large_image`` automatically.

The background is chosen in priority order:
  1. ``--bg FILE``     -- a hand-made / AI-generated background you supply.
  2. Nano Banana       -- ``gemini-2.5-flash-image`` via the google-genai SDK,
                          used when GEMINI_API_KEY is set and the SDK is present.
  3. Pillow gradient   -- a deterministic branded card (no network, no key).

Text (title, tags/event, brand) is ALWAYS rendered locally with Pillow, so it
stays crisp and correct regardless of the background source -- never trust an
image model to spell.

Output location:
  - Page bundle (``<slug>/index.md`` or a dir)  -> ``<slug>/feature.png``
  - Flat file   (``content/talks/<slug>.md``)   -> ``static/og/talks/<slug>.png``
    (also prints the ``images`` frontmatter line to add, since a flat page has
    no bundle resource to match).
  - ``--default``                               -> ``static/og/default.png``
    (the site-wide fallback referenced by ``params.images``).

Usage:
    gen-og-image.py content/posts/<slug>/index.md
    gen-og-image.py content/talks/<slug>.md
    gen-og-image.py --default
    gen-og-image.py --all-content          # every post + talk + the default
    gen-og-image.py --bg bg.png content/posts/<slug>/index.md
"""

import argparse
import os
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    sys.exit("Pillow is required: pip install Pillow (see scripts/ venv).")


def load_dotenv():
    """Read KEY=VALUE lines from a gitignored repo-root .env (e.g. GEMINI_API_KEY).
    Walks up from CWD; existing environment variables win."""
    for d in [Path.cwd(), *Path.cwd().parents]:
        f = d / ".env"
        if f.exists():
            for line in f.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
            return
        if (d / ".git").is_dir():
            return


load_dotenv()

# ---------------------------------------------------------------------------
# Default color palette — a neutral violet/slate gradient, not site-specific;
# swappable by forking the constants or adding --palette flags in a future pass.
# ---------------------------------------------------------------------------
W, H = 1200, 630
MARGIN = 80
BG_TOP = (15, 23, 42)        # slate-900  #0f172a
BG_BOTTOM = (46, 16, 101)    # violet-950 #2e1065
ACCENT = (124, 58, 237)      # violet-600 #7c3aed
ACCENT_SOFT = (167, 139, 250)  # violet-400 #a78bfa
TEXT = (255, 255, 255)
MUTED = (148, 163, 184)      # slate-400
CHIP_BG = (30, 41, 59)       # slate-800
CHIP_TEXT = (203, 213, 225)  # slate-300

FONT_CANDIDATES_BOLD = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]
FONT_CANDIDATES_REG = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
]


def load_font(path_override, candidates, size):
    paths = [path_override] if path_override else []
    paths += candidates
    for p in paths:
        if p and Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default(size)


# ---------------------------------------------------------------------------
# Frontmatter extraction (TOML for posts, YAML for talks) -- only the few
# fields we need, so no toml/yaml dependency is required.
# ---------------------------------------------------------------------------
def extract_fields(md_path: Path) -> dict:
    text = md_path.read_text(encoding="utf-8")
    m = re.match(r"^\s*(\+\+\+|---)\s*\n(.*?)\n\1\s*\n", text, re.DOTALL)
    if not m:
        raise ValueError(f"no frontmatter found in {md_path}")
    block = m.group(2)

    def find(key):
        # matches both `key = "v"` (TOML) and `key: "v"` / `key: v` (YAML)
        mm = re.search(rf"^{key}\s*[:=]\s*(.+)$", block, re.MULTILINE)
        if not mm:
            return None
        return mm.group(1).strip().strip('"').strip("'")

    title = find("title") or md_path.stem

    tags = []
    tm = re.search(r"^tags\s*=\s*\[(.*?)\]", block, re.MULTILINE | re.DOTALL)
    if tm:  # TOML inline array
        tags = [t.strip().strip('"').strip("'") for t in tm.group(1).split(",") if t.strip()]
    else:  # YAML block list
        ym = re.search(r"^tags:\s*\n((?:\s*-\s*.+\n?)+)", block, re.MULTILINE)
        if ym:
            tags = [re.sub(r"^\s*-\s*", "", ln).strip().strip('"').strip("'")
                    for ln in ym.group(1).splitlines() if ln.strip()]

    return {
        "title": title,
        "tags": [t for t in tags if t],
        "event": find("event"),
        "slug": find("slug"),
    }


# ---------------------------------------------------------------------------
# Backgrounds
# ---------------------------------------------------------------------------
def gradient_bg() -> Image.Image:
    """Deterministic diagonal slate->teal gradient with an emerald corner glow."""
    base = Image.new("RGB", (W, H), BG_TOP)
    px = base.load()
    for y in range(H):
        for x in range(0, W, 4):  # step 4px horizontally, cheap + smooth enough
            t = (x / W * 0.35) + (y / H * 0.65)
            r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
            g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
            b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
            for dx in range(4):
                if x + dx < W:
                    px[x + dx, y] = (r, g, b)
    # emerald radial glow, top-right
    glow = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W - 520, -260, W + 260, 360], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    tint = Image.new("RGB", (W, H), ACCENT)
    base = Image.composite(tint, base, glow)
    return base


def ai_bg(prompt: str):
    """Nano Banana (gemini-2.5-flash-image). Returns an Image or None on any failure."""
    if not os.environ.get("GEMINI_API_KEY"):
        return None
    try:
        from google import genai  # type: ignore
        from google.genai import types  # type: ignore
        client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
        model = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
        resp = client.models.generate_content(
            model=model,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_modalities=["IMAGE"],
                image_config=types.ImageConfig(aspect_ratio="16:9"),
            ),
        )
        for part in resp.parts:
            if part.inline_data:
                return cover_fit(part.as_image().convert("RGB"), W, H)
    except Exception as e:  # noqa: BLE001 -- background is best-effort; fall back
        print(f"  (Nano Banana unavailable, using gradient: {e})", file=sys.stderr)
    return None


def cover_fit(img: Image.Image, w: int, h: int) -> Image.Image:
    scale = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (img.width - w) // 2
    top = (img.height - h) // 2
    return img.crop((left, top, left + w, top + h))


def scrim(img: Image.Image) -> Image.Image:
    """Darken a photographic background so overlaid text stays legible."""
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for y in range(H):  # bottom-weighted vertical scrim
        a = int(40 + 150 * (y / H) ** 1.5)
        od.line([(0, y), (W, y)], fill=(8, 12, 24, a))
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


# ---------------------------------------------------------------------------
# Text layout
# ---------------------------------------------------------------------------
def wrap(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for word in words:
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit_title(draw, text, font_path, max_w, max_lines=4, hi=76, lo=40):
    """Largest font size (hi..lo) at which the title fits in max_lines."""
    for size in range(hi, lo - 1, -3):
        font = load_font(font_path, FONT_CANDIDATES_BOLD, size)
        lines = wrap(draw, text, font, max_w)
        if len(lines) <= max_lines:
            return font, lines, size
    font = load_font(font_path, FONT_CANDIDATES_BOLD, lo)
    return font, wrap(draw, text, font, max_w)[:max_lines], lo


def draw_chips(draw, labels, x, y, font, max_w):
    pad_x, pad_y, gap, h = 18, 9, 12, None
    cx = x
    for label in labels:
        label = label.upper()
        tw = draw.textlength(label, font=font)
        bbox = font.getbbox(label)
        th = bbox[3] - bbox[1]
        if h is None:
            h = th + pad_y * 2
        w = tw + pad_x * 2
        if cx + w > x + max_w:
            break
        draw.rounded_rectangle([cx, y, cx + w, y + h], radius=h // 2, fill=CHIP_BG)
        draw.text((cx + pad_x, y + pad_y - bbox[1]), label, font=font, fill=CHIP_TEXT)
        cx += w + gap


def compose(fields, kind, background, fonts, brand="", author=""):
    img = background.copy()
    draw = ImageDraw.Draw(img)

    # left accent bar
    draw.rectangle([0, 0, 10, H], fill=ACCENT)

    usable = W - 2 * MARGIN

    # kicker
    kicker = "TALK" if kind == "talk" else "BLOG"
    kfont = load_font(fonts["bold"], FONT_CANDIDATES_BOLD, 26)
    draw.text((MARGIN, MARGIN), kicker, font=kfont, fill=ACCENT_SOFT)
    if fields.get("event") and kind == "talk":
        ef = load_font(fonts["reg"], FONT_CANDIDATES_REG, 26)
        kx = MARGIN + draw.textlength(kicker, font=kfont) + 18
        draw.text((kx, MARGIN + 1), f"· {fields['event']}", font=ef, fill=MUTED)

    # title (vertically centred-ish in the middle band)
    tfont, lines, tsize = fit_title(draw, fields["title"], fonts["bold"], usable)
    line_h = int(tsize * 1.18)
    block_h = line_h * len(lines)
    ty = MARGIN + 70 + max(0, (300 - block_h) // 2)
    for ln in lines:
        draw.text((MARGIN, ty), ln, font=tfont, fill=TEXT)
        ty += line_h

    # tag chips (posts) under the title
    if fields.get("tags"):
        cfont = load_font(fonts["bold"], FONT_CANDIDATES_BOLD, 22)
        draw_chips(draw, fields["tags"][:4], MARGIN, ty + 18, cfont, usable)

    # footer brand: author on the left, brand on the right; skip when empty
    bfont = load_font(fonts["bold"], FONT_CANDIDATES_BOLD, 30)
    by = H - MARGIN - 30
    if author:
        draw.ellipse([MARGIN, by + 6, MARGIN + 18, by + 24], fill=ACCENT)
        draw.text((MARGIN + 30, by), author, font=bfont, fill=TEXT)
    if brand:
        afont = load_font(fonts["reg"], FONT_CANDIDATES_REG, 30)
        aw = draw.textlength(brand, font=afont)
        draw.text((W - MARGIN - aw, by), brand, font=afont, fill=MUTED)

    return img


def site_default(fonts, brand="", author="", subtitle=""):
    """Generic branded card (no post title) for the site-wide fallback."""
    img = gradient_bg()
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, 10, H], fill=ACCENT)
    tfont = load_font(fonts["bold"], FONT_CANDIDATES_BOLD, 84)
    if author:
        draw.text((MARGIN, 240), author, font=tfont, fill=TEXT)
    if subtitle:
        sfont = load_font(fonts["reg"], FONT_CANDIDATES_REG, 34)
        draw.text((MARGIN, 350), subtitle, font=sfont, fill=MUTED)
    if brand:
        bfont = load_font(fonts["bold"], FONT_CANDIDATES_BOLD, 30)
        draw.ellipse([MARGIN, H - MARGIN - 24, MARGIN + 18, H - MARGIN - 6], fill=ACCENT)
        draw.text((MARGIN + 30, H - MARGIN - 30), brand, font=bfont, fill=TEXT)
    return img


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
def repo_root(start: Path) -> Path:
    for p in [start, *start.parents]:
        if (p / "config" / "_default").is_dir() or (p / ".git").is_dir():
            return p
    return start


def ai_prompt(fields, kind):
    topic = ", ".join(fields.get("tags") or []) or fields["title"]
    return (
        "A modern, minimal, abstract technology background, 16:9 landscape. "
        "Dark slate and emerald-teal color palette. Subtle geometric grid and "
        f"network motifs evoking {topic}. Soft depth-of-field glow, cinematic, "
        "professional, high quality. Absolutely no text, no words, no letters, "
        "no logos -- background imagery only."
    )


def output_path(md_path: Path, root: Path) -> tuple[Path, bool]:
    """Returns (output_png, is_bundle). Flat files go to static/og/<section>/."""
    if md_path.name == "index.md":
        return md_path.parent / "feature.png", True
    section = md_path.parent.name  # e.g. "talks"
    return root / "static" / "og" / section / f"{md_path.stem}.png", False


def target_slug(md_path: Path) -> str:
    """Stable name for a target: the bundle dir for index.md, else the file stem."""
    return md_path.parent.name if md_path.name == "index.md" else md_path.stem


def resolve_bg(md_path: Path, bg: str | None, bg_dir: str | None) -> str | None:
    """An explicit --bg wins; otherwise look for <slug>.<ext> in --bg-dir."""
    if bg:
        return bg
    if bg_dir:
        slug = target_slug(md_path)
        for ext in (".png", ".jpg", ".jpeg", ".webp"):
            cand = Path(bg_dir) / f"{slug}{ext}"
            if cand.exists():
                return str(cand)
    return None


def make_background(fields, kind, bg_file):
    if bg_file:
        return scrim(cover_fit(Image.open(bg_file).convert("RGB"), W, H))
    ai = ai_bg(ai_prompt(fields, kind))
    return scrim(ai) if ai else gradient_bg()


def generate_for(md_path: Path, root: Path, fonts, bg_file, out_override=None,
                 brand="", author=""):
    fields = extract_fields(md_path)
    kind = "talk" if "talks" in md_path.parts else "post"
    img = compose(fields, kind, make_background(fields, kind, bg_file), fonts,
                  brand=brand, author=author)

    if out_override:
        out, is_bundle = Path(out_override), True
    else:
        out, is_bundle = output_path(md_path, root)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    try:
        print(f"  wrote {out.relative_to(root)}" + (f" (bg: {Path(bg_file).name})" if bg_file else ""))
    except ValueError:
        print(f"  wrote {out}")
    if not is_bundle and not out_override:
        rel = out.relative_to(root / "static").as_posix()
        print(f"    -> ensure frontmatter: images = [\"{rel}\"]")


def discover(root: Path, sections: list[str]) -> list[Path]:
    targets = []
    for section in sections:
        section_dir = root / "content" / section
        # page bundles: <section>/<slug>/index.md
        for p in sorted(section_dir.glob("*/index.md")):
            targets.append(p)
        # flat files: <section>/<slug>.md (skip _index.md)
        for p in sorted(section_dir.glob("*.md")):
            if p.name != "_index.md":
                targets.append(p)
    return targets


def main():
    ap = argparse.ArgumentParser(description="Generate OG/social images for posts and talks.")
    ap.add_argument("targets", nargs="*", help="post/talk markdown files or bundle dirs")
    ap.add_argument("--default", action="store_true", help="generate static/og/default.png")
    ap.add_argument("--all-content", action="store_true", help="all posts + talks + default")
    ap.add_argument("--bg", help="background image to use for the target(s)")
    ap.add_argument("--bg-dir", help="folder of <slug>.png|jpg backgrounds; matched per target, "
                                     "falling back to AI/gradient when absent")
    ap.add_argument("--print-prompts", action="store_true",
                    help="print the per-target image prompt (to paste into the Gemini app) and exit")
    ap.add_argument("--out", help="explicit output path (single target only)")
    ap.add_argument("--font-bold", help="path to a bold .ttf")
    ap.add_argument("--font", help="path to a regular .ttf")
    ap.add_argument("--brand", default="", help="Brand string overlaid on the card (e.g. my.site)")
    ap.add_argument("--author", default="", help="Author name overlaid on the card")
    ap.add_argument("--subtitle", default="", help="Subtitle/tagline overlaid on the site default card")
    ap.add_argument("--sections", default="posts,talks",
                    help="Comma-separated content sections to discover for --all-content")
    args = ap.parse_args()

    fonts = {"bold": args.font_bold, "reg": args.font}
    sections = [s.strip() for s in args.sections.split(",") if s.strip()]
    here = Path.cwd()
    root = repo_root(Path(args.targets[0]).resolve() if args.targets else here)

    # resolve targets
    targets = []
    if args.all_content:
        targets = discover(root, sections)
    else:
        for t in args.targets:
            p = Path(t).resolve()
            if p.is_dir():
                p = p / "index.md"
            targets.append(p)

    if args.print_prompts:
        if not targets:
            ap.error("--print-prompts needs targets or --all-content")
        for md in targets:
            fields = extract_fields(md)
            kind = "talk" if "talks" in md.parts else "post"
            print(f"### {target_slug(md)}\n{ai_prompt(fields, kind)}\n")
        return

    if args.default or args.all_content:
        out = root / "static" / "og" / "default.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        site_default(fonts, brand=args.brand, author=args.author, subtitle=args.subtitle).save(out, "PNG")
        print(f"  wrote {out.relative_to(root)}")

    for md in targets:
        print(f"{md}")
        bg = resolve_bg(md, args.bg, args.bg_dir)
        out_override = args.out if (args.out and len(targets) == 1) else None
        generate_for(md, root, fonts, bg, out_override, brand=args.brand, author=args.author)

    if not targets and not (args.default or args.all_content):
        ap.error("nothing to do: pass targets, --default, or --all-content")


if __name__ == "__main__":
    main()
