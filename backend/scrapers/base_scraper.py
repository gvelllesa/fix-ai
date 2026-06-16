import os
from abc import ABC, abstractmethod
from typing import List
from scrapingbee import ScrapingBeeClient
import httpx

from models.part_price import PartPrice

SCRAPINGBEE_API_KEY = os.environ.get("SCRAPINGBEE_API_KEY", "")


class BaseScraper(ABC):
    """
    Abstract base scraper using the official ScrapingBee Python client.
    All subclasses get JS rendering + proxy rotation for free.
    """

    def __init__(self):
        if SCRAPINGBEE_API_KEY:
            self._bee = ScrapingBeeClient(api_key=SCRAPINGBEE_API_KEY)
        else:
            self._bee = None
        self._http = httpx.AsyncClient(
            timeout=30.0,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
        )

    def fetch_html(self, url: str, render_js: bool = True) -> str:
        """
        Synchronous fetch via ScrapingBee (handles proxies + JS rendering).
        Falls back to a direct HTTPX request when no API key is set (local dev).
        ScrapingBeeClient is synchronous — wrap in asyncio.to_thread() in async context.
        """
        if self._bee:
            response = self._bee.get(
                url,
                params={
                    "render_js": "true" if render_js else "false",
                    "block_ads": "true",
                    "block_resources": "false",
                    "timeout": "20000",
                },
            )
            response.raise_for_status()
            return response.text
        else:
            import asyncio
            # Direct fetch for local development without ScrapingBee
            response = asyncio.get_event_loop().run_until_complete(self._http.get(url))
            return response.text

    @abstractmethod
    async def search(self, query: str, make: str = "", model: str = "") -> List[PartPrice]:
        """Search for a part and return a list of standardized PartPrice results."""
        pass

    async def close(self):
        await self._http.aclose()
