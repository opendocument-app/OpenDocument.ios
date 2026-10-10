#!/usr/bin/env python3
# Frame App Store captures from fastlane/screenshots into fastlane/framed.
# Requires Pillow. Use --locale to frame one locale.

import argparse
import bisect
import functools
import json
import math
import shutil
import sys
from pathlib import Path

import store_screenshots as store

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("this needs Pillow: python3 -m pip install Pillow")

ROOT = Path(__file__).resolve().parent.parent
FRAMES = ROOT / "fastlane" / "frames"
CAPTURED = ROOT / "fastlane" / "screenshots"
FRAMED = ROOT / "fastlane" / "framed"

# Layout dimensions are fractions of the canvas: y positions use height; sizes use width.
LAYOUT = {
    "iphone": {
        "headline_top": 0.068,
        "headline_size": 0.070,        # before it is shrunk to fit
        "headline_width": 0.86,        # what it is shrunk to fit inside
        "headline_leading": 1.06,
        "screen_left": 0.278,
        "screen_top": 0.265,
        "screen_width": 0.650,         # as wide as it may be; `foot` is the other limit
        "foot": 0.045,                 # ground left under the device, of the height
        # iPhone 17 Pro Max bezel and corner proportions.
        "bezel": 0.0272,               # screen edge to the outside of the body
        "rim": 0.57,                   # how much of that is the black border
        "corner": 0.141,               # screen corner, of the screen's width
        "island": (0.2826, 0.0811),    # the Dynamic Island, of the screen's width
        "island_top": 0.0334,
        # Left buttons as (top, height), relative to body height.
        "buttons": [(0.189, 0.0423), (0.262, 0.0686), (0.349, 0.0686)],
        # the side button, on the right edge
        "buttons_right": [(0.286, 0.1082)],
        "chip_top": 0.440,
        "chip_size": (0.240, 0.147),
        "chip_step": 0.165,
        "chip_text": 0.113,
        "dash_stroke": 0.0056,
        "dash_on": 0.0236,
        "dash_off": 0.0098,
        # Gallery seam heights in canvas fractions; adjacent screens share a seam.
        "seams": [0.150, 0.200, 0.170, 0.215, 0.158, 0.195, 0.176],
        # Routes join the "in" and "out" seams; numeric heights are canvas fractions.
        "routes": [
            [(0.34, "in"), (0.34, "out")],
            [(0.17, "in"), (0.17, "out")],
            [(0.52, "in"), (0.52, "out")],
            [(0.12, "in"), (0.12, 0.248), (0.28, 0.248), (0.28, "out")],
            [(0.26, "in"), (0.26, "out"), (0.60, "out")],
            [(0.15, "in"), (0.15, 0.238), (0.33, 0.238), (0.33, "out")],
        ],
        "radii": [0.078, 0.066, 0.086, 0.062, 0.072, 0.070],
        # Lower decorations attach to chips or enter from the canvas edge.
        "decorations": [
            [("chips", "chips"), ("chips", 0.930), (0.55, 0.930)],
            [(-0.2, 0.700), (0.155, 0.700), (0.155, 0.930), (0.62, 0.930)],
            [("chips", "chips"), ("chips", 0.880), (-0.2, 0.880)],
            [(-0.2, 0.845), (0.185, 0.845), (0.185, 0.640), (0.58, 0.640)],
        ],
    },
    "ipad": {
        "headline_top": 0.068,
        "headline_size": 0.050,
        "headline_width": 0.80,
        "headline_leading": 1.06,
        "screen_left": 0.215,
        "screen_top": 0.250,
        "screen_width": 0.720,
        "foot": 0.055,
        # iPad Pro 13-inch bezel and corner proportions.
        "bezel": 0.0350,
        "rim": 0.86,
        "corner": 0.0174,
        "buttons": [],
        "chip_top": 0.440,
        "chip_size": (0.170, 0.0828),
        "chip_step": 0.0935,
        "chip_text": 0.080,
        "dash_stroke": 0.0040,
        "dash_on": 0.0147,
        "dash_off": 0.0061,
        "seams": [0.162, 0.208, 0.180, 0.224, 0.170, 0.202, 0.186],
        "routes": [
            [(0.30, "in"), (0.30, "out")],
            [(0.115, "in"), (0.115, "out")],
            [(0.46, "in"), (0.46, "out")],
            [(0.08, "in"), (0.08, 0.248), (0.19, 0.248), (0.19, "out")],
            [(0.18, "in"), (0.18, "out"), (0.54, "out")],
            [(0.10, "in"), (0.10, 0.238), (0.225, 0.238), (0.225, "out")],
        ],
        "radii": [0.060, 0.052, 0.068, 0.050, 0.056, 0.054],
        "decorations": [
            [("chips", "chips"), ("chips", 0.930), (0.52, 0.930)],
            [(-0.2, 0.620), (0.105, 0.620), (0.105, 0.930), (0.58, 0.930)],
            [("chips", "chips"), ("chips", 0.880), (-0.2, 0.880)],
            [(-0.2, 0.810), (0.125, 0.810), (0.125, 0.520), (0.54, 0.520)],
        ],
    },
}

