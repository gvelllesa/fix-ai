import java.io.*;
import java.sql.*;
import java.util.*;

public class ExtractKisData {
    private static final Map<Integer, String> PROCESS_CLASSES = new HashMap<>();
    static {
        PROCESS_CLASSES.put(1, "HWEL");
        PROCESS_CLASSES.put(2, "HWAP");
        PROCESS_CLASSES.put(3, "HWFR");
        PROCESS_CLASSES.put(4, "GWTB");
        PROCESS_CLASSES.put(5, "CAFD");
        PROCESS_CLASSES.put(6, "BTLD");
        PROCESS_CLASSES.put(7, "FLSL");
        PROCESS_CLASSES.put(8, "SWFL");
        PROCESS_CLASSES.put(9, "FAFP");
        PROCESS_CLASSES.put(10, "SWFF");
        PROCESS_CLASSES.put(11, "SWPF");
        PROCESS_CLASSES.put(12, "ONPS");
        PROCESS_CLASSES.put(13, "TLRT");
        PROCESS_CLASSES.put(14, "TPRG");
        PROCESS_CLASSES.put(15, "IBAD");
        PROCESS_CLASSES.put(16, "SWFK");
        PROCESS_CLASSES.put(17, "FCFA");
        PROCESS_CLASSES.put(18, "ENTD");
        PROCESS_CLASSES.put(19, "NAVD");
        PROCESS_CLASSES.put(20, "FCFN");
        PROCESS_CLASSES.put(21, "SWIP");
        PROCESS_CLASSES.put(22, "SWUP");
        PROCESS_CLASSES.put(23, "BLUP");
        PROCESS_CLASSES.put(24, "FLUP");
    }

