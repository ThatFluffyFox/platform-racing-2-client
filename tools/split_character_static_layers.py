#!/usr/bin/env python3
"""Split each character part's static SVG at its colour layers, as stacked in the XFL.

A part MovieClip frame stacks art layers around its two tinted instances,
colorMC (primary) and colorMC2 (secondary). Animate's static export hides those
two layers and flattens everything else into static.svg, so the runtime could
only draw it at one depth and drew outlines and shading below the secondary
colour. This tool reads the part frame's layer stack and splits static.svg into:

  static_below.svg  art under colorMC
  static.svg        art between colorMC and colorMC2
  static_above.svg  art over colorMC2

Animate writes one top-level group per frame element, bottom to top, with a
DOMGroup expanded to one group per member, so the split is by group count; any
part whose group count does not match the XFL is reported and left alone.
Re-running is safe: existing pieces are joined back before splitting.

  python3 tools/split_character_static_layers.py [--xfl DIR] [--check]
"""

from __future__ import annotations

import argparse
import copy
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/svg/character"
XFL = "{http://ns.adobe.com/xfl/2008/}"
SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
SVG = "{" + SVG_NS + "}"
SOURCES = {
    "head": "Parts/Heads/headsMC.xml",
    "body": "Parts/Bodies/bodyMC.xml",
    "feet": "Parts/Feet/footMC.xml",
    "hat": "Parts/Hats/hatsMC.xml",
}
PIECES = ("static_below.svg", "static.svg", "static_above.svg")
# hatsMC layer that tools/generate_character_hat_overlays.py animates separately.
ANIMATED_HAT_LAYERS = ("Layer 3",)
REF = re.compile(r"#([A-Za-z_][\w.\-]*)")

ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)


def leaf_count(element: ET.Element) -> int:
    if element.tag == f"{XFL}DOMGroup":
        members = element.find(f"{XFL}members")
        return sum(leaf_count(child) for child in members) if members is not None else 0
    return 1


def frame_at(layer: ET.Element, frame: int) -> ET.Element | None:
    frames = layer.find(f"{XFL}frames")
    if frames is None:
        return None
    for candidate in frames:
        start = int(candidate.get("index", "0"))
        if start <= frame < start + int(candidate.get("duration", "1")):
            return candidate
    return None


def frame_bands(source: ET.Element, frame: int, excluded_layers: tuple[str, ...] = (), expand_groups: bool = True) -> list[str] | None:
    """Band ('below' / 'between' / 'above') of each static leaf, bottom to top."""
    layers = list(source.find(f".//{XFL}DOMTimeline/{XFL}layers"))
    stack: list[str] = []
    for layer in reversed(layers):
        if layer.get("layerType") in ("guide", "folder", "mask") or layer.get("name") in excluded_layers:
            continue
        current = frame_at(layer, frame)
        elements = current.find(f"{XFL}elements") if current is not None else None
        if elements is None:
            continue
        for element in elements:
            name = element.get("name")
            if name == "colorMC":
                stack.append("P")
            elif name == "colorMC2":
                stack.append("S")
            else:
                stack.extend("x" * (leaf_count(element) if expand_groups else 1))
    if "P" not in stack:
        return None
    bands = []
    seen_primary = seen_secondary = False
    for entry in stack:
        if entry == "P":
            seen_primary = True
        elif entry == "S":
            seen_secondary = True
        else:
            bands.append("above" if seen_secondary else "between" if seen_primary else "below")
    return bands


def content_group(svg: ET.Element) -> ET.Element:
    groups = [child for child in svg if child.tag == f"{SVG}g"]
    if len(groups) != 1:
        raise ValueError("expected one top-level content group")
    return groups[0]


def references(element: ET.Element) -> set[str]:
    found = set()
    for node in element.iter():
        for value in node.attrib.values():
            found.update(REF.findall(value))
    return found


def build(template: ET.Element, defs: dict[str, ET.Element], children: list[ET.Element]) -> ET.Element:
    svg = copy.deepcopy(template)
    for child in list(svg):
        svg.remove(child)
    wrapper = copy.deepcopy(content_group(template))
    for child in list(wrapper):
        wrapper.remove(child)
    for child in children:
        wrapper.append(copy.deepcopy(child))
    wanted: set[str] = set()
    pending = references(wrapper)
    while pending:
        ref = pending.pop()
        if ref in wanted or ref not in defs:
            continue
        wanted.add(ref)
        pending |= references(defs[ref])
    defs_element = ET.SubElement(svg, f"{SVG}defs")
    for ref, element in defs.items():
        if ref in wanted:
            defs_element.append(copy.deepcopy(element))
    if not len(defs_element):
        svg.remove(defs_element)
    svg.append(wrapper)
    ET.indent(svg, space="")
    return svg


