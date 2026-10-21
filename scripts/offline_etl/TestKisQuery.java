import java.sql.*;

public class TestKisQuery {
    public static void main(String[] args) {
        String dbPath = "D:/D/BMW ISTA+ 4.59.30 Standalone-SetupFiles/BMW_Group_ISTA-FILES/BMW/ISPI/TRIC/ISTA/PSdZ/data/psdzdata/kiswb/F025/KIS";
        String url = "jdbc:hsqldb:file:" + dbPath + ";readonly=true;shutdown=true";
        try {
            Class.forName("org.hsqldb.jdbcDriver");
            Connection conn = DriverManager.getConnection(url, "SA", "");
            Statement stmt = conn.createStatement();
            
            System.out.println("=== KIS.EBR (Chassis) ===");
            ResultSet rs = stmt.executeQuery("SELECT * FROM KIS.EBR");
            while (rs.next()) {
                System.out.println("  EBR: " + rs.getString("NAME") + " | " + rs.getString("BESCHREIBUNG"));
            }
            
            System.out.println("\n=== KIS.BORDNETZTEILNEHMER (Sample ECUs) ===");
            rs = stmt.executeQuery("SELECT ID, NAME, DIAGNOSEADRESSE, BESCHREIBUNG FROM KIS.BORDNETZTEILNEHMER LIMIT 10");
            while (rs.next()) {
                System.out.println("  ECU: " + rs.getString("NAME") + " (0x" + Integer.toHexString(rs.getInt("DIAGNOSEADRESSE")).toUpperCase() + ") - " + rs.getString("BESCHREIBUNG"));
            }

            System.out.println("\n=== KIS.ISTUFE (Latest I-Levels) ===");
            rs = stmt.executeQuery("SELECT NAME, PROGRAMMIERBAR, BESCHREIBUNG FROM KIS.ISTUFE ORDER BY ID DESC LIMIT 8");
            while (rs.next()) {
                System.out.println("  I-Level: " + rs.getString("NAME") + " | Prog=" + rs.getString("PROGRAMMIERBAR") + " | " + rs.getString("BESCHREIBUNG"));
            }
            
            conn.close();
            System.out.println("\nSUCCESS: KIS database connection verified!");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
