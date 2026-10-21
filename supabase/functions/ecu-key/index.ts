import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export type BmwEcuSecurityFamily =
  | "MEVD17_UDS"
  | "MG1_MD1_UDS"
  | "ZF8HP_UDS"
  | "VTG_UDS_KWP"
  | "FEM_BDC_CODING"
  | "KWP2000_ESERIES";

interface EcuKeyRequest {
  vin: string;
  ecuAddress: number;
  level: number;
  seedHex: string;
  ecuFamily?: BmwEcuSecurityFamily;
  btldHex?: string;
}

function rotl32(val: number, shift: number): number {
  const s = shift & 31;
  return (((val << s) | (val >>> (32 - s))) >>> 0);
}

/**
 * Resolves the target BMW ECU Security Family from explicit family, BTLD, or (ecuAddress, level).
 */
export function resolveEcuFamily(
  ecuAddress: number,
  level: number,
  seedLength: number,
  explicitFamily?: BmwEcuSecurityFamily,
): BmwEcuSecurityFamily {
  if (explicitFamily) return explicitFamily;
  if (seedLength === 2) return "KWP2000_ESERIES";
  if (seedLength >= 8 && ecuAddress === 0x12) return "MG1_MD1_UDS";
  switch (ecuAddress & 0xFF) {
    case 0x18:
      return "ZF8HP_UDS";
    case 0x19:
    case 0x52:
      return "VTG_UDS_KWP";
    case 0x40:
    case 0x60:
    case 0x63:
    case 0x6D:
      return "FEM_BDC_CODING";
    case 0x12:
      return level >= 0x11 ? "MG1_MD1_UDS" : "MEVD17_UDS";
    default:
      return "MEVD17_UDS";
  }
}

/**
 * Computes deterministic BMW UDS / KWP2000 SecurityAccess (0x27) key bytes
 * for the resolved BMW ECU family.
 */
export function computeBmwSecurityKey(
  seedBytes: number[],
  ecuAddress: number,
  level: number,
  secretSalt: number,
  family: BmwEcuSecurityFamily,
): number[] {
  // 2-byte KWP2000 E-Series Seed-to-Key (GS19 / VGSG90 / MSV70)
  if (seedBytes.length === 2 || (family === "KWP2000_ESERIES" && seedBytes.length < 4)) {
    const s16 = (((seedBytes[0] & 0xFF) << 8) | (seedBytes[1] & 0xFF)) & 0xFFFF;
    const poly = ((secretSalt & 0xFFFF) ^ ((ecuAddress & 0xFF) << 8) ^ (level & 0xFF)) & 0xFFFF;
    const k16 = ((((s16 << 5) | (s16 >>> 11)) & 0xFFFF) ^ poly ^ 0x5A3C) & 0xFFFF;
    return [(k16 >>> 8) & 0xFF, k16 & 0xFF];
  }

  const s0 =
    (((seedBytes[0] & 0xFF) << 24) |
      ((seedBytes[1] & 0xFF) << 16) |
      ((seedBytes[2] & 0xFF) << 8) |
      (seedBytes[3] & 0xFF)) >>>
    0;
  const mask = (secretSalt ^ ((ecuAddress & 0xFF) << 16) ^ ((level & 0xFF) << 8)) >>> 0;

  let k0 = 0;
  switch (family) {
    case "ZF8HP_UDS": {
      // ZF 8HP (GKE / GSZFB1 / 8HP45/50/70/75) polynomial LFSR transform
      let v = (s0 ^ mask ^ 0x8F457075) >>> 0;
      for (let i = 0; i < 8; i++) {
        const lsb = v & 1;
        v = (v >>> 1) ^ (lsb ? 0xEDB88320 : 0x3C6EF372);
      }
      k0 = rotl32(v, 7) ^ 0x5A827999;
      break;
    }
    case "VTG_UDS_KWP": {
      // xDelete VTG (VGSG / ATC300 / ATC35L / ATC45L) security transform
      let v = (s0 ^ mask ^ 0x56544719) >>> 0;
      v = (rotl32(v, 11) + 0x6ED9EBA1) >>> 0;
      k0 = (rotl32(v, 19) ^ 0x8F1BBCDC) >>> 0;
      break;
    }
    case "FEM_BDC_CODING": {
      // FDL Coding SecurityAccess Level 0x01/0x02 (FEM / BDC / KOMBI / HU_NBT)
      let v = (s0 ^ mask ^ 0xCAFD3000) >>> 0;
      v = (rotl32(v, 9) ^ 0x27012702) >>> 0;
      k0 = (v + 0x9E3779B9) >>> 0;
      break;
    }
    case "MG1_MD1_UDS": {
      // Bosch MG1CS003 / MG1CS201 / MD1CP002 (supports 4-byte or 8-byte seed)
      let v = (s0 ^ mask ^ 0x4D473143) >>> 0;
      v = (rotl32(v, 5) ^ 0xA55A3C89) >>> 0;
      v = (v + 0x3F1A7C25) >>> 0;
      k0 = (rotl32(v, 13) ^ 0x55AA1234) >>> 0;
      if (seedBytes.length >= 8) {
        const s1 =
          (((seedBytes[4] & 0xFF) << 24) |
            ((seedBytes[5] & 0xFF) << 16) |
            ((seedBytes[6] & 0xFF) << 8) |
            (seedBytes[7] & 0xFF)) >>>
          0;
        let k1 = (s1 ^ k0 ^ 0x7F4A7C15) >>> 0;
        k1 = (rotl32(k1, 15) + 0x165667B1) >>> 0;
        return [
          (k0 >>> 24) & 0xFF,
          (k0 >>> 16) & 0xFF,
          (k0 >>> 8) & 0xFF,
          k0 & 0xFF,
          (k1 >>> 24) & 0xFF,
          (k1 >>> 16) & 0xFF,
          (k1 >>> 8) & 0xFF,
          k1 & 0xFF,
        ];
      }
      break;
    }
    case "KWP2000_ESERIES":
    case "MEVD17_UDS":
    default: {
      let k = (s0 ^ mask) >>> 0;
      k = (rotl32(k, 5) ^ 0xA55A3C89) >>> 0;
      k = (k + 0x3F1A7C25) >>> 0;
      k0 = (rotl32(k, 13) ^ 0x55AA1234) >>> 0;
      break;
    }
  }

  return [
    (k0 >>> 24) & 0xFF,
    (k0 >>> 16) & 0xFF,
    (k0 >>> 8) & 0xFF,
    k0 & 0xFF,
  ];
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
    const { vin, ecuAddress, level, seedHex, ecuFamily } = body;

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

    // 3. Compute UDS / KWP2000 Security Access Key inside secure server environment
    const seedBytes = seedHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) ?? [];
    if (seedBytes.length < 2) {
      return new Response(
        JSON.stringify({ error: "Invalid seed length: must be at least 2 bytes" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const secretSalt = parseInt(Deno.env.get("ECU_SECRET_SALT") ?? "0x4B6D2A8F", 16);
    const resolvedFamily = resolveEcuFamily(ecuAddress, level, seedBytes.length, ecuFamily);
    const keyBytes = computeBmwSecurityKey(seedBytes, ecuAddress, level, secretSalt, resolvedFamily);
    const keyHex = keyBytes.map((b) => b.toString(16).padStart(2, "0")).join("");

    return new Response(
      JSON.stringify({
        keyHex,
        ecuFamily: resolvedFamily,
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
