#!/usr/bin/env python3
"""Render PRIVACY_POLICY.md to privacy_policy.html.

The store-facing privacy policy is served as HTML from GitHub Pages (raw
Markdown is delivered as text/plain, which Apple 5.1.1(i) review has treated as
not being a privacy policy page). The Markdown file stays the source of truth;
this script is the only thing that writes the HTML, so the two cannot drift.

Run from the repo root:  python3 scripts/build_privacy_html.py

Deliberately dependency-free — this has to run on any machine in the release
path without a pip install. It handles exactly the Markdown this document uses:
h1/h2, paragraphs, unordered lists, and inline bold/italic/code/links. Anything
richer should be added here rather than hand-patched into the HTML.
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PRIVACY_POLICY.md"
TARGET = ROOT / "privacy_policy.html"

HEAD = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Honest Signal — Privacy Policy</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;max-width:720px;\
margin:2rem auto;padding:0 1rem;line-height:1.6;color:#1a2b22}\
h1,h2{color:#14241e}a{color:#0b6e4f}\
code{background:#eef4f1;padding:.1em .3em;border-radius:3px;font-size:.92em}\
ul{padding-left:1.2rem}li{margin:.35rem 0}</style>
</head><body>
"""

FOOT = "</body></html>\n"


def inline(text: str) -> str:
    """Escape, then apply inline Markdown. Escaping first keeps user text safe."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    # Single asterisks only when not part of a ** pair (handled above already).
    out = re.sub(r"(?<!\*)\*([^*\n]+?)\*(?!\*)", r"<em>\1</em>", out)
    out = re.sub(r"`([^`\n]+?)`", r"<code>\1</code>", out)
    return out


def render(markdown: str) -> str:
    parts: list[str] = []
    # Blocks are separated by blank lines. Within a block, a hard-wrapped line
    # is a continuation, NOT a new paragraph — getting this wrong is what made
    # the first cut render every source line as its own <p>.
    for block in re.split(r"\n\s*\n", markdown.strip()):
        lines = [ln.rstrip() for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue

        if lines[0].startswith("## "):
            parts.append(f"<h2>{inline(lines[0][3:].strip())}</h2>")
            rest = lines[1:]
            if rest:
                parts.append(f"<p>{inline(' '.join(rest))}</p>")
            continue

        if lines[0].startswith("# "):
            parts.append(f"<h1>{inline(lines[0][2:].strip())}</h1>")
            rest = lines[1:]
            if rest:
                parts.append(f"<p>{inline(' '.join(rest))}</p>")
            continue

        if lines[0].startswith("- "):
            items: list[str] = []
            for line in lines:
                if line.startswith("- "):
                    items.append(line[2:].strip())
                else:
                    # Continuation of the previous bullet.
                    items[-1] += " " + line.strip()
            rendered = "".join(f"<li>{inline(i)}</li>" for i in items)
            parts.append(f"<ul>{rendered}</ul>")
            continue

        parts.append(f"<p>{inline(' '.join(lines))}</p>")

    return HEAD + "\n".join(parts) + "\n" + FOOT


def main() -> int:
    if not SOURCE.exists():
        print(f"missing {SOURCE}", file=sys.stderr)
        return 1
    TARGET.write_text(render(SOURCE.read_text(encoding="utf-8")), encoding="utf-8")
    print(f"wrote {TARGET.relative_to(ROOT)} from {SOURCE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
