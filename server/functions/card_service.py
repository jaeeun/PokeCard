"""
Card lookup using the TCGdex Python SDK (https://tcgdex.dev/sdks/python).

Pure Python, no Firebase dependency, so it can be run and tested locally
(see cli.py / tests/). `main.py` wraps it as a Firebase Cloud Function.

Input is what the iOS scanner reads from the card's footer row:

    G  SV1a  001/073  C
    │  │     │   │    └─ rarity (not needed for lookup)
    │  │     │   └────── official set size
    │  │     └────────── local card number
    │  └──────────────── set code (optional; app doesn't parse it yet)
    └─────────────────── regulation mark (optional; used to disambiguate)

LICENSING: only factual data (names, numbers, rarity, prices) is returned.
Official card images are intentionally NOT returned — see LICENSING.md.
"""

from __future__ import annotations

import json
import re
import socket
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Optional, Protocol, TypeVar
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from tcgdexsdk import Query, TCGdex

T = TypeVar("T")

SUPPORTED_LANGUAGES = {"en", "ja", "ko"}

# Korean prints reuse the Japanese set codes and numbering, and TCGdex's
# Korean data is incomplete (e.g. SV1a has 0 cards), so fall back to JA.
LANGUAGE_FALLBACKS = {"ko": ["ja"]}

_SET_NUMBER_RE = re.compile(r"^\s*([A-Za-z]*\d{1,3}[A-Za-z]?)\s*(?:/\s*(\d{1,3}))?\s*$")


class CardLookupError(ValueError):
    """Invalid lookup input (maps to INVALID_ARGUMENT in the function)."""


# --------------------------------------------------------------------------
# TCGdex access
# --------------------------------------------------------------------------

class CardSource(Protocol):
    """What the lookup needs from TCGdex. Faked in tests."""

    def sets_by_abbreviation(self, lang: str, code: str) -> list[str]: ...
    def sets_by_official_count(self, lang: str, count: int) -> list[str]: ...
    def set_exists(self, lang: str, set_id: str) -> bool: ...
    def card(self, lang: str, card_id: str) -> Optional[dict[str, Any]]: ...


class TCGdexSource:
    """CardSource backed by the official TCGdex Python SDK."""

    def __init__(self, timeout_sec: float = 6.0, retries: int = 1) -> None:
        self._sdks: dict[str, TCGdex] = {}
        self._retries = retries
        # tcgdex-sdk calls urlopen() without a timeout, so a stalled
        # connection would hang until the function's own deadline. A process
        # default bounds it (this process only serves card lookups).
        if socket.getdefaulttimeout() is None:
            socket.setdefaulttimeout(timeout_sec)

    def _call(self, fn: Callable[[], T]) -> T:
        """TCGdex occasionally stalls a request while the next one returns in
        ~50ms, so retry timeouts/connection errors. HTTP errors (404 etc.) are
        real answers and are not retried."""
        for attempt in range(self._retries + 1):
            try:
                return fn()
            except HTTPError:
                raise
            except (URLError, TimeoutError):
                if attempt == self._retries:
                    raise
        raise AssertionError("unreachable")

    def _sdk(self, lang: str) -> TCGdex:
        if lang not in self._sdks:
            self._sdks[lang] = TCGdex(lang)
        return self._sdks[lang]

    def sets_by_abbreviation(self, lang: str, code: str) -> list[str]:
        q = Query().equal("abbreviation.official", code)
        return [s.id for s in self._call(lambda: self._sdk(lang).set.listSync(q))]

    def sets_by_official_count(self, lang: str, count: int) -> list[str]:
        q = Query().equal("cardCount.official", count)
        return [s.id for s in self._call(lambda: self._sdk(lang).set.listSync(q))]

    def set_exists(self, lang: str, set_id: str) -> bool:
        try:
            return self._call(lambda: self._sdk(lang).set.getSync(set_id)) is not None
        except HTTPError as e:
            if e.code == 404:
                return False
            raise

    def card(self, lang: str, card_id: str) -> Optional[dict[str, Any]]:
        sdk = self._sdk(lang)
        try:
            c = self._call(lambda: sdk.card.getSync(card_id))  # raises HTTPError on 404
        except HTTPError as e:
            if e.code == 404:
                return None
            raise
        if c is None:
            return None
        raw = self._call(lambda: self._raw_card(sdk, card_id))

        card_set = c.set
        count = getattr(card_set, "cardCount", None)
        return {
            "id": c.id,
            "localId": c.localId,
            "name": c.name,
            "language": lang,
            "category": c.category,
            "rarity": c.rarity,
            "regulationMark": c.regulationMark,
            "hp": c.hp,
            "types": c.types,
            "stage": c.stage,
            "illustrator": c.illustrator,
            "set": {
                "id": card_set.id,
                "name": card_set.name,
                "official": getattr(count, "official", None),
                "total": getattr(count, "total", None),
            },
            "pricing": normalize_pricing(raw.get("pricing")),
        }

    @staticmethod
    def _raw_card(sdk: TCGdex, card_id: str) -> dict[str, Any]:
        """Raw card JSON, needed because tcgdex-sdk 2.3.0's `Card` model drops
        the `pricing` field. Reuses the SDK's own cached fetcher so this does
        not cost a second network request; falls back to a plain GET if that
        private helper ever changes."""
        url = f"{sdk.getEndpoint()}/{sdk.getLanguage()}/cards/{card_id}"
        try:
            from tcgdexsdk import utils as sdk_utils

            body = sdk_utils._urlopen(url, time.monotonic() // (sdk_utils.ttl * 60))
        except (ImportError, AttributeError, TypeError):
            req = Request(url, headers={"User-Agent": "pokecard-server"})
            with urlopen(req) as resp:  # bounded by the socket default timeout
                body = resp.read().decode()
        return json.loads(body)


def normalize_pricing(pricing: Optional[dict[str, Any]]) -> dict[str, Any]:
    """Trims TCGdex `pricing` to the fields the app shows. Providers that
    don't list the card are omitted."""
    out: dict[str, Any] = {}
    if not pricing:
        return out

    cm = pricing.get("cardmarket")
    if cm:
        out["cardmarket"] = {
            "unit": cm.get("unit"),             # EUR
            "updated": cm.get("updated"),
            "trend": cm.get("trend"),
            "avg30": cm.get("avg30"),
            "low": cm.get("low"),
            "trendHolo": cm.get("trend-holo") or None,
            "avg30Holo": cm.get("avg30-holo"),
        }

    tp = pricing.get("tcgplayer")
    if tp:
        variants = {
            name: {
                "market": v.get("marketPrice"),
                "low": v.get("lowPrice"),
                "mid": v.get("midPrice"),
                "high": v.get("highPrice"),
            }
            for name, v in tp.items()
            if isinstance(v, dict)
        }
        out["tcgplayer"] = {
            "unit": tp.get("unit"),             # USD
            "updated": tp.get("updated"),
            "variants": variants,
        }
    return out


# --------------------------------------------------------------------------
# Lookup logic
# --------------------------------------------------------------------------

@dataclass
class LookupQuery:
    language: str
    set_number: str                       # "001/073" or "001"
    set_code: Optional[str] = None        # "SV1a" (JP/KR) or "SVI" (EN)
    regulation_mark: Optional[str] = None # "G"

    @property
    def local_id(self) -> str:
        return _parse_set_number(self.set_number)[0]

    @property
    def official_count(self) -> Optional[int]:
        return _parse_set_number(self.set_number)[1]


@dataclass
class LookupResult:
    query: dict[str, Any]
    matches: list[dict[str, Any]] = field(default_factory=list)
    # True when several cards fit and the app should let the user choose.
    ambiguous: bool = False
    # Set when results came from a fallback language (e.g. ko → ja).
    resolved_language: Optional[str] = None
    source: str = "TCGdex"
    fetched_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat(timespec="seconds")
    )

    def to_dict(self) -> dict[str, Any]:
        return {
            "query": self.query,
            "matches": self.matches,
            "ambiguous": self.ambiguous,
            "resolvedLanguage": self.resolved_language,
            "source": self.source,
            "fetchedAt": self.fetched_at,
        }


