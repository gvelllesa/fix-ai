# FIX AI — Price Finder Backend

A FastAPI microservice that powers the real-time part price search feature in the FIX AI app.

## Architecture

```
POST /scrape  →  asyncio.gather(eBay API, MyParts.ge, Autodoc, RockAuto)
                        ↓
              Unified PartPrice JSON schema
                        ↓
              Supabase part_prices table (via Edge Function cache layer)
```

## Environment Variables

Set these in your Railway project settings:

| Variable | Description |
|---|---|
| `SCRAPINGBEE_API_KEY` | Your ScrapingBee API key (get from app.scrapingbee.com) |
| `EBAY_APP_ID` | eBay Partner Network App ID |
| `EBAY_CLIENT_SECRET` | eBay Partner Network Client Secret |

## Local Development

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload
```

Test the endpoint:
```bash
curl -X POST http://localhost:8000/scrape \
  -H "Content-Type: application/json" \
  -d '{"query": "Air Filter", "make": "BMW", "model": "3 Series"}'
```

## Deploy to Railway

1. Push this repository to GitHub.
2. Go to [railway.app](https://railway.app) → New Project → Deploy from GitHub.
3. Set the **Root Directory** to `backend/`.
4. Add the environment variables listed above.
5. Railway auto-deploys on every `git push`.

## API Reference

### `GET /health`
Returns `{"status": "ok"}`.

### `POST /scrape`
| Field | Type | Description |
|---|---|---|
| `query` | string | Part name to search for |
| `make` | string (optional) | Car make (e.g., "BMW") |
| `model` | string (optional) | Car model (e.g., "3 Series") |

**Response:**
```json
{
  "results": [
    {
      "part_name": "Air Filter BMW 3 Series",
      "price": 12.99,
      "currency": "USD",
      "store_name": "eBay Motors",
      "url": "https://...",
      "is_oem": false
    }
  ],
  "total": 8
}
```
