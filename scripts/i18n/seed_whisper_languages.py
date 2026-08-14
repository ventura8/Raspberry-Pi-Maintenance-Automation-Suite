#!/usr/bin/env python3
"""Create missing PO skeletons for the exact Whisper language set."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PO_DIR = REPO_ROOT / "po"
POT_PATH = PO_DIR / "pi-maintenance-suite.pot"
SUPPORTED_PATH = PO_DIR / "SUPPORTED_LANGUAGES"
ENDONYMS_PATH = PO_DIR / "LANGUAGE_ENDONYMS"

WHISPER_CODE_TEXT = (
    "en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms "
    "cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa lv bn sr az sl kn "
    "et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be "
    "tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha "
    "ba jw su"
)
WHISPER_CODES = tuple(WHISPER_CODE_TEXT.split())
# Stable real stamp (not gettext's YEAR-MO-DA placeholder) so msgfmt --check is quiet.
PO_REVISION_DATE = "2026-01-01 00:00+0000"


def read_supported_codes() -> tuple[str, ...]:
    """Read non-empty catalog codes in their canonical order."""
    return tuple(line.strip() for line in SUPPORTED_PATH.read_text(encoding="utf-8").splitlines() if line.strip())


def _parse_endonym_row(raw_line: str) -> tuple[str, str]:
    code, separator, endonym = raw_line.partition("|")
    if not separator or not code or not endonym:
        raise ValueError(f"invalid endonym row: {raw_line!r}")
    return code, endonym


def read_endonyms() -> dict[str, str]:
    """Read the machine-code to native-language-name mapping."""
    result: dict[str, str] = {}
    for raw_line in ENDONYMS_PATH.read_text(encoding="utf-8").splitlines():
        code, endonym = _parse_endonym_row(raw_line)
        if code in result:
            raise ValueError(f"duplicate endonym code: {code}")
        result[code] = endonym
    return result


def validate_language_sources() -> dict[str, str]:
    """Fail unless both source lists exactly match Whisper's 99 codes."""
    supported = read_supported_codes()
    if supported != WHISPER_CODES:
        raise ValueError("SUPPORTED_LANGUAGES does not exactly match Whisper LANGUAGES")
    endonyms = read_endonyms()
    if tuple(endonyms) != WHISPER_CODES:
        raise ValueError("LANGUAGE_ENDONYMS codes/order do not match SUPPORTED_LANGUAGES")
    return endonyms


def _run_msginit(code: str, output_path: Path) -> None:
    locale_code = "jv" if code == "jw" else code
    subprocess.run(
        [
            "msginit",
            "--no-translator",
            f"--locale={locale_code}",
            f"--input={POT_PATH}",
            f"--output-file={output_path}",
        ],
        check=True,
    )


def _normalize_headers(path: Path, code: str, endonym: str) -> None:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'^"Language: .*?\\n"$', f'"Language: {code}\\\\n"', text, flags=re.MULTILINE)
    text = re.sub(
        r'^"Language-Team: .*?\\n"$',
        f'"Language-Team: {endonym}\\\\n"',
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r'^"PO-Revision-Date: YEAR-MO-DA HO:MI\+ZONE\\n"$',
        f'"PO-Revision-Date: {PO_REVISION_DATE}\\\\n"',
        text,
        flags=re.MULTILINE,
    )
    path.write_text(text, encoding="utf-8")


def _missing_catalogs() -> list[Path]:
    return [PO_DIR / f"{code}.po" for code in WHISPER_CODES if not (PO_DIR / f"{code}.po").is_file()]


def _seed_catalogs(missing: list[Path]) -> None:
    for path in missing:
        _run_msginit(path.stem, path)
        print(f"Seeded {path.relative_to(REPO_ROOT)}")


def _normalize_all_headers(endonyms: dict[str, str]) -> None:
    for code in WHISPER_CODES:
        _normalize_headers(PO_DIR / f"{code}.po", code, endonyms[code])


def seed_missing_catalogs(check_only: bool) -> list[Path]:
    """Create missing PO files, returning the paths that were absent."""
    if shutil.which("msginit") is None:
        raise RuntimeError("msginit is required to seed catalogs")
    endonyms = validate_language_sources()
    missing = _missing_catalogs()
    if check_only:
        return missing
    _seed_catalogs(missing)
    _normalize_all_headers(endonyms)
    return missing


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if any catalog is missing")
    args = parser.parse_args()
    try:
        missing = seed_missing_catalogs(args.check)
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Catalog seeding failed: {error}", file=sys.stderr)
        return 1
    if args.check and missing:
        joined = ", ".join(path.name for path in missing)
        print(f"Missing catalogs: {joined}", file=sys.stderr)
        return 1
    print(f"Catalog set contains all {len(WHISPER_CODES)} Whisper languages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
