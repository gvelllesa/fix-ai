import os
import asyncio
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

# Load .env for local development (Railway injects env vars directly in production)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # python-dotenv not installed in production — env vars set by Railway


from models.part_price import PartPrice
from scrapers.ebay_motors_api import search_ebay_motors
from scrapers.myparts_ge_scraper import MyPartsGeScraper
from scrapers.autodoc_scraper import AutodocScraper
from scrapers.rockauto_scraper import RockAutoScraper

app = FastAPI(title="FIX AI Price Finder", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ScrapeRequest(BaseModel):
    query: str
    make: Optional[str] = ""
    model: Optional[str] = ""


class ScrapeResponse(BaseModel):
    results: List[PartPrice]
    total: int


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/scrape", response_model=ScrapeResponse)
async def scrape_prices(req: ScrapeRequest) -> ScrapeResponse:
    """
    Fan out to all 4 connectors in parallel and return combined results.
    Results are sorted by price ascending (None-price results go last).
    """
    if not req.query.strip():
        raise HTTPException(status_code=400, detail="query cannot be empty")

    myparts = MyPartsGeScraper()
    autodoc = AutodocScraper()
    rockauto = RockAutoScraper()

    # Run all scrapers concurrently
    tasks = await asyncio.gather(
        search_ebay_motors(req.query, req.make, req.model),
        myparts.search(req.query, req.make, req.model),
        autodoc.search(req.query, req.make, req.model),
        rockauto.search(req.query, req.make, req.model),
        return_exceptions=True,
    )

    # Flatten results, skip exceptions
    combined: List[PartPrice] = []
    for result in tasks:
        if isinstance(result, Exception):
            print(f"[Main] Scraper exception: {result}")
        elif isinstance(result, list):
            combined.extend(result)

    # Sort: items with prices first (ascending), then fallback links
    combined.sort(key=lambda x: (x.price is None, x.price or 0))

    # Cleanup
    await myparts.close()
    await autodoc.close()
    await rockauto.close()

    return ScrapeResponse(results=combined, total=len(combined))
