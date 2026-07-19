#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


RUN_DIR = Path(__file__).resolve().parent
WORKSPACE = RUN_DIR.parents[3]
SOURCE_DIR = WORKSPACE / "AppStore/screenshots/upload-ready-2560x1600"
BACKGROUND_PATH = RUN_DIR / "backgrounds/today-md-light-polish.png"
APP_ICON_PATH = WORKSPACE / "today-md/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
BASE_DIR = RUN_DIR / "bases"
FINAL_DIR = RUN_DIR / "final"
PREVIEW_DIR = RUN_DIR / "preview"

WIDTH, HEIGHT = 2560, 1600
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"

SLIDES = [
    {
        "id": "01-plan-today",
        "source": "01-board-task-details.png",
        "feature": "BOARD + TASK DETAILS",
        "headline": "Everything important, in one calm view.",
        "description": "Plan Today and This Week while notes and checklists stay beside every task.",
        "accent": "#E07A00",
    },
    {
        "id": "02-organize-projects",
        "source": "02-product-launch.png",
        "feature": "LISTS",
        "headline": "Organize every project your way.",
        "description": "Create focused lists and move work between Today, This Week, and Backlog.",
        "accent": "#C02BCF",
    },
    {
        "id": "03-time-blocking",
        "source": "03-calendar-planner.png",
        "feature": "CALENDAR PLANNER · PRO",
        "headline": "Turn tasks into time blocks.",
        "description": "Plan beside your calendar and protect time for the work that matters.",
        "accent": "#2F6FDB",
    },
    {
        "id": "04-week-view",
        "source": "04-week-view.png",
        "feature": "WEEK VIEW · PRO",
        "headline": "See your week without switching apps.",
        "description": "Keep tasks and calendar events together in one focused weekly view.",
        "accent": "#128A92",
    },
    {
        "id": "05-folder-sync",
        "source": "05-folder-sync.png",
        "feature": "FOLDER SYNC · PRO",
        "headline": "Markdown files that stay yours.",
        "description": "Sync a readable archive to the folder you choose.",
        "accent": "#269447",
    },
]


def font(size: int, variation: str) -> ImageFont.FreeTypeFont:
    result = ImageFont.truetype(FONT_PATH, size=size)
    result.set_variation_by_name(variation)
    return result


FONT_APP = font(44, "Semibold")
FONT_FEATURE = font(26, "Bold")
FONT_HEADLINE = font(88, "Bold")
FONT_DESCRIPTION = font(37, "Regular")


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def rounded_image(image: Image.Image, size: tuple[int, int], radius: int) -> Image.Image:
    resized = image.resize(size, Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    resized.putalpha(mask)
    return resized


def create_background(generated: bool, accent: tuple[int, int, int]) -> Image.Image:
    if generated:
        canvas = cover(Image.open(BACKGROUND_PATH).convert("RGB"), (WIDTH, HEIGHT)).convert("RGBA")
    else:
        canvas = Image.new("RGBA", (WIDTH, HEIGHT), (251, 248, 243, 255))

    tint = Image.new("RGBA", (WIDTH, HEIGHT), (*accent, 12))
    canvas = Image.alpha_composite(canvas, tint)

    veil = Image.new("RGBA", (WIDTH, HEIGHT), (255, 255, 255, 0))
    veil_pixels = veil.load()
    for y in range(HEIGHT):
        alpha = max(0, round(205 * (1 - min(y, 800) / 800)))
        for x in range(WIDTH):
            veil_pixels[x, y] = (255, 255, 255, alpha)
    return Image.alpha_composite(canvas, veil)


def place_screenshot(canvas: Image.Image, source: Image.Image) -> None:
    shot_x, shot_y = 220, 395
    shot_w = 2120
    shot_h = round(shot_w * source.height / source.width)
    radius = 42

    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (shot_x + 1, shot_y + 18, shot_x + shot_w - 1, shot_y + shot_h + 18),
        radius=radius,
        fill=(62, 44, 31, 82),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.alpha_composite(shadow)

    framed = rounded_image(source, (shot_w, shot_h), radius)
    canvas.alpha_composite(framed, (shot_x, shot_y))

    border = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (shot_x, shot_y, shot_x + shot_w - 1, shot_y + shot_h - 1),
        radius=radius,
        outline=(69, 52, 39, 34),
        width=2,
    )
    canvas.alpha_composite(border)


