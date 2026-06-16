# FIX AI — Price Finder Backend: Deployment Guide

## Overview

This folder contains the Python FastAPI microservice that powers the real-time automotive part price search feature in the FIX AI app.

It connects to **ScrapingBee** for proxy-rotated JS rendering and to the **eBay Partner Network API** for official marketplace data. All results are stored in Supabase via the `find-part-prices` Edge Function.

---

## Required Environment Variables

Set these in your **Railway project → Variables** tab before deploying:

| Variable | Required | Description |
|---|---|---|
| `SCRAPINGBEE_API_KEY` | ✅ Yes | Your ScrapingBee API key from [app.scrapingbee.com](https://app.scrapingbee.com) |
| `EBAY_APP_ID` | ⚠️ Optional | eBay Developer App ID from [developer.ebay.com](https://developer.ebay.com). Without it, eBay results are skipped. |
| `EBAY_CLIENT_SECRET` | ⚠️ Optional | eBay Developer Client Secret (required alongside `EBAY_APP_ID`) |

> **Security:** Never commit `.env` to git. The `.gitignore` already excludes it.

---

## Deploy to Railway (Step-by-Step)

### 1. Push to GitHub
Ensure this repository is pushed to your GitHub account:
```bash
git push origin main
```

### 2. Create a Railway Project
1. Go to [railway.app](https://railway.app) and sign in.
2. Click **New Project** → **Deploy from GitHub Repo**.
3. Select your repository.

### 3. Configure the Root Directory
> ⚠️ **CRITICAL:** Railway must be told to deploy only from the `backend/` subfolder.

In your Railway project settings:
- Go to **Settings** → **Source**
- Set **Root Directory** to: `/backend`

### 4. Add Environment Variables
In Railway → **Variables**, add:
- `SCRAPINGBEE_API_KEY` = `your_key_here`
- `EBAY_APP_ID` = `your_ebay_app_id` *(optional)*
- `EBAY_CLIENT_SECRET` = `your_ebay_secret` *(optional)*

### 5. Deploy
Railway will automatically detect the `Dockerfile` in the `/backend` folder and build + deploy the service. The first deploy takes ~2-3 minutes.

### 6. Copy Your Railway URL
Once deployed, copy the public URL (e.g., `https://fix-ai-backend.up.railway.app`).

---

## Connect to Supabase Edge Function

After deploying, set the `SCRAPER_BACKEND_URL` secret in Supabase:

```bash
supabase secrets set SCRAPER_BACKEND_URL=https://your-service.up.railway.app \
  --project-ref pfztaizoqlxfgqyiojdh
```

Then deploy the Edge Function:

```bash
supabase functions deploy find-part-prices \
  --project-ref pfztaizoqlxfgqyiojdh
```

---

## API Reference

### `GET /health`
Health check. Returns `{"status": "ok"}`.

### `POST /scrape`
Searches all 4 price sources in parallel and returns unified results.

**Request body:**
```json
{
  "query": "Air Filter",
  "make": "BMW",
  "model": "3 Series"
}
```

**Response:**
```json
{
  "results": [
    {
      "part_name": "Air Filter BMW 3 Series",
      "price": 12.99,
      "currency": "USD",
      "store_name": "eBay Motors",
      "url": "https://www.ebay.com/...",
      "is_oem": false
    }
  ],
  "total": 8
}
```

---

## Local Development

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Test with:
```bash
curl -X POST http://localhost:8000/scrape \
  -H "Content-Type: application/json" \
  -d '{"query": "Spark Plugs", "make": "BMW", "model": "5 Series"}'
```