def split_part(directory: Path, bands: list[str], check: bool) -> str:
    present = [directory / name for name in PIECES if (directory / name).exists()]
    trees = {path.name: ET.parse(path).getroot() for path in present}
    template = trees["static.svg"]
    defs: dict[str, ET.Element] = {}
    children: list[ET.Element] = []
    for name in PIECES:
        if name not in trees:
            continue
        for defs_element in trees[name].findall(f"{SVG}defs"):
            for element in defs_element:
                # A reference may name an element nested inside a def; keep the whole def.
                for node in element.iter():
                    if node.get("id"):
                        defs.setdefault(node.get("id"), element)
        children.extend(content_group(trees[name]))
    if len(children) != len(bands):
        return f"skipped: {len(children)} SVG groups, {len(bands)} XFL elements"
    expected = {name: [c for c, b in zip(children, bands) if b == band] for name, band in zip(PIECES, ("below", "between", "above"))}
    if check:
        for name in PIECES:
            actual = len(content_group(trees[name])) if name in trees else 0
            if actual != len(expected[name]) or (name != "static.svg" and name in trees and actual == 0):
                return f"stale: {name} has {actual} groups, expected {len(expected[name])}"
        return "ok"
    for name in PIECES:
        path = directory / name
        if name != "static.svg" and not expected[name]:
            if path.exists():
                path.unlink()
            continue
        svg = build(template, defs, expected[name])
        text = ET.tostring(svg, encoding="unicode")
        path.write_text('<?xml version="1.0" encoding="utf-8"?>\n' + text + "\n", encoding="utf-8")
    return "split " + "/".join(str(len(expected[name])) for name in PIECES)


def split_composed_base(directory: Path, bands: list[str], check: bool) -> str:
    """Split a tools/generate_character_hat_overlays.py base: one child per element, defs inline."""
    pieces = ("static_base.svg", "static_base_above.svg")
    trees = {name: ET.parse(directory / name).getroot() for name in pieces if (directory / name).exists()}
    holders = {name: tree.find(f"{SVG}g") for name, tree in trees.items()}
    children = [child for name in pieces if name in holders for child in holders[name]]
    if len(children) != len(bands) or "below" in bands:
        return f"skipped: {len(children)} base groups, bands {bands}"
    expected = {"static_base.svg": [c for c, b in zip(children, bands) if b == "between"],
                "static_base_above.svg": [c for c, b in zip(children, bands) if b == "above"]}
    if check:
        for name in pieces:
            actual = len(holders[name]) if name in holders else 0
            if actual != len(expected[name]) or (name != "static_base.svg" and name in holders and actual == 0):
                return f"stale: {name} has {actual} groups, expected {len(expected[name])}"
        return "ok"
    template = trees["static_base.svg"]
    for name in pieces:
        path = directory / name
        if name != "static_base.svg" and not expected[name]:
            if path.exists():
                path.unlink()
            continue
        svg = copy.deepcopy(template)
        holder = svg.find(f"{SVG}g")
        for child in list(holder):
            holder.remove(child)
        for child in expected[name]:
            holder.append(copy.deepcopy(child))
        path.write_text("<?xml version='1.0' encoding='utf-8'?>\n" + ET.tostring(svg, encoding="unicode") + "\n", encoding="utf-8")
    return "split base " + "/".join(str(len(expected[name])) for name in pieces)


COVERED = "static_under_secondary.svg"
XLINK_HREF = "{" + XLINK_NS + "}href"
MATRIX = re.compile(r"matrix\(\s*([^)]*)\)")


def multiply(m, n):
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2, a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def placed_paths(svg: ET.Element) -> list[tuple[ET.Element, ET.Element, tuple]]:
    """(def group, path, key) for every path drawn through a <use>; key = (d, matrix)."""
    defs = {}
    for defs_element in svg.findall(f"{SVG}defs"):
        for element in defs_element:
            if element.get("id"):
                defs[element.get("id")] = element
    found = []

    def walk(node, matrix):
        match = MATRIX.match(node.get("transform", ""))
        if match:
            matrix = multiply(matrix, tuple(float(v) for v in match.group(1).replace(",", " ").split()))
        if node.tag == f"{SVG}use":
            target = defs.get((node.get(XLINK_HREF) or "").lstrip("#"))
            if target is not None:
                for path in target.iter(f"{SVG}path"):
                    key = (" ".join(path.get("d", "").split()), tuple(round(v, 3) for v in matrix))
                    found.append((target, path, key))
        for child in node:
            if child.tag != f"{SVG}defs":
                walk(child, matrix)

    walk(svg, (1.0, 0.0, 0.0, 1.0, 0.0, 0.0))
    return found


