"""Checks the App Store text in appstore/PUBLISHING.md against Apple's character limits.

    python3 tools/check_listing.py [path/to/PUBLISHING.md]

The listing text lives in one section per locale ("## Listing — English (U.S.)",
"## Listing — Portuguese (Brazil)"). Within each section, a field's value is the first code
block after the line containing its label. It also fails while the app name placeholder
{{APP_NAME}} is still in a listing section, and warns about [...] placeholders left
in the Review Notes.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "appstore", "PUBLISHING.md")

LOCALES = ["English (U.S.)", "Portuguese (Brazil)"]
PLACEHOLDER = "{{APP_NAME}}"

# label in the guide -> Apple's limit; every locale section must have each of these
LIMITS = {
    "**Name** (30)": 30,
    "**Subtitle** (30)": 30,
    "**Promotional Text** (170)": 170,
    "**Description** (4000)": 4000,
    "**Keywords** (100)": 100,
}
# App Review Information is not localized: the notes appear once, in the first section.
REVIEW_NOTES = ("**Review Notes** (4000)", 4000)


def section(text, locale):
    """The text from the locale's heading to the next level-2 heading, or None."""
    heading = f"## Listing — {locale}"
    start = text.find(heading)
    if start < 0:
        return None
    end = text.find("\n## ", start + len(heading))
    return text[start:] if end < 0 else text[start:end]


def field(body, label):
    """The code block that directly follows the label's line (only blank lines may come between),
    with each line's indentation removed; None if the label or its block is missing."""
    pattern = re.escape(label) + r"[^\n]*\n(?:[ \t]*\n)*[ \t]*```[^\n]*\n(.*?)^[ \t]*```"
    block = re.search(pattern, body, re.S | re.M)
    if not block:
        return None
    return "\n".join(line.strip() for line in block.group(1).split("\n")).strip()


def check(locale, label, limit, value):
    """Prints one result line; returns True when the field is within its limit."""
    name = label.split("**")[1]
    if value is None:
        print(f"✗ {locale} · {name}: label not found, or no code block right after it")
        return False
    if not value:
        print(f"✗ {locale} · {name}: empty")
        return False
    ok = len(value) <= limit
    print(f"{'✓' if ok else '✗'} {locale} · {name}: {len(value)}/{limit}")
    if name == "Keywords" and ", " in value:
        print(f"✗ {locale} · Keywords: no spaces after commas")
        ok = False
    if name == "Review Notes":
        for placeholder in re.findall(r"\[[^\]\n]+\]", value):
            print(f"! {locale} · Review Notes: fill in {placeholder} before submitting (warning)")
    return ok


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DOC
    text = open(path, encoding="utf-8").read()
    failed = False
    placeholder_left = False
    for index, locale in enumerate(LOCALES):
        body = section(text, locale)
        if body is None:
            print(f"✗ section not found: ## Listing — {locale}")
            failed = True
            continue
        placeholder_left |= PLACEHOLDER in body
        fields = dict(LIMITS)
        if index == 0:
            fields[REVIEW_NOTES[0]] = REVIEW_NOTES[1]
        for label, limit in fields.items():
            failed |= not check(locale, label, limit, field(body, label))
    if placeholder_left:
        print(f"✗ App name not chosen yet: replace every {PLACEHOLDER} in the listing sections")
        failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
