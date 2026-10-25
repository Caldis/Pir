#!/usr/bin/env python3
"""Check portable site paths and production download links before publication."""
from html.parser import HTMLParser
from pathlib import Path
import re

site = Path(__file__).resolve().parents[1] / "website"
root = site / "dist" if (site / "dist/index.html").exists() else site

class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key not in ("href", "src") or not value:
                continue
            if value.startswith(("http:", "https:", "mailto:", "#", "data:")):
                continue
            assert not value.startswith("/"), f"Use project-relative Pages URL: {value}"
            path = value.split("?", 1)[0].split("#", 1)[0]
            assert (root / path).exists(), f"Missing site asset: {value}"

index = root / "index.html"
assert index.exists(), "website/index.html is required"
html = index.read_text()
Links().feed(html)
assert "github.com/Caldis/Pir/releases" in html, "Release download link is required"
assert not re.search(r"(?:localhost|127\.0\.0\.1):\d+", html), "Remove local preview URLs"
print("Website paths and release link passed")