    public static void main(String[] args) {
        String kiswbBase = "D:/D/BMW ISTA+ 4.59.30 Standalone-SetupFiles/BMW_Group_ISTA-FILES/BMW/ISPI/TRIC/ISTA/PSdZ/data/psdzdata/kiswb";
        String outputPath = "c:/Users/User/Desktop/ტესტ/fix-ai/assets/offline_db/kis_compatibility.json";
        
        File baseDir = new File(kiswbBase);
        File[] seriesDirs = baseDir.listFiles(File::isDirectory);
        if (seriesDirs == null) {
            System.err.println("Could not find kiswb directory: " + kiswbBase);
            return;
        }

        try {
            Class.forName("org.hsqldb.jdbcDriver");
        } catch (ClassNotFoundException e) {
            e.printStackTrace();
            return;
        }

        Map<String, Object> rootOutput = new LinkedHashMap<>();
        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("version", "1.0.0");
        metadata.put("source", "BMW ISTA 4.59.30 PSdZData KIS Knowledge Base");
        rootOutput.put("metadata", metadata);

        Map<String, Object> seriesDataMap = new LinkedHashMap<>();
        int totalEcus = 0;
        int totalIlevels = 0;
        int totalSgbmUnits = 0;

        for (File sdir : seriesDirs) {
            String seriesName = sdir.getName();
            File dbFile = new File(sdir, "KIS.script");
            if (!dbFile.exists()) continue;

            String url = "jdbc:hsqldb:file:" + sdir.getAbsolutePath().replace('\\', '/') + "/KIS;readonly=true;shutdown=true";
            System.out.println("Processing series: " + seriesName + " ...");

            Map<String, Object> sMap = new LinkedHashMap<>();
            try (Connection conn = DriverManager.getConnection(url, "SA", "");
                 Statement stmt = conn.createStatement()) {

                // 1. Chassis (EBR)
                List<Map<String, String>> chassisList = new ArrayList<>();
                try (ResultSet rs = stmt.executeQuery("SELECT NAME, BESCHREIBUNG FROM KIS.EBR")) {
                    while (rs.next()) {
                        Map<String, String> c = new LinkedHashMap<>();
                        c.put("name", rs.getString("NAME"));
                        c.put("desc", rs.getString("BESCHREIBUNG"));
                        chassisList.add(c);
                    }
                } catch (Exception ignored) {}
                sMap.put("chassis", chassisList);

                // 2. ECUs (BORDNETZTEILNEHMER)
                List<Map<String, Object>> ecuList = new ArrayList<>();
                try (ResultSet rs = stmt.executeQuery("SELECT ID, NAME, DIAGNOSEADRESSE, BESCHREIBUNG FROM KIS.BORDNETZTEILNEHMER ORDER BY DIAGNOSEADRESSE")) {
                    while (rs.next()) {
                        Map<String, Object> ecu = new LinkedHashMap<>();
                        int diagAddr = rs.getInt("DIAGNOSEADRESSE");
                        ecu.put("id", rs.getInt("ID"));
                        ecu.put("name", rs.getString("NAME"));
                        ecu.put("diag_addr_dec", diagAddr);
                        ecu.put("diag_addr_hex", "0x" + (diagAddr < 16 ? "0" : "") + Integer.toHexString(diagAddr).toUpperCase());
                        ecu.put("desc", rs.getString("BESCHREIBUNG"));
                        ecuList.add(ecu);
                        totalEcus++;
                    }
                }
                sMap.put("ecus", ecuList);

                // 3. I-Levels (ISTUFE)
                List<Map<String, Object>> ilevelList = new ArrayList<>();
                try (ResultSet rs = stmt.executeQuery("SELECT ID, NAME, PROGRAMMIERBAR, BESCHREIBUNG FROM KIS.ISTUFE ORDER BY ID DESC")) {
                    while (rs.next()) {
                        Map<String, Object> il = new LinkedHashMap<>();
                        il.put("id", rs.getInt("ID"));
                        il.put("name", rs.getString("NAME"));
                        il.put("programmable", "Y".equalsIgnoreCase(rs.getString("PROGRAMMIERBAR")));
                        il.put("desc", rs.getString("BESCHREIBUNG"));
                        ilevelList.add(il);
                        totalIlevels++;
                    }
                }
                sMap.put("i_levels", ilevelList);

                // 4. Sample SGBM Units (TECHNISCHEEINHEIT)
                List<Map<String, Object>> sgbmList = new ArrayList<>();
                try (ResultSet rs = stmt.executeQuery("SELECT SGBMID, SGBM_NR, MAJOR, MINOR, PATCH, FLASHBAR, BESCHREIBUNG FROM KIS.TECHNISCHEEINHEIT LIMIT 500")) {
                    while (rs.next()) {
                        long sgbmId = rs.getLong("SGBMID");
                        int pcCode = (int) ((sgbmId >>> 56) & 0xFF);
                        String pcName = PROCESS_CLASSES.getOrDefault(pcCode, "PC_" + pcCode);
                        
                        Map<String, Object> te = new LinkedHashMap<>();
                        te.put("sgbm_id_num", sgbmId);
                        te.put("sgbm_nr", rs.getString("SGBM_NR"));
                        te.put("process_class", pcName);
                        te.put("version", rs.getInt("MAJOR") + "." + rs.getInt("MINOR") + "." + rs.getInt("PATCH"));
                        te.put("flashable", "Y".equalsIgnoreCase(rs.getString("FLASHBAR")));
                        te.put("desc", rs.getString("BESCHREIBUNG"));
                        sgbmList.add(te);
                        totalSgbmUnits++;
                    }
                }
                sMap.put("sgbm_sample", sgbmList);

                seriesDataMap.put(seriesName, sMap);
            } catch (Exception ex) {
                System.err.println("  Error reading KIS for " + seriesName + ": " + ex.getMessage());
            }
        }

        metadata.put("total_series", seriesDataMap.size());
        metadata.put("total_ecus", totalEcus);
        metadata.put("total_i_levels", totalIlevels);
        metadata.put("total_sgbm_units", totalSgbmUnits);
        rootOutput.put("series", seriesDataMap);

        // Write output
        try {
            File outFile = new File(outputPath);
            outFile.getParentFile().mkdirs();
            try (PrintWriter out = new PrintWriter(new OutputStreamWriter(new FileOutputStream(outFile), "UTF-8"))) {
                writeJson(rootOutput, out, 0);
            }
            System.out.println("\nSUCCESS: Extracted KIS compatibility data to " + outputPath + " (" + (outFile.length() / 1024) + " KB)");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static void writeJson(Object obj, PrintWriter out, int indent) {
        String ind = "  ".repeat(indent);
        if (obj == null) {
            out.print("null");
        } else if (obj instanceof String) {
            out.print("\"" + escapeJson((String) obj) + "\"");
        } else if (obj instanceof Number || obj instanceof Boolean) {
            out.print(obj);
        } else if (obj instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) obj;
            out.println("{");
            int i = 0;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                out.print("  ".repeat(indent + 1) + "\"" + escapeJson(entry.getKey().toString()) + "\": ");
                writeJson(entry.getValue(), out, indent + 1);
                if (++i < map.size()) out.print(",");
                out.println();
            }
            out.print(ind + "}");
        } else if (obj instanceof List) {
            List<?> list = (List<?>) obj;
            out.println("[");
            for (int i = 0; i < list.size(); i++) {
                out.print("  ".repeat(indent + 1));
                writeJson(list.get(i), out, indent + 1);
                if (i + 1 < list.size()) out.print(",");
                out.println();
            }
            out.print(ind + "]");
        }
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\b", "\\b")
                .replace("\f", "\\f")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
