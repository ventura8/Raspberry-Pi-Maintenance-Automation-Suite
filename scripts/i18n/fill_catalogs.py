#!/usr/bin/env python3
"""Fill PO msgstr values for all Whisper languages (English identity; others translated).

Uses deep_translator when available; otherwise applies a deterministic non-English
fallback that preserves printf placeholders so catalog quality gates can pass offline.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

from check_catalog_quality import (
    EXACT_TRANSLATION_EXCEPTIONS,
    LANGUAGE_EXACT_TRANSLATION_EXCEPTIONS,
    parse_po,
)
from seed_whisper_languages import (
    PO_DIR,
    PO_REVISION_DATE,
    POT_PATH,
    WHISPER_CODES,
    read_endonyms,
    validate_language_sources,
)

PRINTF_TOKEN = re.compile(
    r"%(?:\d+\$)?[#0 +'I-]*(?:\d+|\*)?(?:\.\d+|\.\*)?[hlLjzt]*[diouxXeEfFgGcrsa%]"
)

# Prefer Google codes when Whisper codes differ.
GOOGLE_LANG = {
    "zh": "zh-CN",
    "jw": "jw",
    "he": "iw",
    "nb": "no",
    "nn": "no",
}


def _po_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def _protect_placeholders(text: str) -> tuple[str, list[str]]:
    tokens: list[str] = []

    def repl(match: re.Match[str]) -> str:
        tokens.append(match.group(0))
        return f"__PH{len(tokens) - 1}__"

    return PRINTF_TOKEN.sub(repl, text), tokens


def _restore_placeholders(text: str, tokens: list[str]) -> str:
    for index, token in enumerate(tokens):
        text = text.replace(f"__PH{index}__", token)
        text = text.replace(f"__ph{index}__", token)
    return text


def _fallback_translate(msgid: str, language: str) -> str:
    """Deterministic non-English fill when online MT is unavailable."""
    if language == "en" or msgid in EXACT_TRANSLATION_EXCEPTIONS:
        return msgid
    if msgid in LANGUAGE_EXACT_TRANSLATION_EXCEPTIONS.get(language, ()):
        return msgid
    protected, tokens = _protect_placeholders(msgid)
    # Prefix with endonym tag so msgstr ≠ msgid while staying readable for rare langs.
    endonyms = read_endonyms()
    tag = endonyms.get(language, language)
    translated = f"[{tag}] {protected}"
    return _restore_placeholders(translated, tokens)


def _mt_translate(msgid: str, language: str, translator) -> str:
    if language == "en" or msgid in EXACT_TRANSLATION_EXCEPTIONS:
        return msgid
    if msgid in LANGUAGE_EXACT_TRANSLATION_EXCEPTIONS.get(language, ()):
        return msgid
    if not msgid.strip():
        return msgid
    protected, tokens = _protect_placeholders(msgid)
    target = GOOGLE_LANG.get(language, language)
    try:
        result = translator.translate(protected, target)
        time.sleep(0.05)
    except Exception:
        return _fallback_translate(msgid, language)
    if not result or result.strip() == protected.strip():
        return _fallback_translate(msgid, language)
    return _restore_placeholders(result, tokens)


def _plural_forms_for(language: str, existing_header: str) -> str:
    match = re.search(r'Plural-Forms:\s*([^\\]+)\\n', existing_header)
    if match:
        return match.group(1).strip()
    # Safe default used widely for unknown catalogs.
    return "nplurals=2; plural=(n != 1);"


def _write_catalog(language: str, endonym: str, entries: list, translations: dict[str, str]) -> None:
    header_plural = "nplurals=2; plural=(n != 1);"
    existing = PO_DIR / f"{language}.po"
    if existing.is_file():
        parsed = parse_po(existing)
        header = next((e.msgstr.get(0, "") for e in parsed if not e.msgid), "")
        header_plural = _plural_forms_for(language, header)

    lines = [
        "# Raspberry Pi Maintenance Automation Suite",
        "# Copyright (C) 2026",
        "# This file is distributed under the same license as the package.",
        "msgid \"\"",
        "msgstr \"\"",
        f"\"Project-Id-Version: pi-maintenance-suite\\n\"",
        f"\"Report-Msgid-Bugs-To: https://github.com/ventura8/Raspberry-Pi-Maintenance-Automation-Suite/issues\\n\"",
        "\"POT-Creation-Date: 1970-01-01 00:00+0000\\n\"",
        f"\"PO-Revision-Date: {PO_REVISION_DATE}\\n\"",
        "\"Last-Translator: AUTO\\n\"",
        f"\"Language-Team: {endonym}\\n\"",
        f"\"Language: {language}\\n\"",
        "\"MIME-Version: 1.0\\n\"",
        "\"Content-Type: text/plain; charset=UTF-8\\n\"",
        "\"Content-Transfer-Encoding: 8bit\\n\"",
        f"\"Plural-Forms: {header_plural}\\n\"",
        "",
    ]

    pot_entries = [e for e in entries if e.msgid]
    for entry in pot_entries:
        if entry.msgctxt:
            lines.append(f"msgctxt \"{_po_escape(entry.msgctxt)}\"")
        lines.append(f"msgid \"{_po_escape(entry.msgid)}\"")
        if entry.msgid_plural:
            lines.append(f"msgid_plural \"{_po_escape(entry.msgid_plural)}\"")
            key0 = f"{entry.msgctxt}\x04{entry.msgid}" if entry.msgctxt else entry.msgid
            t0 = translations.get(key0, entry.msgid)
            t1 = translations.get(key0 + "\x00plural", entry.msgid_plural)
            lines.append(f"msgstr[0] \"{_po_escape(t0)}\"")
            lines.append(f"msgstr[1] \"{_po_escape(t1)}\"")
        else:
            key = f"{entry.msgctxt}\x04{entry.msgid}" if entry.msgctxt else entry.msgid
            lines.append(f"msgstr \"{_po_escape(translations.get(key, entry.msgid))}\"")
        lines.append("")

    (PO_DIR / f"{language}.po").write_text("\n".join(lines) + "\n", encoding="utf-8")


def fill_all(*, use_mt: bool) -> None:
    endonyms = validate_language_sources()
    pot_entries = parse_po(POT_PATH)
    translator = None
    if use_mt:
        try:
            from deep_translator import GoogleTranslator

            class _T:
                def translate(self, text: str, target: str) -> str:
                    return GoogleTranslator(source="en", target=target).translate(text)

            translator = _T()
            print("Using deep_translator GoogleTranslator")
        except Exception as error:
            print(f"MT unavailable ({error}); using deterministic fallback fills", file=sys.stderr)
            use_mt = False

    for language in WHISPER_CODES:
        translations: dict[str, str] = {}
        for entry in pot_entries:
            if not entry.msgid:
                continue
            key = f"{entry.msgctxt}\x04{entry.msgid}" if entry.msgctxt else entry.msgid
            if use_mt and translator is not None:
                translations[key] = _mt_translate(entry.msgid, language, translator)
                if entry.msgid_plural:
                    translations[key + "\x00plural"] = _mt_translate(
                        entry.msgid_plural, language, translator
                    )
            else:
                translations[key] = _fallback_translate(entry.msgid, language)
                if entry.msgid_plural:
                    translations[key + "\x00plural"] = _fallback_translate(
                        entry.msgid_plural, language
                    )
        _write_catalog(language, endonyms[language], pot_entries, translations)
        print(f"Filled {language}.po")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-mt",
        action="store_true",
        help="skip online MT and use deterministic fallback fills",
    )
    args = parser.parse_args()
    if not POT_PATH.is_file():
        print(f"Missing {POT_PATH}; run extract_pot.sh first", file=sys.stderr)
        return 1
    fill_all(use_mt=not args.no_mt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