def _parse_set_number(raw: str) -> tuple[str, Optional[int]]:
    m = _SET_NUMBER_RE.match(raw or "")
    if not m:
        raise CardLookupError(f"Unrecognized set number: {raw!r}")
    local_id, total = m.group(1), m.group(2)
    return local_id, int(total) if total else None


class CardLookupService:
    def __init__(self, source: Optional[CardSource] = None) -> None:
        self.source = source or TCGdexSource()

    def lookup(self, q: LookupQuery) -> LookupResult:
        lang = (q.language or "").lower()
        if lang not in SUPPORTED_LANGUAGES:
            raise CardLookupError(f"Unsupported language: {q.language!r}")
        q.local_id  # validates the set number early
        if not q.set_code and q.official_count is None:
            raise CardLookupError("Need a set code or a set number like '001/073'.")

        result = LookupResult(query={
            "language": lang,
            "setNumber": q.set_number,
            "setCode": q.set_code,
            "regulationMark": q.regulation_mark,
        })

        for candidate_lang in [lang, *LANGUAGE_FALLBACKS.get(lang, [])]:
            matches = self._lookup_in(candidate_lang, q)
            if matches:
                result.matches = matches
                result.ambiguous = len(matches) > 1
                result.resolved_language = candidate_lang
                break
        return result

    def _lookup_in(self, lang: str, q: LookupQuery) -> list[dict[str, Any]]:
        cards: list[dict[str, Any]] = []
        for set_id in self._candidate_sets(lang, q):
            card = self._find_card(lang, set_id, q.local_id)
            if card:
                cards.append(card)

        # The printed set size must agree when we know it.
        if q.official_count is not None:
            cards = [c for c in cards
                     if c["set"]["official"] in (None, q.official_count)]

        # Regulation mark narrows sets with the same size (e.g. 198 → sv01 vs
        # swsh6). Only filter if it doesn't eliminate everything — OCR can
        # misread the mark.
        if q.regulation_mark:
            mark = q.regulation_mark.upper()
            same_mark = [c for c in cards if (c.get("regulationMark") or "").upper() == mark]
            if same_mark:
                cards = same_mark
        return cards

    def _candidate_sets(self, lang: str, q: LookupQuery) -> list[str]:
        if q.set_code:
            code = q.set_code.strip()
            # EN cards print an abbreviation ("SVI") that differs from the
            # TCGdex set id ("sv01"); JP/KR print the id itself ("SV1a").
            found = self.source.sets_by_abbreviation(lang, code.upper())
            if not found and self.source.set_exists(lang, code):
                found = [code]
            if found:
                return found
        if q.official_count is not None:
            return self.source.sets_by_official_count(lang, q.official_count)
        return []

    def _find_card(self, lang: str, set_id: str, local_id: str) -> Optional[dict[str, Any]]:
        # Try "001" as printed, then "1" in case a set uses unpadded ids.
        tried = []
        for lid in (local_id, local_id.lstrip("0") or "0"):
            if lid in tried:
                continue
            tried.append(lid)
            card = self.source.card(lang, f"{set_id}-{lid}")
            if card:
                return card
        return None
