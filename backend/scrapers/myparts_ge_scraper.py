import re
import asyncio
from typing import List
from bs4 import BeautifulSoup
from scrapers.base_scraper import BaseScraper
from models.part_price import PartPrice


class MyPartsGeScraper(BaseScraper):
    """
    Scraper for MyParts.ge — the primary Georgian auto parts marketplace.
    Uses the ScrapingBee client for JS rendering + proxy rotation.
    """

    BASE_URL = "https://www.myparts.ge/ka/search/"

    async def search(self, query: str, make: str = "", model: str = "") -> List[PartPrice]:
        search_url = f"{self.BASE_URL}?keyword={query.replace(' ', '+')}"
        results = []

        try:
            html = await asyncio.to_thread(self.fetch_html, search_url, True)
            soup = BeautifulSoup(html, "lxml")

            cards = (
                soup.select(".products-list .product-item")
                or soup.select("[class*='product-card']")
                or soup.select("[class*='product-item']")
            )

            for card in cards[:5]:
                title_el = card.select_one("[class*='title'], [class*='name'], h2, h3, a")
                price_el = card.select_one("[class*='price']")
                link_el = card.select_one("a[href]")

                if not title_el:
                    continue

                title = title_el.get_text(strip=True)
                price_text = price_el.get_text(strip=True) if price_el else ""
                price_num = self._extract_price(price_text)
                url = link_el["href"] if link_el else search_url
                if url.startswith("/"):
                    url = f"https://www.myparts.ge{url}"

                results.append(PartPrice(
                    part_name=title,
                    price=price_num,
                    currency="GEL",
                    store_name="MyParts.ge",
                    url=url,
                    is_oem=False,
                ))

        except Exception as e:
            print(f"[MyParts.ge] Error: {e}")

        # Always append search link as a fallback row
        results.append(PartPrice(
            part_name=f"{query} (Search)",
            price=None,
            currency="GEL",
            store_name="MyParts.ge",
            url=search_url,
            is_oem=False,
        ))
        return results

    def _extract_price(self, text: str) -> float | None:
        numbers = re.findall(r"\d[\d\s]*\.?\d*", text.replace(",", "").replace(" ", ""))
        return float(numbers[0]) if numbers else None