def draw_header(canvas: Image.Image, slide: dict) -> None:
    accent = hex_rgb(slide["accent"])
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(APP_ICON_PATH).convert("RGBA").resize((72, 72), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, (150, 64))
    draw.text((244, 75), "today-md", font=FONT_APP, fill=(48, 40, 34, 255))

    feature_bbox = draw.textbbox((0, 0), slide["feature"], font=FONT_FEATURE)
    feature_w = feature_bbox[2] - feature_bbox[0] + 54
    feature_h = 54
    feature_x = WIDTH - 150 - feature_w
    feature_y = 72
    pill = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle(
        (feature_x, feature_y, feature_x + feature_w, feature_y + feature_h),
        radius=27,
        fill=(*accent, 25),
        outline=(*accent, 82),
        width=2,
    )
    canvas.alpha_composite(pill)
    draw = ImageDraw.Draw(canvas)
    draw.text((feature_x + 27, feature_y + 11), slide["feature"], font=FONT_FEATURE, fill=(*accent, 255))

    draw.text((150, 164), slide["headline"], font=FONT_HEADLINE, fill=(42, 34, 29, 255))
    draw.text((154, 287), slide["description"], font=FONT_DESCRIPTION, fill=(93, 82, 73, 255))


def render_slide(slide: dict, generated: bool) -> Path:
    accent = hex_rgb(slide["accent"])
    canvas = create_background(generated, accent)
    draw_header(canvas, slide)
    source = Image.open(SOURCE_DIR / slide["source"]).convert("RGB")
    place_screenshot(canvas, source)
    destination = (FINAL_DIR if generated else BASE_DIR) / f"{slide['id']}.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, "PNG", optimize=True)
    return destination


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w, thumb_h = 760, 475
    gap = 36
    margin = 48
    columns, rows = 3, 2
    sheet = Image.new(
        "RGB",
        (
            margin * 2 + columns * thumb_w + (columns - 1) * gap,
            margin * 2 + rows * thumb_h + (rows - 1) * gap,
        ),
        (246, 243, 239),
    )
    for index, path in enumerate(paths):
        image = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = margin + (index % columns) * (thumb_w + gap)
        y = margin + (index // columns) * (thumb_h + gap)
        sheet.paste(image, (x, y))
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    destination = PREVIEW_DIR / "contact-sheet.png"
    sheet.save(destination, "PNG", optimize=True)
    return destination


def main() -> None:
    base_paths = [render_slide(slide, generated=False) for slide in SLIDES]
    final_paths = [render_slide(slide, generated=True) for slide in SLIDES]
    contact_sheet = make_contact_sheet(final_paths)

    manifest = {
        "project": "today-md App Store preview gallery",
        "status": "review",
        "dimensions": {"width": WIDTH, "height": HEIGHT},
        "format": "PNG, RGB, no alpha",
        "sourceScreenshots": str(SOURCE_DIR),
        "generatedPolishLayer": str(BACKGROUND_PATH),
        "appIcon": str(APP_ICON_PATH),
        "composition": "Deterministic Pillow layout using exact copy and supplied product screenshots.",
        "copyRisk": "Low: capability language is limited to visible, implemented features.",
        "slides": [
            {
                **slide,
                "base": str(base_paths[index]),
                "final": str(final_paths[index]),
            }
            for index, slide in enumerate(SLIDES)
        ],
        "contactSheet": str(contact_sheet),
    }
    (RUN_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    review_manifest = [
        {
            "id": slide["id"],
            "index": index + 1,
            "title": slide["headline"],
            "label": slide["feature"],
            "caption": slide["description"],
            "src": str(final_paths[index]),
            "href": str(final_paths[index]),
            "output": final_paths[index].name,
            "prompt": "Deterministic final composite; product screenshot and copy preserved exactly.",
            "family": "App Store preview",
            "tone": "Calm, native, focused",
        }
        for index, slide in enumerate(SLIDES)
    ]
    (RUN_DIR / "review-manifest.json").write_text(json.dumps(review_manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
