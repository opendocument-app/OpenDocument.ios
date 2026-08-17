#!/usr/bin/env python3
#
# Puts the captured screenshots into the picture the store shows: the app on a
# phone, on a coloured ground, under a line of copy in that locale's language.
#
#   scripts/frame-screenshots.py                    frame the whole capture
#   scripts/frame-screenshots.py --locale en-US     one locale, for a look
#
# `fastlane ios screenshots` takes the raw captures into fastlane/screenshots;
# this reads them and writes the framed set to fastlane/framed, which is what
# `scripts/store_screenshots.py` then checks and stages. The raw set is left
# alone, so a framing change costs a rerun of this and not of the simulators.
#
# Nothing here is drawn from an image file. Every part of the design is a
# rounded rectangle, a plain rectangle or a line of text, so it is all in
# `fastlane/frames/frames.json` and in the numbers below - which is also what
# lets one canvas size become another. The only asset is the font.
#
# Needs Pillow, which is the one thing in this repository's scripts that is not
# in the standard library:
#
#   python3 -m pip install Pillow

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

# The design, as fractions of the canvas rather than pixels, because the canvas
# is whatever the capture is - 1320x2868 today and something else after the next
# device.
#
# How far down something sits is a fraction of the height; how big it is, and
# how far across, is a fraction of the width. So a taller canvas gives
# everything more room without stretching any of it.
#
# The proportions came off the 2020 artwork at 1242x2208. A phone is a good deal
# taller than that now, so the phone is anchored by its top left corner and left
# to run off the bottom and the right - which is what the original did too, only
# by less.
LAYOUT = {
    "iphone": {
        "headline_top": 0.068,
        "headline_size": 0.070,        # before it is shrunk to fit
        "headline_width": 0.86,        # what it is shrunk to fit inside
        "headline_leading": 1.06,
        "screen_left": 0.280,
        "screen_top": 0.235,
        "screen_width": 0.780,
        # An iPhone 17 Pro Max, from its published dimensions: a 440pt screen
        # inside a 78.0mm body, which leaves 2.54mm - 15.3pt - of black border
        # and aluminium on every side, and a 62pt display corner.
        "bezel": 0.0272,               # screen edge to the outside of the body
        "rim": 0.57,                   # how much of that is the black border
        "corner": 0.141,               # screen corner, of the screen's width
        "island": (0.2826, 0.0811),    # the Dynamic Island, of the screen's width
        "island_top": 0.0334,
        # The action button and the two volume keys: (how far down the body,
        # how long), both of the body's height. Measured off Apple's own bezel
        # artwork, which is also where the bezel, the island and the corner
        # come from - so all of it is the device rather than a guess at it.
        "buttons": [(0.189, 0.0423), (0.262, 0.0686), (0.349, 0.0686)],
        # the side button, on the right edge, off the canvas where the phone
        # sits today. Kept so the device is described whole: what is drawn
        # follows from where it is placed, not the other way round.
        "buttons_right": [(0.286, 0.1082)],
        "chip_top": 0.440,
        "chip_size": (0.240, 0.147),
        "chip_step": 0.165,
        "chip_text": 0.113,
        "dash_stroke": 0.0056,
        "dash_on": 0.0236,
        "dash_off": 0.0098,
        # Each decoration is a line that comes in from off the canvas, turns a
        # corner and leaves again - one corner of a rounded rectangle far bigger
        # than the picture. Points are (x, y) in canvas fractions, and a point
        # past 1 is off the edge on purpose. A y of "chips" starts the line at
        # the top of the tabs, so it runs behind however many there are and
        # comes out underneath: anchored to a number instead, a screen with one
        # tab leaves the line starting in mid air below it.
        # The line crossing every screen. Each picture takes it in at the height
        # the one before let it out at, steps it to a new height somewhere along
        # the way, and hands it on - so no two screens carry the same line and
        # the gallery still reads as one. There is one height per seam, which is
        # one more than there are screens.
        #
        # Every height sits between the foot of the headline and the top of the
        # device, the only band that is neither written on nor covered up.
        "seams": [0.150, 0.200, 0.170, 0.215, 0.158, 0.195, 0.176],
        # What the line does between the two seams it has to join. "in" is the
        # height it arrived at and "out" the one it has to leave at; anything
        # else is a height of its own. Only the left quarter is free below the
        # band - the device covers the rest - so that is where a line can wander
        # before it has to come back up and go.
        # A step and, on some, a shallow dip into the left column before it. Kept
        # shallow on purpose: the line is there to tie the pictures together, and
        # one that wanders far down the page competes with what it is framing.
        # One step, at a different place on each. Two of them dip a little
        # further first, and only a little: the line is there to tie the
        # pictures together, and anything more reads as decoration for its own
        # sake across the top of every screen.
        "routes": [
            [(0.34, "in"), (0.34, "out")],
            [(0.17, "in"), (0.17, "out")],
            [(0.52, "in"), (0.52, "out")],
            [(0.12, "in"), (0.12, 0.248), (0.28, 0.248), (0.28, "out")],
            [(0.26, "in"), (0.26, "out"), (0.60, "out")],
            [(0.15, "in"), (0.15, 0.238), (0.33, 0.238), (0.33, "out")],
        ],
        "radii": [0.078, 0.066, 0.086, 0.062, 0.072, 0.070],
        # The lower line. Some of these hang off the tabs, some come in from the
        # left edge instead - picking up where the picture before let its own
        # line disappear behind the device - and one leaves to the left again.
        # A screen with no tabs takes one of the ones that does not need them.
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
        # Off the right edge by a little, as the phone is, but only a little:
        # an iPad's status icons sit within a fiftieth of its own edge, so any
        # more of a bleed takes the battery with it. The phone can afford 6%
        # because the Dynamic Island pushes its icons well inboard.
        "screen_left": 0.188,
        "screen_top": 0.245,
        "screen_width": 0.825,
        # An iPad Pro 13-inch, likewise: a 1032pt screen in a 215.5mm body is
        # 8.44mm - 43.8pt - of border, near three times the phone's, and the
        # display corner is 18pt where the phone's is 62. Nothing on the left
        # edge either: its buttons are all on the top one.
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

# The shadow the device casts. Black rather than a colour of its own, which was
# mixed for the green ground and went muddy on the orange one, and offset down
# and right instead of sitting square behind the body, where the body covers it.
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
    """Lays dashes along a path, so a dash carries on around a corner.

    Counted out from the start of the path rather than accumulated as it walks,
    because a step that rounds to nothing next to a distance already travelled
    is a step that never arrives.
    """
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
    """A rounded rectangle whose corners are superellipse quadrants.

    Apple's corners are a continuous curve rather than a circular arc: the
    curvature eases into the straight edge instead of starting at full bend. A
    circle reads as an Android phone, or as a 2015 one. Exponent 5 is close
    enough that nobody looks twice.
    """
    x0, y0, x1, y1 = box
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    points = []

    # each corner as (centre, x sign, y sign), going clockwise from bottom right.
    # Two of the four are walked backwards, so that every quadrant leaves off
    # where the next one starts and the outline closes.
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
    """The same outline, moved out by a fixed distance along its own normals.

    A squircle grown by raising its radius is not parallel to the one it grew
    from: the gap between the two opens up around the corner and closes down
    the sides. Drawn that way a bezel is visibly fatter at the corners than
    along the edges, which is the first thing anybody who owns the phone sees.
    """
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
    """The metal's colour that far across the band, outside edge to black.

    Read off Apple's own bezel: the edge is turned, so it comes in at a middling
    grey, climbs to a highlight about two thirds of the way in and falls away
    again. Lit along its length like this it reads as a rolled edge; filled
    flat, as a grey stripe.
    """
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
    """The device: the capture behind glass, in a metal body.

    Drawn rather than pasted from a mockup, so it is the shape of whatever was
    captured. A frame downloaded for one device is the wrong shape for the next
    one, and the sets on offer stop at a generation the store no longer asks for.

    Built in its own image and composited once, so the parts can be masked
    against each other without the ground showing through the seams.
    """
    width, height = canvas.size
    screen_width = layout["screen_width"] * width
    screen_height = screen_width * shot.height / shot.width
    left, top = layout["screen_left"] * width, layout["screen_top"] * height
    screen = (left, top, left + screen_width, top + screen_height)

    bezel = layout["bezel"] * width          # screen edge to the outside of the body
    rim = bezel * layout["rim"]              # how much of that is metal
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

    # Every edge is the screen's own outline moved out, so the black border and
    # the metal around it are the same width the whole way round - which is what
    # they are on the device, and not what a bigger squircle would give.
    face = squircle(here(screen), corner)
    outline = outset(face, bezel)

    # The metal, lit across the band's own width rather than the body's: the
    # band is filled as rings, each the colour ``chamfer`` gives for how far in
    # it sits, so the highlight follows the edge the whole way round.
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

    # The hairline where the glass meets the surround, which a real device
    # catches the light along. Without it a screen that is dark at the top - the
    # intro is - runs into the black bezel, and the two read as one fat border
    # off a phone from 2016.
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
    """Two lines, light over bold, centred and shrunk until they fit.

    Fitted rather than set at a fixed size because the same sentence is a third
    longer in German than in English, and a line that runs off the picture is
    worse than one set a little smaller.
    """
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

    # As wide as the longest word in the whole design needs, and no narrower
    # than the design's own tab: "odt" is three letters and "docx" is four, and
    # a tab cut to fit the shorter one loses the end of the longer.
    #
    # Measured across every format rather than the two or three on this screen,
    # so the tabs are one length through the gallery. Cut to fit each screen
    # they step in and out as the reader swipes, which reads as the pictures
    # having been made at different times.
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

    # The crossing line, and the dash pattern picked up where the screens before
    # it left off, so the dashes carry on across the gallery rather than
    # restarting at every picture.
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

        for path in sorted(folder.glob("*.png")):
            name = next((n for n in screens if path.stem.endswith(n)), None)
            if name is None:
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
