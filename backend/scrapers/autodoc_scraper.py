import re
import asyncio
from typing import List
from urllib.parse import quote_plus
from bs4 import BeautifulSoup
from scrapers.base_scraper import BaseScraper
from models.part_price import PartPrice


class AutodocScraper(BaseScraper):
    """
    Scraper for Autodoc.co.uk — major EU auto parts marketplace.
    Autodoc is heavily JS-rendered; ScrapingBee is essential here.
    """

    BASE_URL = "https://www.autodoc.co.uk"

    async def search(self, query: str, make: str = "", model: str = "") -> List[PartPrice]:
        search_url = f"{self.BASE_URL}/search?query={quote_plus(query)}"
        results = []

        try:
            html = await asyncio.to_thread(self.fetch_html, search_url, True)
            soup = BeautifulSoup(html, "lxml")

            cards = (
                soup.select(".product-card")
                or soup.select("[class*='listing-item']")
                or soup.select("[class*='product-list-item']")
            )

            for card in cards[:5]:
                title_el = card.select_one("[class*='title'], [class*='name'], h2, h3")
                price_el = card.select_one("[class*='price']")
                link_el = card.select_one("a[href]")
                oem_badge = card.select_one("[class*='oem'], [class*='original']")

                if not title_el:
                    continue

                title = title_el.get_text(strip=True)
                price_text = price_el.get_text(strip=True) if price_el else ""
                price_num = self._extract_price(price_text)
                url = link_el["href"] if link_el else search_url
                if url.startswith("/"):
                    url = f"{self.BASE_URL}{url}"

                results.append(PartPrice(
                    part_name=title,
                    price=price_num,
                    currency="GBP",
                    store_name="Autodoc",
                    url=url,
                    is_oem=oem_badge is not None,
                ))

        except Exception as e:
            print(f"[Autodoc] Error: {e}")

        results.append(PartPrice(
            part_name=f"{query} (Search)",
            price=None,
            currency="EUR",
            store_name="Autodoc",
            url=search_url,
            is_oem=False,
        ))
        return results

    def _extract_price(self, text: str) -> float | None:
        numbers = re.findall(r"\d[\d]*\.?\d*", text.replace(",", ""))
        return float(numbers[0]) if numbers else None
