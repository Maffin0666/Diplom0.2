"""Save the current server API contract for the future Flutter client."""

import json
from pathlib import Path

from server.app.main import app


def main() -> None:
    output = Path(__file__).resolve().parents[1] / "client" / "api" / "openapi.v1.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(app.openapi(), ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(f"OpenAPI записан в {output}")


if __name__ == "__main__":
    main()
