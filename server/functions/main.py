"""
Firebase Cloud Functions entry point (Python).

`lookupCard` is a callable function, so the iOS app can call it with the
FirebaseFunctions SDK and the user's Firebase Auth token is verified for us.

Not deployed yet — test the logic locally first with cli.py / pytest.
"""

import os

from firebase_functions import https_fn, options

from card_service import CardLookupError, CardLookupService, LookupQuery

# Cap scale-out so a bug or abuse can't run up a bill.
options.set_global_options(max_instances=5, region="asia-northeast3")

_service = CardLookupService()

# Only for the local emulator. Never set this in production.
_ALLOW_UNAUTHENTICATED = os.environ.get("ALLOW_UNAUTHENTICATED") == "true"


@https_fn.on_call(timeout_sec=30)
def lookupCard(req: https_fn.CallableRequest) -> dict:
    """data: {language, setNumber, setCode?, regulationMark?}"""
    if req.auth is None and not _ALLOW_UNAUTHENTICATED:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED,
                                  "Sign in to look up cards.")

    data = req.data or {}
    try:
        query = LookupQuery(
            language=str(data.get("language", "")),
            set_number=str(data.get("setNumber", "")),
            set_code=data.get("setCode") or None,
            regulation_mark=data.get("regulationMark") or None,
        )
        return _service.lookup(query).to_dict()
    except CardLookupError as e:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(e))
    except Exception as e:  # network / TCGdex errors (incl. timeouts)
        print(f"lookupCard failed: {e!r}")
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAVAILABLE,
                                  "Card database is unavailable. Try again later.")
