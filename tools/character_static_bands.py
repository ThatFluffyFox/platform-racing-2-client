#!/usr/bin/env python3
"""Record where each character part's fixed art sits relative to its colour layers.

Flash part clips interleave fixed art with the two colour clips. Top to bottom a
head is, for example: outlines and details, `colorMC2` (epic colour), the
`static_color` layer, `colorMC` (primary colour). The Animate SVG export flattens
all fixed layers into one static.svg, which the port drew between the primary and
epic colours, so the epic colour covered outlines that Flash draws above it.

static.svg keeps one top-level group per XFL layer, bottom to top. This tool
counts, for every part, how many of those groups lie below `colorMC` ("under")
and between `colorMC` and `colorMC2` ("middle"); the rest lie above the epic
colour. The counts are written to each rig variant as `fixedBands`.

When the middle band is the same artwork as the epic colour clip's frame (the
part's uncoloured epic area), `middleHiddenByEpic` is set: Flash's renderer lets
the topmost of two identical shapes win each sub-pixel, so that art never shows
while an epic colour is on. Browsers blend both shapes' edges instead, which
tinted thin epic areas with the uncoloured art, so the port hides it then.

    python3 tools/character_static_bands.py                 # patch art/rigs/character-rig.json
    python3 tools/character_static_bands.py --check
    python3 tools/character_static_bands.py --library PATH  # XFL LIBRARY directory
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LIBRARY = ROOT / "flash/platform-racing-2-xfl/LIBRARY"
RIG = ROOT / "art/rigs/character-rig.json"
ART = ROOT / "art/svg/character"
XFL = "{http://ns.adobe.com/xfl/2008/}"
SVG = "{http://www.w3.org/2000/svg}"
SOURCES = {
    "head": "Parts/Heads/headsMC.xml",
    "body": "Parts/Bodies/bodyMC.xml",
    "feet": "Parts/Feet/footMC.xml",
    "hat": "Parts/Hats/hatsMC.xml",
}


def layer_frames(layer: ET.Element) -> list[tuple[int, int, ET.Element]]:
    frames = []
    for frame in layer.findall(f"{XFL}frames/{XFL}DOMFrame"):
        start = int(frame.get("index", "0"))
        frames.append((start, int(frame.get("duration", "1")), frame))
    return frames


def frame_at(layer: ET.Element, index: int) -> ET.Element | None:
    for start, duration, frame in layer_frames(layer):
        if start <= index < start + duration:
            return frame
    return None


def classify(frame: ET.Element) -> str | None:
    elements = frame.find(f"{XFL}elements")
    if elements is None or len(elements) == 0:
        return None
    names = {element.get("name") for element in elements}
    if "colorMC2" in names:
        return "C2"
    if "colorMC" in names:
        return "C1"
    return "S"


def signature(frame: ET.Element) -> tuple:
    """Comparable description of a frame's artwork (instances and shapes)."""
    elements = frame.find(f"{XFL}elements")
    result = []
    for element in elements if elements is not None else []:
        if element.tag == f"{XFL}DOMShape":
            result.append(("shape", "".join(edge.get("edges", "") for edge in element.iter(f"{XFL}Edge"))))
        else:
            matrix = element.find(f"{XFL}matrix/{XFL}Matrix")
            result.append((element.get("libraryItemName"), tuple(sorted(matrix.attrib.items())) if matrix is not None else ()))
    return tuple(result)


_parsed: dict[Path, ET.Element] = {}


def parse(path: Path) -> ET.Element:
    if path not in _parsed:
        _parsed[path] = ET.parse(path).getroot()
    return _parsed[path]


def timeline_layers(root: ET.Element) -> list[ET.Element]:
    return [layer for layer in root.findall(f".//{XFL}DOMTimeline/{XFL}layers/{XFL}DOMLayer")
            if layer.get("layerType") not in ("guide", "folder")]


def layer_kinds(library: Path, source: Path, index: int) -> tuple[list[str], list[tuple], set[tuple]]:
    """Kinds and artwork of the exported, non-empty layers at a frame, top to bottom,
    plus the artwork of the epic colour clip at the same part frame."""
    kinds, signatures, epic = [], [], set()
    for layer in timeline_layers(parse(source)):
        frame = frame_at(layer, index)
        kind = classify(frame) if frame is not None else None
        if kind is None:
            continue
        kinds.append(kind)
        signatures.append(signature(frame))
        if kind == "C2":
            for element in frame.find(f"{XFL}elements"):
                if element.get("name") == "colorMC2":
                    clip = library / (element.get("libraryItemName") + ".xml")
                    for clip_layer in timeline_layers(parse(clip)):
                        clip_frame = frame_at(clip_layer, index)
                        if clip_frame is not None and classify(clip_frame):
                            epic.add(signature(clip_frame))
    return kinds, signatures, epic


def svg_layer_groups(path: Path) -> int | None:
    root = ET.parse(path).getroot()
    groups = [child for child in root if child.tag == f"{SVG}g"]
    if len(groups) != 1:
        return None
    return sum(1 for child in groups[0] if child.tag == f"{SVG}g")


def bands(library: Path) -> tuple[dict[str, dict[str, dict[str, int]]], list[str]]:
    result: dict[str, dict[str, dict[str, int]]] = {}
    warnings = []
    for kind, relative in SOURCES.items():
        source = library / relative
        result[kind] = {}
        for directory in sorted((ART / kind).iterdir()):
            prefix = directory.name.split("_", 1)[0]
            static = directory / "static.svg"
            if not prefix.isdigit() or not static.exists():
                continue
            part_id = int(prefix)
            kinds, signatures, epic = layer_kinds(library, source, part_id - 1)
            if "C2" not in kinds or "C1" not in kinds or kinds.index("C2") > kinds.index("C1"):
                continue
            c2, c1 = kinds.index("C2"), kinds.index("C1")
            middle = kinds[c2 + 1:c1].count("S")
            under = kinds[c1 + 1:].count("S")
            if middle == 0 and under == 0:
                continue
            exported = svg_layer_groups(static)
            if exported != kinds.count("S"):
                warnings.append(f"{kind} {part_id}: static.svg has {exported} layer groups, XFL has {kinds.count('S')}; left as one band")
                continue
            record = {"under": under, "middle": middle}
            middle_art = [signatures[i] for i in range(c2 + 1, c1) if kinds[i] == "S"]
            if middle_art and all(art in epic for art in middle_art):
                record["middleHiddenByEpic"] = True
            result[kind][str(part_id)] = record
    return result, warnings


def apply(rig: dict, computed: dict) -> None:
    for kind, part in rig["parts"].items():
        for variant in part["variants"]:
            variant.pop("fixedBands", None)
            found = computed.get(kind, {}).get(str(variant["id"]))
            # Animated channels and overlays replace static.svg; their frames keep one band.
            if found and variant["fixed"].endswith("/static.svg") and "channelAnimations" not in variant:
                variant["fixedBands"] = found


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    computed, warnings = bands(args.library)
    for warning in warnings:
        print("warning:", warning, file=sys.stderr)
    text = RIG.read_text()
    rig = json.loads(text)
    apply(rig, computed)
    updated = json.dumps(rig, indent=2) + ("\n" if text.endswith("\n") else "")
    if args.check:
        if updated != text:
            sys.exit("character-rig.json fixedBands are stale (run python3 tools/character_static_bands.py)")
        return
    RIG.write_text(updated)
    total = sum(len(parts) for parts in computed.values())
    print(f"Wrote fixedBands for {total} parts to {RIG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