# The phone, which is drawn rather than photographed. The rim is read across the
# body's width: bright where the edge turns towards the light, dark on the flat.
BODY = "#08080a"
RIM = ("#c9c9cf", "#6f7076", "#8e8f95", "#7c7d83", "#6a6b71", "#b6b7bd")
# The metal the device wears, off Apple's own bezel. They read as a step in the
# edge rather than as marks on it, which is what they are.
BUTTON = ("#d8d8d6", "#a9a9a7", "#c4c4c2")
GLASS = 96      # how brightly the screen's edge catches the light, of 255

# Black shadow, offset down and right.
SHADOW = (0, 0, 0, 105)
SHADOW_OFFSET = (0.30, 0.65)    # of the bezel, across and down
SHADOW_BLUR = 0.85              # of the bezel


@functools.lru_cache(maxsize=None)
def design():
    text = json.loads((FRAMES / "frames.json").read_text())
    text.pop("_comment", None)
    return text


@functools.lru_cache(maxsize=None)
def font(size, weight):
    """Nunito at one weight. It ships as a single variable file these days."""
    face = ImageFont.truetype(str(FRAMES / design()["font"]), size)
    face.set_variation_by_name(weight)
    return face


def gradient(size, top, bottom):
    """The ground: the same colour top to bottom, a little darker at the foot."""
    width, height = size
    strip = Image.new("RGB", (1, height))
    start = Image.new("RGB", (1, 1), top).getpixel((0, 0))
    end = Image.new("RGB", (1, 1), bottom).getpixel((0, 0))
    for y in range(height):
        share = y / max(1, height - 1)
        strip.putpixel((0, y), tuple(round(start[i] + (end[i] - start[i]) * share) for i in range(3)))

    return strip.resize((width, height)).convert("RGBA")


