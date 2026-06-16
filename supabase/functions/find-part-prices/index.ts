// Supabase Edge Function: find-part-prices
// Deploy with: supabase functions deploy find-part-prices

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SCRAPER_BACKEND_URL = Deno.env.get('SCRAPER_BACKEND_URL') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const CACHE_TTL_HOURS = 24

interface ScrapeRequest {
  query: string
  make?: string
  model?: string
}

interface PartPrice {
  part_name: string
  price: number | null
  currency: string
  store_name: string
  url: string | null
  is_oem: boolean
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Authorization, Content-Type' } })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  let body: ScrapeRequest
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid request body' }), { status: 400 })
  }

  const { query, make = '', model = '' } = body
  if (!query) {
    return new Response(JSON.stringify({ error: 'query is required' }), { status: 400 })
  }

  // 1. Check Supabase cache first (records fetched within last 24 hours)
  const cutoff = new Date(Date.now() - CACHE_TTL_HOURS * 60 * 60 * 1000).toISOString()
  const { data: cached } = await supabase
    .from('part_prices')
    .select('*')
    .ilike('part_name', `%${query}%`)
    .gte('fetched_at', cutoff)
    .limit(20)

  if (cached && cached.length >= 4) {
    console.log(`[find-part-prices] Returning ${cached.length} cached results for "${query}"`)
    return new Response(JSON.stringify({ results: cached, source: 'cache' }), {
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    })
  }

  // 2. No fresh cache — call the Python scraper backend
  if (!SCRAPER_BACKEND_URL) {
    return new Response(JSON.stringify({ error: 'SCRAPER_BACKEND_URL not configured' }), { status: 503 })
  }

  let scraperResults: PartPrice[] = []
  try {
    console.log(`[find-part-prices] Dispatching scrape job for "${query}"`)
    const scraperResp = await fetch(`${SCRAPER_BACKEND_URL}/scrape`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, make, model }),
    })
    if (!scraperResp.ok) throw new Error(`Scraper returned ${scraperResp.status}`)
    const scraperData = await scraperResp.json()
    scraperResults = scraperData.results ?? []
  } catch (e) {
    console.error(`[find-part-prices] Scraper error: ${e}`)
    return new Response(JSON.stringify({ error: 'Scraper service unavailable', details: String(e) }), { status: 502 })
  }

  // 3. Insert fresh results into part_prices table
  if (scraperResults.length > 0) {
    const rows = scraperResults.map((r) => ({
      part_name: r.part_name,
      price: r.price,
      currency: r.currency,
      store_name: r.store_name,
      url: r.url,
      is_oem: r.is_oem,
      fetched_at: new Date().toISOString(),
    }))
    const { error: insertError } = await supabase.from('part_prices').insert(rows)
    if (insertError) console.error(`[find-part-prices] Insert error: ${insertError.message}`)
  }

  return new Response(JSON.stringify({ results: scraperResults, source: 'live' }), {
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  })
})
