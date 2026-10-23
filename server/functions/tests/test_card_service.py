"""Offline unit tests for the lookup logic (fake TCGdex source, no network).

    ./venv/bin/python -m pytest tests -q
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from card_service import (  # noqa: E402
    CardLookupError,
    CardLookupService,
    LookupQuery,
    normalize_pricing,
)


def _card(lang, set_id, local_id, name, official, mark):
    return {
        "id": f"{set_id}-{local_id}", "localId": local_id, "name": name,
        "language": lang, "regulationMark": mark,
        "set": {"id": set_id, "name": set_id, "official": official, "total": official},
        "pricing": {},
    }


class FakeSource:
    def __init__(self):
        self.sets = {
            "en": {"sv01": (198, "SVI"), "swsh6": (198, "CRE")},
            "ja": {"SV1a": (73, None), "SV9": (100, None)},
            "ko": {"SV1a": (73, None), "SV5K": (71, None)},  # KR SV1a has no cards
        }
        self.cards = {
            "en": {"sv01-001": _card("en", "sv01", "001", "Pineco", 198, "G"),
                   "swsh6-001": _card("en", "swsh6", "001", "Venusaur V", 198, "E")},
            "ja": {"SV1a-001": _card("ja", "SV1a", "001", "トロピウス", 73, "G")},
            "ko": {"SV5K-001": _card("ko", "SV5K", "001", "로젤리아", 71, "H")},
        }

    def sets_by_abbreviation(self, lang, code):
        return [sid for sid, (_, abbr) in self.sets[lang].items() if abbr == code]

    def sets_by_official_count(self, lang, count):
        return [sid for sid, (n, _) in self.sets[lang].items() if n == count]

    def set_exists(self, lang, set_id):
        return set_id in self.sets[lang]

    def card(self, lang, card_id):
        return self.cards[lang].get(card_id)


@pytest.fixture
def svc():
    return CardLookupService(FakeSource())


def ids(result):
    return [m["id"] for m in result.matches]


def test_jp_by_set_code(svc):
    r = svc.lookup(LookupQuery("ja", "001/073", set_code="SV1a"))
    assert ids(r) == ["SV1a-001"] and not r.ambiguous


def test_en_abbreviation_maps_to_set_id(svc):
    r = svc.lookup(LookupQuery("en", "001/198", set_code="SVI"))
    assert ids(r) == ["sv01-001"]


def test_en_without_code_is_ambiguous_by_size(svc):
    r = svc.lookup(LookupQuery("en", "001/198"))
    assert set(ids(r)) == {"sv01-001", "swsh6-001"} and r.ambiguous


def test_regulation_mark_disambiguates(svc):
    r = svc.lookup(LookupQuery("en", "001/198", regulation_mark="G"))
    assert ids(r) == ["sv01-001"] and not r.ambiguous


def test_wrong_mark_does_not_eliminate_everything(svc):
    r = svc.lookup(LookupQuery("en", "001/198", regulation_mark="Z"))
    assert len(r.matches) == 2


def test_ko_falls_back_to_ja(svc):
    r = svc.lookup(LookupQuery("ko", "001/073", set_code="SV1a"))
    assert ids(r) == ["SV1a-001"] and r.resolved_language == "ja"


def test_ko_found_natively(svc):
    r = svc.lookup(LookupQuery("ko", "001/071", regulation_mark="H"))
    assert ids(r) == ["SV5K-001"] and r.resolved_language == "ko"


def test_set_size_mismatch_filtered(svc):
    r = svc.lookup(LookupQuery("ja", "001/999", set_code="SV1a"))
    assert r.matches == []


@pytest.mark.parametrize("bad", [
    LookupQuery("fr", "001/073"),
    LookupQuery("ja", "abc"),
    LookupQuery("ja", "001"),          # no total and no set code
])
def test_invalid_input(svc, bad):
    with pytest.raises(CardLookupError):
        svc.lookup(bad)


def test_normalize_pricing():
    out = normalize_pricing({
        "cardmarket": {"unit": "EUR", "trend": 0.03, "avg30": 0.04, "trend-holo": 0},
        "tcgplayer": {"unit": "USD", "updated": "x",
                      "normal": {"marketPrice": 0.12, "lowPrice": 0.01}},
    })
    assert out["cardmarket"]["trend"] == 0.03
    assert out["cardmarket"]["trendHolo"] is None
    assert out["tcgplayer"]["variants"]["normal"]["market"] == 0.12
    assert normalize_pricing(None) == {}


def test_retry_on_timeout_but_not_on_http_error():
    from urllib.error import HTTPError

    from card_service import TCGdexSource

    src = TCGdexSource(retries=1)
    calls = {"n": 0}

    def flaky():
        calls["n"] += 1
        if calls["n"] == 1:
            raise TimeoutError("stalled")
        return "ok"

    assert src._call(flaky) == "ok" and calls["n"] == 2

    def not_found():
        calls["n"] += 1
        raise HTTPError("u", 404, "nf", None, None)

    calls["n"] = 0
    with pytest.raises(HTTPError):
        src._call(not_found)
    assert calls["n"] == 1