def rounded_path(points, radius, per_corner=24):
    """A polyline with its corners rounded off, as points to walk along."""
    walk = [points[0]]
    for before, corner, after in zip(points, points[1:], points[2:]):
        into = math.hypot(corner[0] - before[0], corner[1] - before[1])
        out = math.hypot(after[0] - corner[0], after[1] - corner[1])
        r = min(radius, into / 2, out / 2)
        start = (corner[0] + (before[0] - corner[0]) * r / into,
                 corner[1] + (before[1] - corner[1]) * r / into)
        end = (corner[0] + (after[0] - corner[0]) * r / out,
               corner[1] + (after[1] - corner[1]) * r / out)
        walk.append(start)
        for i in range(1, per_corner):
            t = i / per_corner
            # one quadratic bend, with the corner itself as the control point
            walk.append((
                (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * corner[0] + t ** 2 * end[0],
                (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * corner[1] + t ** 2 * end[1],
            ))
        walk.append(end)
    walk.append(points[-1])

    return walk


def dashed(canvas, points, stroke, on, off, colour=(255, 255, 255, 255), phase=0.0):
    """Draw dashes continuously around a path, measuring from its start to avoid rounding drift."""
    reached = [0.0]
    for before, after in zip(points, points[1:]):
        reached.append(reached[-1] + math.hypot(after[0] - before[0], after[1] - before[1]))
    total = reached[-1]
    if not total:
        return

    def at(distance):
        """The point that far along the path."""
        index = max(1, min(len(reached) - 1, bisect.bisect_left(reached, distance)))
        span = reached[index] - reached[index - 1]
        share = 0.0 if not span else (distance - reached[index - 1]) / span
        before, after = points[index - 1], points[index]

        return (before[0] + (after[0] - before[0]) * share,
                before[1] + (after[1] - before[1]) * share)

    draw = ImageDraw.Draw(canvas)
    width = max(1, round(stroke))

    period = on + off
    phase = phase % period
    for number in range(int((total + phase) // period) + 2):
        start = number * period - phase
        end = min(start + on, total)
        if start >= total:
            break
        start = max(start, 0.0)
        if start >= end:
            continue

        # the path's own corners inside this dash, so a dash that lands on a
        # bend is drawn bent rather than as a chord across it
        run = [at(start)]
        run += [point for point, so_far in zip(points, reached) if start < so_far < end]
        run.append(at(end))
        draw.line(run, fill=colour, width=width, joint="curve")


def squircle(box, radius, exponent=5.0, per_corner=40):
    """Return a rounded rectangle with superellipse corners."""
    x0, y0, x1, y1 = box
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    points = []

    # Walk superellipse corners clockwise, reversing alternate quadrants.
    for (cx, cy), sx, sy in (((x1 - r, y1 - r), 1, 1), ((x0 + r, y1 - r), -1, 1),
                             ((x0 + r, y0 + r), -1, -1), ((x1 - r, y0 + r), 1, -1)):
        for step in range(per_corner + 1):
            share = step / per_corner if sx * sy > 0 else 1 - step / per_corner
            angle = math.pi / 2 * share
            points.append((
                cx + sx * r * math.cos(angle) ** (2 / exponent),
                cy + sy * r * math.sin(angle) ** (2 / exponent),
            ))

    return points


def outset(points, distance):
    """Offset an outline along its normals to preserve a constant border width."""
    walked = list(zip(points, points[1:] + points[:1]))
    facing = 1.0 if sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in walked) > 0 else -1.0
    moved = []

    for index, (x, y) in enumerate(points):
        (ax, ay), (bx, by) = points[index - 1], points[(index + 1) % len(points)]
        run, rise = bx - ax, by - ay
        length = math.hypot(run, rise) or 1.0
        moved.append((x + facing * rise / length * distance, y - facing * run / length * distance))

    return moved


def stencil(size, points, supersample=3):
    """An antialiased mask of one shape. Pillow's polygon has hard edges, so it
    is drawn large and shrunk, which is cheaper than it sounds on a mask."""
    big = Image.new("L", (size[0] * supersample, size[1] * supersample), 0)
    ImageDraw.Draw(big).polygon([(x * supersample, y * supersample) for x, y in points], fill=255)

    return big.resize(size, Image.LANCZOS)


def chamfer(share):
    """Return the metal color across the bezel, from outside edge to black."""
    stops = ((0.00, 109), (0.19, 157), (0.40, 190), (0.64, 235), (0.79, 195), (1.00, 120))
    place = bisect.bisect_right([at for at, _ in stops], share)
    if place == 0:
        return (stops[0][1],) * 3
    if place == len(stops):
        return (stops[-1][1],) * 3

    (before, low), (after, high) = stops[place - 1], stops[place]
    level = round(low + (high - low) * (share - before) / (after - before))

    return (level,) * 3


def brushed(size, colours):
    """The rim: a metal that catches the light differently across its width."""
    width, height = size
    strip = Image.new("RGB", (len(colours), 1))
    for index, colour in enumerate(colours):
        strip.putpixel((index, 0), Image.new("RGB", (1, 1), colour).getpixel((0, 0)))

    return strip.resize((width, height), Image.BICUBIC)


def crossing(layout, order, size):
    """The line this screen hands on: in at one height, out at the next."""
    width, height = size
    seams = layout["seams"]
    enters = seams[order % len(seams)] * height
    leaves = seams[(order + 1) % len(seams)] * height
    route = layout["routes"][order % len(layout["routes"])]

    def down(y):
        return enters if y == "in" else leaves if y == "out" else y * height

    return (
        [(-0.2 * width, enters)]
        + [(x * width, down(y)) for x, y in route]
        + [(1.2 * width, leaves)]
    )


def walked(points):
    """How far a path runs, so the next one can pick the dashes up."""
    return sum(
        math.hypot(after[0] - before[0], after[1] - before[1])
        for before, after in zip(points, points[1:])
    )


def phone(canvas, shot, layout):
    """Composite a capture inside a device frame, with bezel, buttons and shadow."""
    width, height = canvas.size
    bezel = layout["bezel"] * width          # screen edge to the outside of the body
    rim = bezel * layout["rim"]              # how much of that is metal

    left, top = layout["screen_left"] * width, layout["screen_top"] * height

    # Fit the device within screen_width while preserving the foot margin.
    standing = (height - layout["foot"] * height) - top - bezel
    screen_width = min(layout["screen_width"] * width, standing * shot.width / shot.height)
    screen_height = screen_width * shot.height / shot.width

    screen = (left, top, left + screen_width, top + screen_height)
    corner = layout["corner"] * screen_width

    body = (screen[0] - bezel, screen[1] - bezel, screen[2] + bezel, screen[3] + bezel)

    # its own canvas, with room to the left for the buttons that stand proud
    margin = round(bezel * 3)
    origin = (round(body[0]) - margin, round(body[1]) - margin)
    size = (round(body[2]) - origin[0] + margin, round(body[3]) - origin[1] + margin)
    here = lambda box: tuple(v - origin[i % 2] for i, v in enumerate(box))

    device = Image.new("RGBA", size, (0, 0, 0, 0))

    # the buttons first, so the body's own edge covers where they meet it
    metal = brushed(size, BUTTON)
    buttons = Image.new("L", size, 0)
    draw = ImageDraw.Draw(buttons)
    stand = screen_width * 0.0061          # how far a button stands proud, 2.7pt
    tall_as = body[3] - body[1]
    for edge, keys in ((here(body)[0], layout["buttons"]),
                       (here(body)[2], layout.get("buttons_right", []))):
        for at_height, tall in keys:
            y = here(body)[1] + tall_as * at_height
            draw.rounded_rectangle((edge - stand, y, edge + stand, y + tall_as * tall),
                                   radius=stand * 0.55, fill=255)
    device.paste(metal, (0, 0), buttons)

    # Offset the screen outline to keep the bezel width constant.
    face = squircle(here(screen), corner)
    outline = outset(face, bezel)

    # Shade concentric bezel rings with chamfer().
    band = bezel - rim
    lit = Image.new("RGB", size, chamfer(1.0))
    rings = ImageDraw.Draw(lit)
    steps = max(8, round(band))
    for step in range(steps + 1):
        share = step / steps
        rings.polygon(outset(face, bezel - band * share), fill=chamfer(share))

    device.paste(lit, (0, 0), stencil(size, outline))

    # the black surround the glass sits in, and then the glass
    device.paste(Image.new("RGB", size, BODY), (0, 0), stencil(size, outset(face, rim)))

    fitted = shot.resize((round(screen_width), round(screen_height)), Image.LANCZOS).convert("RGBA")
    inside = here(screen)
    device.paste(fitted, (round(inside[0]), round(inside[1])),
                 stencil(size, face).crop(
                     (round(inside[0]), round(inside[1]),
                      round(inside[0]) + fitted.width, round(inside[1]) + fitted.height)))

    # Highlight the glass edge to separate dark screens from the bezel.
    hair = max(1.0, screen_width * 0.0012)
    halo = ImageChops.subtract(
        stencil(size, face), stencil(size, outset(face, -hair))
    ).point(lambda level: level * GLASS // 255)
    device.paste(Image.new("RGB", size, "white"), (0, 0), halo)

    # the pill the camera sits in, over the gap the status bar leaves for it
    if layout.get("island"):
        island_width, island_height = (share * screen_width for share in layout["island"])
        middle = (inside[0] + inside[2]) / 2
        island_top = inside[1] + layout["island_top"] * screen_width
        ImageDraw.Draw(device).rounded_rectangle(
            (middle - island_width / 2, island_top, middle + island_width / 2, island_top + island_height),
            radius=island_height / 2, fill=BODY)

    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow.paste(Image.new("RGB", size, SHADOW[:3]), (0, 0),
                 stencil(size, outline).point(lambda v: v * SHADOW[3] // 255))
    canvas.alpha_composite(
        shadow.filter(ImageFilter.GaussianBlur(bezel * SHADOW_BLUR)),
        (origin[0] + round(bezel * SHADOW_OFFSET[0]), origin[1] + round(bezel * SHADOW_OFFSET[1])))
    canvas.alpha_composite(device, origin)


def headline(canvas, lines, layout):
    """Fit two centered headline lines to the available width."""
    width, height = canvas.size
    size = round(layout["headline_size"] * width)
    allowed = layout["headline_width"] * width
    weights = ("Regular", "Bold")
    draw = ImageDraw.Draw(canvas)

    while size > 8:
        faces = [font(size, weight) for weight in weights]
        if max(draw.textlength(line, font=face) for line, face in zip(lines, faces)) <= allowed:
            break
        size -= 2

    leading = size * layout["headline_leading"]
    y = layout["headline_top"] * height
    for line, face in zip(lines, faces):
        draw.text((width / 2, y), line, font=face, fill="white", anchor="ma")
        y += leading


def chips(canvas, names, palette, layout):
    """The odt/ods/odp tabs, running off the left edge as the design has them."""
    width, height = canvas.size
    least, chip_height = (share * width for share in layout["chip_size"])
    face = font(round(layout["chip_text"] * width), "Bold")
    draw = ImageDraw.Draw(canvas)

    # Size all chips to the widest format name, keeping their width consistent across screens.
    padding = layout["chip_text"] * width * 0.42
    chip_width = max([least] + [draw.textlength(name, font=face) + 2 * padding for name in palette])

    for index, name in enumerate(names):
        top = layout["chip_top"] * height + layout["chip_step"] * width * index
        draw.rectangle((-2, top, chip_width, top + chip_height), fill=palette[name])
        draw.text((chip_width / 2, top + chip_height / 2), name, font=face, fill="white", anchor="mm")

    return chip_width


def frame(shot, screen, locale, spec, order=0):
    """One picture: ground, decorations, phone, tabs, headline."""
    kind = store.device(*shot.size)
    if kind is None:
        raise ValueError(f"{shot.size[0]}x{shot.size[1]} is no size the store takes")

    layout = LAYOUT[kind]
    width, height = shot.size
    canvas = gradient(shot.size, *spec["backgrounds"][screen["background"]])

    on, off = layout["dash_on"] * width, layout["dash_off"] * width
    stroke = layout["dash_stroke"] * width
    radius = layout["radii"][order % len(layout["radii"])] * width

    # Continue the dash phase from preceding screens.
    before = sum(walked(crossing(layout, index, shot.size)) for index in range(order))
    dashed(
        canvas, rounded_path(crossing(layout, order, shot.size), radius), stroke, on, off, phase=before
    )

    lower = layout["decorations"][order % len(layout["decorations"])]

    # a line hanging off tabs that are not there reads as a line starting in mid
    # air, so a screen without them takes one that comes in from the edge
    if not screen["chips"] and any("chips" in point for point in lower):
        lower = next(
            points for points in layout["decorations"] if not any("chips" in p for p in points)
        )

    # "chips" is the middle of the tabs, so the line runs behind however many
    # there are and comes out underneath
    placed = [
        (layout["chip_size"][0] / 2 if x == "chips" else x,
         layout["chip_top"] if y == "chips" else y)
        for x, y in lower
    ]
    dashed(
        canvas,
        rounded_path([(x * width, y * height) for x, y in placed], radius),
        stroke, on, off,
    )

    phone(canvas, shot, layout)
    chips(canvas, screen["chips"], spec["chips"], layout)
    headline(canvas, copy(screen, locale), layout)

    return canvas.convert("RGB")


def copy(screen, locale):
    """This screen's two lines in that language, or the English if it has none."""
    lines = screen["headline"].get(locale) or screen["headline"][store.FALLBACK]

    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description="Frame the captured App Store screenshots.")
    parser.add_argument("--captured", metavar="DIR", default=CAPTURED,
                        help=f"where the capture run wrote (default {CAPTURED.relative_to(ROOT)})")
    parser.add_argument("--framed", metavar="DIR", default=FRAMED,
                        help=f"where to write the framed set (default {FRAMED.relative_to(ROOT)})")
    parser.add_argument("--locale", action="append",
                        help="only this locale, repeatable; default is everything captured")
    args = parser.parse_args(argv)

    spec = design()
    screens = {screen["name"]: screen for screen in spec["screens"]}
    captured, framed = Path(args.captured), Path(args.framed)

    wanted = args.locale or store.languages()
    written = 0

    for locale in wanted:
        folder = captured / locale
        if not folder.is_dir():
            print(f"{locale}: no {folder}", file=sys.stderr)
            continue

        # emptied rather than written over, so a screen that was renamed does
        # not leave yesterday's picture behind for the release to find
        out = framed / locale
        shutil.rmtree(out, ignore_errors=True)
        out.mkdir(parents=True, exist_ok=True)

        # Lite's edit is framed as the screen it replaces: the same place,
        # and the same headline, which is true of both apps
        replaces = {lite: screen for screen, lite in store.LITE.items()}

        for path in sorted(folder.glob("*.png")):
            taken = next((n for n in store.CAPTURED if path.stem.endswith(n)), None)
            name = replaces.get(taken, taken)
            if name not in screens:
                continue

            with Image.open(path) as shot:
                # a capture of a device the store does not ask for is left where
                # it is; store_screenshots.py is what says the set is wrong
                if store.device(*shot.size) is None:
                    print(f"{locale}: skipping {path.name}, {shot.width}x{shot.height} is no "
                          "size the store takes", file=sys.stderr)
                    continue

                picture = frame(
                    shot.convert("RGB"), screens[name], locale, spec, order=list(screens).index(name)
                )

            picture.save(out / path.name)
            written += 1

    print(f"framed {written} screenshots into {framed}")

    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
