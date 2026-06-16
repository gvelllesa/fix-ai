import os
import httpx
from typing import List
from models.part_price import PartPrice

EBAY_APP_ID = os.environ.get("EBAY_APP_ID", "")
EBAY_API_BASE = "https://api.ebay.com/buy/browse/v1"


async def get_ebay_oauth_token() -> str:
    """Fetches a client-credentials OAuth token from eBay."""
    import base64
    client_secret = os.environ.get("EBAY_CLIENT_SECRET", "")
    credentials = base64.b64encode(f"{EBAY_APP_ID}:{client_secret}".encode()).decode()

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://api.ebay.com/identity/v1/oauth2/token",
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"grant_type": "client_credentials", "scope": "https://api.ebay.com/oauth/api_scope"},
        )
        resp.raise_for_status()
        return resp.json()["access_token"]


async def search_ebay_motors(query: str, make: str = "", model: str = "") -> List[PartPrice]:
    """
    Searches eBay Motors using the official eBay Browse API.
    Returns results in the standardized PartPrice format.
    Requires EBAY_APP_ID and EBAY_CLIENT_SECRET environment variables.
    Falls back to empty list if not configured.
    """
    if not EBAY_APP_ID:
        print("[eBay] No EBAY_APP_ID set. Skipping eBay results.")
        return []

    try:
        token = await get_ebay_oauth_token()
        search_query = f"{query} {make} {model}".strip()

        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{EBAY_API_BASE}/item_summary/search",
                headers={"Authorization": f"Bearer {token}"},
                params={
                    "q": search_query,
                    "category_ids": "6030",  # eBay Motors > Parts & Accessories
                    "limit": "5",
                    "sort": "price",
                },
            )
            resp.raise_for_status()
            data = resp.json()

        results = []
        for item in data.get("itemSummaries", []):
            price_val = item.get("price", {})
            results.append(PartPrice(
                part_name=item.get("title", query),
                price=float(price_val.get("value", 0)),
                currency=price_val.get("currency", "USD"),
                store_name="eBay Motors",
                url=item.get("itemWebUrl"),
                is_oem=False,
            ))
        return results

    except Exception as e:
        print(f"[eBay] API error: {e}")
        return []
