import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface EcuKeyRequest {
  vin: string;
  ecuAddress: number;
  level: number;
  seedHex: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // 1. Authenticate user session from JWT token
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized user session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as EcuKeyRequest;
    const { vin, ecuAddress, level, seedHex } = body;

    if (!vin || vin.length < 17 || typeof ecuAddress !== "number" || typeof level !== "number" || !seedHex) {
      return new Response(
        JSON.stringify({ error: "Invalid parameters. Required: vin (17 chars), ecuAddress, level, seedHex" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 2. Verify that this user holds a valid license for the requested VIN
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);
    const { data: license, error: licenseError } = await adminClient
      .from("ecu_licenses")
      .select("id, active_stage, signature")
      .eq("vin", vin.toUpperCase().trim())
      .eq("user_id", user.id)
      .maybeSingle();

    if (licenseError || !license) {
      return new Response(
        JSON.stringify({
          error: "Vehicle VIN is not licensed or authorized for this account. Flashing access denied.",
          licensed: false,
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 3. Compute UDS Security Access Key inside secure server environment
    const seedBytes = seedHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) ?? [];
    if (seedBytes.length < 4) {
      return new Response(
        JSON.stringify({ error: "Invalid seed length: must be at least 4 bytes" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const s = ((seedBytes[0] << 24) | (seedBytes[1] << 16) | (seedBytes[2] << 8) | seedBytes[3]) >>> 0;
    const secretSalt = parseInt(Deno.env.get("ECU_SECRET_SALT") ?? "0x4B6D2A8F", 16);
    const mask = (secretSalt ^ ((ecuAddress & 0xFF) << 16) ^ ((level & 0xFF) << 8)) >>> 0;
    let k = (s ^ mask) >>> 0;
    k = (((k << 5) | (k >>> 27)) ^ 0xA55A3C89) >>> 0;
    k = (k + 0x3F1A7C25) >>> 0;
    k = (((k << 13) | (k >>> 19)) ^ 0x55AA1234) >>> 0;

    const keyBytes = [
      (k >>> 24) & 0xFF,
      (k >>> 16) & 0xFF,
      (k >>> 8) & 0xFF,
      k & 0xFF,
    ];
    const keyHex = keyBytes.map((b) => b.toString(16).padStart(2, "0")).join("");

    return new Response(
      JSON.stringify({
        keyHex,
        vin: vin.toUpperCase().trim(),
        ecuAddress,
        level,
        status: "AUTHORIZED",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: `Internal server error: ${message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
