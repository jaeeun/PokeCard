# PokeCard server

Card info + price lookup via the [TCGdex Python SDK](https://tcgdex.dev/sdks/python),
packaged as a Firebase Cloud Function (Python). Not deployed yet — test locally first.

```
server/
├── firebase.json            # Functions (python312) + emulator config
└── functions/
    ├── card_service.py      # Lookup logic (pure Python, no Firebase)
    ├── main.py              # Cloud Function: lookupCard (callable)
    ├── cli.py               # Local test CLI
    ├── tests/               # Offline unit tests (fake TCGdex)
    ├── requirements.txt     # Deployed deps (pinned)
    └── requirements-dev.txt # pytest
```

## Local setup

Python **3.10–3.13** (Firebase Functions doesn't support 3.14 yet). The venv
must be named `venv` inside `functions/` — the Firebase CLI expects that.

```bash
cd server/functions
python3.12 -m venv venv
./venv/bin/pip install -r requirements.txt -r requirements-dev.txt
```

## Try it

```bash
# Unit tests (offline)
./venv/bin/python -m pytest tests -q

# Real TCGdex lookups
./venv/bin/python cli.py ja 001/073 --code SV1a   # JP: printed code = TCGdex set id
./venv/bin/python cli.py ko 001/073 --code SV1a   # KR: falls back to JA if KR data missing
./venv/bin/python cli.py en 001/198 --code SVI    # EN: printed abbreviation → sv01
./venv/bin/python cli.py en 001/198 --mark G      # no set code: set size + regulation mark
./venv/bin/python cli.py en 001/198               # ambiguous → several matches
```

Exit codes: `0` found, `1` no match, `2` bad input, `3` network error.

## How a card is resolved

1. **Set candidates**
   - With a set code: EN looks up `abbreviation.official` (`SVI` → `sv01`);
     JP/KR use the code as the set id (`SV1a`).
   - Without: every set whose official size equals the printed total (`/198`).
2. **Card** `{setId}-{number}` is fetched in each candidate set.
3. **Filter** by printed set size, then by regulation mark (skipped if it would
   remove every match, since OCR can misread the mark).
4. **Language fallback** `ko → ja`: TCGdex's Korean data is incomplete (e.g.
   KR `SV1a` has no cards), and KR prints share JP set codes and numbering.

`ambiguous: true` means several cards fit and the app should let the user pick.

## Response (`lookupCard` / `cli.py`)

```jsonc
{
  "query": { "language": "ja", "setNumber": "001/073", "setCode": "SV1a", "regulationMark": null },
  "matches": [{
    "id": "SV1a-001", "localId": "001", "name": "トロピウス", "language": "ja",
    "rarity": "Common", "regulationMark": "G", "hp": 110, "illustrator": "…",
    "set": { "id": "SV1a", "name": "トリプレットビート", "official": 73, "total": 103 },
    "pricing": {
      "cardmarket": { "unit": "EUR", "updated": "…", "trend": 0.03, "avg30": 0.04, "low": 0.02, … },
      "tcgplayer":  { "unit": "USD", "updated": "…", "variants": { "normal": { "market": 0.12, … } } }
    }
  }],
  "ambiguous": false,
  "resolvedLanguage": "ja",
  "source": "TCGdex",
  "fetchedAt": "2026-10-22T19:40:00+00:00"
}
```

A pricing provider is omitted when the card isn't listed there (JP/KR cards
usually only have Cardmarket). Show the source and `updated` date in the app.
Card images are intentionally not returned — see `../LICENSING.md`.

## Notes

- **SDK quirks (tcgdex-sdk 2.3.0):** the `Card` model drops `pricing`, so the
  raw JSON is read through the SDK's own cached fetcher (no extra request).
  The SDK also has no request timeout and raises `HTTPError` on 404, so the
  service sets a 6s socket timeout, retries once on timeouts (TCGdex
  occasionally stalls a request), and maps 404 to "not found".
- **Auth:** `lookupCard` rejects unauthenticated calls. For the local emulator
  only, put `ALLOW_UNAUTHENTICATED=true` in `functions/.env.local` (git-ignored).
- **Cost guard:** `max_instances=5`, region `asia-northeast3` (Seoul) in `main.py`.

## Later: emulator & deploy

```bash
npm install -g firebase-tools
cd server
firebase login
firebase use --add            # pick the same project as GoogleService-Info.plist
firebase emulators:start --only functions
firebase deploy --only functions
```

Python functions need the Blaze (pay-as-you-go) plan to deploy.
