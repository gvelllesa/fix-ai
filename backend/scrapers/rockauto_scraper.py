import re
import asyncio
from typing import List
from urllib.parse import quote_plus
from bs4 import BeautifulSoup
from scrapers.base_scraper import BaseScraper
from models.part_price import PartPrice


class RockAutoScraper(BaseScraper):
    """
    Scraper for RockAuto.com — the US aftermarket price benchmark.
    Uses ScrapingBee for rendering. Provides a search deep-link fallback.
    """

    BASE_URL = "https://www.rockauto.com"

    async def search(self, query: str, make: str = "", model: str = "") -> List[PartPrice]:
        # RockAuto's catalog is navigation-based; search URL is the best entry point
        search_url = f"{self.BASE_URL}/en/partsearch/?parttype={quote_plus(query)}&make={quote_plus(make)}&model={quote_plus(model)}"
        results = []

        try:
            html = await asyncio.to_thread(self.fetch_html, search_url, True)
            soup = BeautifulSoup(html, "lxml")

            cards = (
                soup.select(".listing-inner")
                or soup.select("[class*='ra-product']")
                or soup.select("tr[id*='listing']")
            )

            for card in cards[:5]:
                title_el = card.select_one("[class*='listing-name'], [class*='part-desc'], td")
                price_el = card.select_one("[class*='listing-price'], [class*='price']")
                link_el = card.select_one("a[href]")

                if not title_el:
                    continue

                title = title_el.get_text(strip=True)
                price_text = price_el.get_text(strip=True) if price_el else ""
                price_num = self._extract_price(price_text)
                url = link_el["href"] if link_el else search_url
                if url.startswith("/"):
                    url = f"{self.BASE_URL}{url}"

                results.append(PartPrice(
                    part_name=title or query,
                    price=price_num,
                    currency="USD",
                    store_name="RockAuto",
                    url=url,
                    is_oem=False,
                ))

        except Exception as e:
            print(f"[RockAuto] Error: {e}")

        results.append(PartPrice(
            part_name=f"{query} (Search)",
            price=None,
            currency="USD",
            store_name="RockAuto",
            url=search_url,
            is_oem=False,
        ))
        return results

    def _extract_price(self, text: str) -> float | None:
        numbers = re.findall(r"\d[\d]*\.?\d*", text.replace(",", ""))
        return float(numbers[0]) if numbers else None