def merge_covered(directory: Path) -> None:
    """Put paths moved to static_under_secondary.svg back into static.svg."""
    covered_path = directory / COVERED
    if not covered_path.exists():
        return
    static = ET.parse(directory / "static.svg").getroot()
    groups = {g.get("id"): g for defs in static.findall(f"{SVG}defs") for g in defs if g.get("id")}
    for defs in ET.parse(covered_path).getroot().findall(f"{SVG}defs"):
        for group in defs:
            paths = list(group.iter(f"{SVG}path"))
            if paths and group.get("id") in groups:
                for path in paths:
                    groups[group.get("id")].append(path)
    write_svg(directory / "static.svg", static)
    covered_path.unlink()


def split_covered(directory: Path, check: bool) -> str:
    """Move static paths that exactly duplicate a secondary path (the black stand-in
    Flash shows when colorMC2 is hidden) to their own file. With colorMC2 visible
    Flash covers them exactly; drawn underneath here their anti-aliased edges
    leaked out as a dark fringe around every second-colour area."""
    secondary_path = directory / "secondary.svg"
    if not secondary_path.exists():
        return "no secondary"
    if (directory / "static_frames").exists():
        # The bubble body animates its static art frame by frame; leave it whole.
        return "animated static"
    secondary_keys = {key for _, _, key in placed_paths(ET.parse(secondary_path).getroot())}
    static = ET.parse(directory / "static.svg").getroot()
    placed = placed_paths(static)
    covered = {id(path) for _, path, key in placed if key in secondary_keys}
    # A def drawn more than once must be covered at every placement.
    for _, path, key in placed:
        if id(path) in covered and key not in secondary_keys:
            covered.discard(id(path))
    if check:
        has_file = (directory / COVERED).exists()
        if covered or (has_file and not len(placed_paths(ET.parse(directory / COVERED).getroot()))):
            return f"stale: {len(covered)} covered paths left in static.svg"
        return "ok"
    if not covered:
        return "covered 0"
    keep = copy.deepcopy(static)
    for group, path, _ in placed:
        if id(path) in covered and path in list(group):
            group.remove(path)
    for (group, path, _), (keep_group, keep_path, _) in zip(placed, placed_paths(keep)):
        if id(path) not in covered and keep_path in list(keep_group):
            keep_group.remove(keep_path)
    write_svg(directory / "static.svg", static)
    write_svg(directory / COVERED, keep)
    return f"covered {len(covered)}"


def write_svg(path: Path, svg: ET.Element) -> None:
    path.write_text('<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(svg, encoding="unicode") + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xfl", type=Path, default=ROOT / "flash/platform-racing-2-xfl", help="extracted XFL folder")
    parser.add_argument("--check", action="store_true", help="report parts whose split is missing or stale")
    args = parser.parse_args()
    problems = 0
    for kind, source_name in SOURCES.items():
        source = ET.parse(args.xfl / "LIBRARY" / source_name).getroot()
        for directory in sorted((ART / kind).iterdir()):
            if not (directory / "static.svg").exists():
                continue
            prefix = directory.name.partition("_")[0]
            if not prefix.isdigit():
                continue
            bands = frame_bands(source, int(prefix) - 1)
            if bands is None:
                continue
            if not args.check:
                merge_covered(directory)
            results = [split_part(directory, bands, args.check), split_covered(directory, args.check)]
            if (directory / "static_base.svg").exists():
                # Animated hats: the base leaves out the animated layer, and
                # the composer keeps each element as one group.
                base_bands = frame_bands(source, int(prefix) - 1, ANIMATED_HAT_LAYERS, expand_groups=False)
                results.append(split_composed_base(directory, base_bands or [], args.check))
            for result in results:
                if result.startswith(("skipped", "stale")):
                    problems += 1
                print(f"{kind}/{directory.name}: {result}")
    return 1 if args.check and problems else 0


if __name__ == "__main__":
    sys.exit(main())
