#!/usr/bin/env python3
"""Enforce completeness and translation quality for shipped gettext catalogs."""

from __future__ import annotations

import ast
import re
import shutil
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from seed_whisper_languages import (
    PO_DIR,
    POT_PATH,
    WHISPER_CODES,
    validate_language_sources,
)

CANARY_LANGUAGES = ("ro", "de", "ja", "zh", "ar", "fr", "es", "ko", "hi")
CANARY_MESSAGES = (
    "System OS Update",
    "Checking dependencies...",
    "Continue",
)
EXACT_TRANSLATION_EXCEPTIONS = frozenset(
    {
        "OK",
        "Pi-Apps Update",
        "ssmtp",
        "msmtp",
        "curl",
        "whiptail",
    }
)
LANGUAGE_EXACT_TRANSLATION_EXCEPTIONS: dict[str, frozenset[str]] = {
    "ca": frozenset({"OK"}),
    "oc": frozenset({"OK"}),
}
PRINTF_PATTERN = re.compile(r"%(?:\d+\$)?[#0 +'I-]*(?:\d+|\*)?(?:\.\d+|\.\*)?[hlLjzt]*[diouxXeEfFgGcrsa%]")
TRANSLATION_ARTIFACT_PATTERN = re.compile(
    r"(?:\n#\s*$)|(?:#@)|(?:@#)|(?:^#%(?:[0-9]+\$)?[diouxXeEfFgGcrsa%])|"
    r"(?:\s+#+\s*$)|(?:\bGSM\s*\d)|(?:\bMHz\b)",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass
class PoEntry:
    """One parsed PO entry."""

    msgid: str = ""
    msgid_plural: str = ""
    msgctxt: str = ""
    msgstr: dict[int, str] = field(default_factory=dict)
    flags: set[str] = field(default_factory=set)
    obsolete: bool = False


def _quoted_value(text: str) -> str:
    return ast.literal_eval(text.strip())


def _field_target(token: str) -> tuple[str, int]:
    if token.startswith("msgstr["):
        return "msgstr", int(token.removeprefix("msgstr[").removesuffix("]"))
    return token, 0


def _consume_comment(entry: PoEntry, line: str) -> bool:
    if line.startswith("#~"):
        entry.obsolete = True
        return True
    if line.startswith("#,"):
        entry.flags.update(item.strip() for item in line[2:].split(","))
        return True
    return False


def _consume_content_line(
    entry: PoEntry,
    line: str,
    active_field: str,
    active_index: int,
) -> tuple[str, int, bool]:
    match = re.match(r"^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)\s+(\".*\")$", line)
    if match:
        field_name, field_index = _field_target(match.group(1))
        _set_field(entry, field_name, field_index, _quoted_value(match.group(2)))
        return field_name, field_index, True
    if line.startswith('"') and active_field:
        _append_field(entry, active_field, active_index, _quoted_value(line))
    return active_field, active_index, False


def _set_field(entry: PoEntry, field_name: str, index: int, value: str) -> None:
    if field_name == "msgstr":
        entry.msgstr[index] = value
        return
    setattr(entry, field_name, value)


def _append_field(entry: PoEntry, field_name: str, index: int, value: str) -> None:
    if field_name == "msgstr":
        entry.msgstr[index] = entry.msgstr.get(index, "") + value
        return
    setattr(entry, entry_name := field_name, getattr(entry, entry_name) + value)


def _parse_entry(lines: list[str]) -> PoEntry | None:
    entry = PoEntry()
    active_field = ""
    active_index = 0
    saw_field = False
    for line in lines:
        if _consume_comment(entry, line):
            continue
        active_field, active_index, consumed = _consume_content_line(entry, line, active_field, active_index)
        saw_field = saw_field or consumed
    return entry if saw_field else None


def _append_parsed_entry(entries: list[PoEntry], block: list[str]) -> None:
    parsed = _parse_entry(block)
    if parsed is not None:
        entries.append(parsed)


def parse_po(path: Path) -> list[PoEntry]:
    """Parse active PO entries without requiring a third-party Python package."""
    entries: list[PoEntry] = []
    block: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            block.append(line)
            continue
        _append_parsed_entry(entries, block)
        block = []
    _append_parsed_entry(entries, block)
    return [entry for entry in entries if not entry.obsolete]


def _require_tools() -> None:
    missing = [tool for tool in ("msgfmt", "msgcmp") if shutil.which(tool) is None]
    if missing:
        raise RuntimeError(f"missing gettext tools: {', '.join(missing)}")


def _run_gettext_checks(path: Path) -> None:
    subprocess.run(["msgfmt", "--check", "--check-format", "-o", "/dev/null", path], check=True)
    subprocess.run(["msgcmp", "--use-fuzzy", path, POT_PATH], check=True)


def _header_value(header: str, name: str) -> str:
    prefix = f"{name}:"
    for line in header.splitlines():
        if line.startswith(prefix):
            return line.removeprefix(prefix).strip()
    return ""


def _entry_key(entry: PoEntry) -> str:
    return f"{entry.msgctxt}\x04{entry.msgid}" if entry.msgctxt else entry.msgid


def _source_values(entry: PoEntry) -> tuple[str, ...]:
    if entry.msgid_plural:
        return (entry.msgid, entry.msgid_plural)
    return (entry.msgid,)


def _translation_values(entry: PoEntry) -> tuple[str, ...]:
    return tuple(value for _, value in sorted(entry.msgstr.items()))


def _translations_missing(translations: tuple[str, ...]) -> bool:
    return not translations or any(not value.strip() for value in translations)


def _is_exact_translation_exception(entry: PoEntry, language: str) -> bool:
    language_exceptions = LANGUAGE_EXACT_TRANSLATION_EXCEPTIONS.get(language, ())
    return entry.msgid in EXACT_TRANSLATION_EXCEPTIONS or entry.msgid in language_exceptions


def _has_english_carryover(entry: PoEntry, translations: tuple[str, ...]) -> bool:
    sources = _source_values(entry)
    return any(value.strip() in sources for value in translations)


def _english_carryover_invalid(
    entry: PoEntry,
    language: str,
    translations: tuple[str, ...],
) -> bool:
    if language == "en" or _is_exact_translation_exception(entry, language):
        return False
    return _has_english_carryover(entry, translations)


def _validate_placeholders(entry: PoEntry, language: str) -> None:
    sources = _source_values(entry)
    translations = _translation_values(entry)
    for index, translation in enumerate(translations):
        source = sources[min(index, len(sources) - 1)]
        if Counter(PRINTF_PATTERN.findall(source)) != Counter(PRINTF_PATTERN.findall(translation)):
            raise ValueError(f"{language}: placeholders differ for {entry.msgid!r}")


def _translation_has_artifact(msgid: str, translation: str) -> bool:
    if TRANSLATION_ARTIFACT_PATTERN.search(translation) is None:
        return False
    return TRANSLATION_ARTIFACT_PATTERN.search(msgid) is None


def _validate_translation_artifacts(entry: PoEntry, language: str) -> None:
    for translation in _translation_values(entry):
        if _translation_has_artifact(entry.msgid, translation):
            raise ValueError(f"{language}: translation artifact in {entry.msgid!r}")


def _validate_entry(entry: PoEntry, language: str) -> None:
    if "fuzzy" in entry.flags:
        raise ValueError(f"{language}: fuzzy entry {entry.msgid!r}")
    translations = _translation_values(entry)
    if _translations_missing(translations):
        raise ValueError(f"{language}: empty translation for {entry.msgid!r}")
    if _english_carryover_invalid(entry, language, translations):
        raise ValueError(f"{language}: English placeholder for {entry.msgid!r}")
    _validate_translation_artifacts(entry, language)
    _validate_placeholders(entry, language)


def _catalog_header(entries: list[PoEntry]) -> str:
    return next((entry.msgstr.get(0, "") for entry in entries if not entry.msgid), "")


def _validate_revision_date(header: str, language: str) -> None:
    revision = _header_value(header, "PO-Revision-Date")
    if not revision or "YEAR-MO-DA" in revision:
        raise ValueError(f"{language}: PO-Revision-Date still has the gettext default")


def _validate_headers(entries: list[PoEntry], language: str, endonym: str) -> None:
    header = _catalog_header(entries)
    if _header_value(header, "Language") != language:
        raise ValueError(f"{language}: incorrect Language header")
    if _header_value(header, "Language-Team") != endonym:
        raise ValueError(f"{language}: Language-Team must use the native endonym")
    if "charset=UTF-8" not in _header_value(header, "Content-Type"):
        raise ValueError(f"{language}: catalog is not UTF-8")
    if not _header_value(header, "Plural-Forms"):
        raise ValueError(f"{language}: missing Plural-Forms header")
    _validate_revision_date(header, language)


def _validate_catalog(language: str, source_keys: set[str], endonym: str) -> dict[str, PoEntry]:
    path = PO_DIR / f"{language}.po"
    _run_gettext_checks(path)
    entries = parse_po(path)
    _validate_headers(entries, language, endonym)
    translated = {_entry_key(entry): entry for entry in entries if entry.msgid}
    if set(translated) != source_keys:
        raise ValueError(f"{language}: catalog entries differ from the POT")
    for entry in translated.values():
        _validate_entry(entry, language)
    return translated


def _validate_canaries(catalogs: dict[str, dict[str, PoEntry]]) -> None:
    for language in CANARY_LANGUAGES:
        for message in CANARY_MESSAGES:
            entry = catalogs[language].get(message)
            if entry is None or entry.msgstr.get(0, "").strip() == message:
                raise ValueError(f"{language}: untranslated canary {message!r}")


def _actual_po_codes() -> tuple[str, ...]:
    return tuple(sorted(path.stem for path in PO_DIR.glob("*.po")))


def _source_keys() -> set[str]:
    return {_entry_key(entry) for entry in parse_po(POT_PATH) if entry.msgid}


def _validated_catalogs(
    source_keys: set[str],
    endonyms: dict[str, str],
) -> dict[str, dict[str, PoEntry]]:
    return {language: _validate_catalog(language, source_keys, endonyms[language]) for language in WHISPER_CODES}


def check_catalogs() -> None:
    """Run all source-list, structure, gettext, and translation checks."""
    _require_tools()
    endonyms = validate_language_sources()
    if _actual_po_codes() != tuple(sorted(WHISPER_CODES)):
        raise ValueError("po/*.po files do not exactly match SUPPORTED_LANGUAGES")
    source_keys = _source_keys()
    _validate_canaries(_validated_catalogs(source_keys, endonyms))


def main() -> int:
    """CLI entry point."""
    try:
        check_catalogs()
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Catalog quality check failed: {error}", file=sys.stderr)
        return 1
    print(f"Validated {len(WHISPER_CODES)} complete, non-fuzzy gettext catalogs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
