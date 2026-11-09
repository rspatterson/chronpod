#!/usr/bin/env python3
"""Convert a tt-rss / ChronLaw OPML export to current Google News feed addresses.

Old:  https://news.google.com/news/rss/search/section/q/Animal+Law
New:  https://news.google.com/rss/search?q=Animal%20Law&hl=en-US&gl=US&ceid=US:en

Usage:  python3 tools/convert_opml.py tt-rss.opml chronlaw.opml

ChronPod converts old addresses itself, so this is optional. It keeps the file on
chronlaw.com tidy and lets other feed readers use it too. tt-rss-only attributes are dropped.
"""
import sys
import urllib.parse
import xml.etree.ElementTree as ET

MARKERS = ["/news/rss/search/section/q/", "/rss/search/section/q/", "/news/rss/search/q/"]


def modernize(url: str) -> str:
    low = url.lower()
    if not (low.startswith("https://news.google.com/") or low.startswith("http://news.google.com/")):
        return url
    parsed = urllib.parse.urlparse(url)
    if parsed.path in ("/news", "/news/") and "output=rss" in parsed.query:
        # Retired "Top Stories" feed.
        return "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"
    marker = next((m for m in MARKERS if m in url), None)
    if not marker:
        return url
    raw = url.split(marker, 1)[1]
    for stop in "/?#":
        raw = raw.split(stop, 1)[0]
    q = urllib.parse.unquote(raw).replace("+", " ").replace("|", " OR ")
    q = " ".join(q.split())
    if not q:
        return url
    return "https://news.google.com/rss/search?" + urllib.parse.urlencode(
        {"q": q, "hl": "en-US", "gl": "US", "ceid": "US:en"}, quote_via=urllib.parse.quote, safe=":")


def main(src: str, dst: str) -> None:
    tree = ET.parse(src)
    root = tree.getroot()
    head = root.find("head")
    if head is not None:
        title = head.find("title")
        if title is not None:
            title.text = "ChronLaw Topics"
    changed = 0
    for o in root.iter("outline"):
        for attr in list(o.attrib):
            if attr.startswith("ttrss"):
                del o.attrib[attr]
        if "xmlUrl" in o.attrib:
            new = modernize(o.attrib["xmlUrl"])
            if new != o.attrib["xmlUrl"]:
                changed += 1
                o.attrib["xmlUrl"] = new
                qs = urllib.parse.parse_qs(urllib.parse.urlparse(new).query)
                if "q" not in qs:
                    o.attrib["htmlUrl"] = "https://news.google.com/?hl=en-US&gl=US&ceid=US:en"
                    continue
                q = qs["q"][0]
                o.attrib["htmlUrl"] = "https://news.google.com/search?" + urllib.parse.urlencode(
                    {"q": q, "hl": "en-US", "gl": "US", "ceid": "US:en"}, quote_via=urllib.parse.quote, safe=":")
    root.set("version", "2.0")
    ET.indent(tree, space="  ")
    tree.write(dst, encoding="utf-8", xml_declaration=True)
    print(f"{changed} feed addresses converted -> {dst}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
