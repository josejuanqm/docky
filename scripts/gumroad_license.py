#!/usr/bin/env python3
"""
Interactive Gumroad license manager for Docky.

WHAT THIS DOES
  Seller-side management of an existing license key:
    - Look up a key (uses count, buyer email, refund/dispute/chargeback, enabled state)
    - Reset activations (free seats) so the key can re-activate on another Mac
    - Decrement activations by a chosen amount
    - Disable / enable a key

WHAT THIS CANNOT DO
  Gumroad has no API to mint a NEW license key for an existing sale. Keys are
  created by purchases. So "rotating" a key here means resetting/disabling its
  activations, not generating a fresh key string. To hand a buyer a brand-new
  key you must issue it from the Gumroad dashboard (or it comes from a new sale).

REQUIREMENTS
  Python 3 stdlib only. No pip installs.

CREDENTIALS (read from env, or you'll be prompted)
  GUMROAD_ACCESS_TOKEN  Seller API access token. Required for enable/disable/
                        decrement. Create one at gumroad.com/settings/advanced.
  GUMROAD_PRODUCT_ID    Defaults to Docky's product id below.

USAGE
  export GUMROAD_ACCESS_TOKEN=xxxxx
  ./scripts/gumroad_license.py
"""

import json
import os
import sys
import getpass
import urllib.parse
import urllib.request
import urllib.error

API_BASE = "https://api.gumroad.com/v2/licenses"
DEFAULT_PRODUCT_ID = "bigF0QL8D0STXWDEWKlNIg=="  # Docky, mirrors ProductService.gumroadProductID
RESET_SAFETY_CAP = 1000  # guard against an unexpected non-decreasing uses count


def _request(path: str, method: str, params: dict) -> dict:
    """Send a form-encoded request to the Gumroad license API and return parsed JSON."""
    url = f"{API_BASE}/{path}"
    data = urllib.parse.urlencode(params).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # Gumroad returns a JSON body with {"success": false, "message": ...} on 4xx.
        body = exc.read().decode("utf-8", errors="replace")
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return {"success": False, "message": f"HTTP {exc.code}: {body[:200]}"}
    except urllib.error.URLError as exc:
        return {"success": False, "message": f"Network error: {exc.reason}"}


def verify(product_id: str, license_key: str, increment: bool = False) -> dict:
    """Look up a license without inflating its uses count (increment defaults off)."""
    return _request("verify", "POST", {
        "product_id": product_id,
        "license_key": license_key,
        "increment_uses_count": "true" if increment else "false",
    })


def decrement(token: str, product_id: str, license_key: str) -> dict:
    return _request("decrement_uses_count", "PUT", {
        "access_token": token,
        "product_id": product_id,
        "license_key": license_key,
    })


def set_enabled(token: str, product_id: str, license_key: str, enabled: bool) -> dict:
    return _request("enable" if enabled else "disable", "PUT", {
        "access_token": token,
        "product_id": product_id,
        "license_key": license_key,
    })


def _print_license(result: dict) -> None:
    if not result.get("success"):
        print(f"  ✗ {result.get('message', 'License not found or invalid.')}")
        return
    uses = result.get("uses")
    purchase = result.get("purchase", {}) or {}
    print(f"  ✓ success")
    print(f"  uses (activations): {uses}")
    if purchase:
        print(f"  buyer email:        {purchase.get('email', '—')}")
        print(f"  purchased:          {purchase.get('created_at', '—')}")
        flags = []
        if purchase.get("refunded"):
            flags.append("REFUNDED")
        if purchase.get("disputed"):
            flags.append("DISPUTED")
        if purchase.get("chargebacked"):
            flags.append("CHARGEBACKED")
        if purchase.get("disabled"):
            flags.append("DISABLED")
        if purchase.get("subscription_cancelled_at"):
            flags.append("SUB CANCELLED")
        if purchase.get("subscription_ended_at"):
            flags.append("SUB ENDED")
        print(f"  flags:              {', '.join(flags) if flags else 'none'}")


def _prompt_key() -> str:
    return input("  License key: ").strip()


def _confirm(prompt: str) -> bool:
    return input(f"  {prompt} [y/N]: ").strip().lower() in ("y", "yes")


def action_lookup(token, product_id):
    key = _prompt_key()
    if not key:
        return
    print("\nLooking up...")
    _print_license(verify(product_id, key))


def action_reset(token, product_id):
    """Decrement repeatedly until the uses count reaches 0 (frees every seat)."""
    key = _prompt_key()
    if not key:
        return
    current = verify(product_id, key)
    if not current.get("success"):
        _print_license(current)
        return
    uses = current.get("uses") or 0
    print(f"\nCurrent activations: {uses}")
    if uses <= 0:
        print("  Nothing to reset; already at 0.")
        return
    if not _confirm(f"Reset all {uses} activations to 0?"):
        print("  Cancelled.")
        return
    steps = 0
    while uses > 0 and steps < RESET_SAFETY_CAP:
        result = decrement(token, product_id, key)
        if not result.get("success"):
            print(f"  ✗ decrement failed: {result.get('message')}")
            return
        new_uses = result.get("uses")
        # Some responses omit uses; re-verify as a fallback to avoid a tight loop.
        uses = new_uses if isinstance(new_uses, int) else (verify(product_id, key).get("uses") or 0)
        steps += 1
        print(f"  decremented -> uses = {uses}")
    print(f"  ✓ done after {steps} step(s).")


def action_decrement_by(token, product_id):
    key = _prompt_key()
    if not key:
        return
    raw = input("  How many activations to free? ").strip()
    try:
        count = int(raw)
    except ValueError:
        print("  Not a number.")
        return
    if count <= 0:
        return
    for i in range(count):
        result = decrement(token, product_id, key)
        if not result.get("success"):
            print(f"  ✗ decrement failed: {result.get('message')}")
            return
        print(f"  [{i + 1}/{count}] uses = {result.get('uses')}")
    print("  ✓ done.")


def action_set_enabled(token, product_id, enabled):
    key = _prompt_key()
    if not key:
        return
    verb = "enable" if enabled else "disable"
    if not _confirm(f"{verb.capitalize()} this license key?"):
        print("  Cancelled.")
        return
    result = set_enabled(token, product_id, key, enabled)
    if result.get("success"):
        print(f"  ✓ license {verb}d.")
    else:
        print(f"  ✗ {result.get('message')}")


MENU = """
Gumroad license manager (product: {product})
  1) Look up a license key
  2) Reset activations to 0 (free all seats)
  3) Free N activations
  4) Disable a license key
  5) Enable a license key
  q) Quit
"""


def main():
    product_id = os.environ.get("GUMROAD_PRODUCT_ID", DEFAULT_PRODUCT_ID)
    token = os.environ.get("GUMROAD_ACCESS_TOKEN", "")
    if not token:
        print("No GUMROAD_ACCESS_TOKEN in environment.")
        token = getpass.getpass("Paste Gumroad access token (input hidden): ").strip()
    if not token:
        print("An access token is required for enable/disable/decrement. Exiting.")
        sys.exit(1)

    while True:
        print(MENU.format(product=product_id))
        choice = input("Choose: ").strip().lower()
        if choice == "1":
            action_lookup(token, product_id)
        elif choice == "2":
            action_reset(token, product_id)
        elif choice == "3":
            action_decrement_by(token, product_id)
        elif choice == "4":
            action_set_enabled(token, product_id, enabled=False)
        elif choice == "5":
            action_set_enabled(token, product_id, enabled=True)
        elif choice in ("q", "quit", "exit"):
            print("Bye.")
            return
        else:
            print("  Unknown choice.")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nBye.")
