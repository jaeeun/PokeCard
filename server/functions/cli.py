"""
Local test CLI — calls TCGdex directly, no Firebase needed.

    ./venv/bin/python cli.py ja 001/073 --code SV1a
    ./venv/bin/python cli.py ko 001/071 --mark H
    ./venv/bin/python cli.py en 001/198 --code SVI
    ./venv/bin/python cli.py en 001/198 --mark G      # no set code: size + mark
"""

import argparse
import json
import sys

from card_service import CardLookupError, CardLookupService, LookupQuery


def main() -> int:
    p = argparse.ArgumentParser(description="Look up a card on TCGdex.")
    p.add_argument("language", choices=["en", "ja", "ko"])
    p.add_argument("set_number", help='e.g. "001/073"')
    p.add_argument("--code", help='printed set code, e.g. "SV1a" or "SVI"')
    p.add_argument("--mark", help='regulation mark, e.g. "G"')
    args = p.parse_args()

    try:
        result = CardLookupService().lookup(LookupQuery(
            language=args.language,
            set_number=args.set_number,
            set_code=args.code,
            regulation_mark=args.mark,
        ))
    except CardLookupError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except OSError as e:  # URLError / timeouts reaching TCGdex
        print(f"network error talking to TCGdex: {e}", file=sys.stderr)
        return 3

    print(json.dumps(result.to_dict(), ensure_ascii=False, indent=2))
    return 0 if result.matches else 1


if __name__ == "__main__":
    sys.exit(main())
