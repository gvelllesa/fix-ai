import java.sql.*;

public class TestKisSgbm {
    public static void main(String[] args) {
        String dbPath = "D:/D/BMW ISTA+ 4.59.30 Standalone-SetupFiles/BMW_Group_ISTA-FILES/BMW/ISPI/TRIC/ISTA/PSdZ/data/psdzdata/kiswb/F025/KIS";
        String url = "jdbc:hsqldb:file:" + dbPath + ";readonly=true;shutdown=true";
        try {
            Class.forName("org.hsqldb.jdbcDriver");
            Connection conn = DriverManager.getConnection(url, "SA", "");
            Statement stmt = conn.createStatement();
            
            System.out.println("=== Sample TECHNISCHEEINHEIT ===");
            ResultSet rs = stmt.executeQuery("SELECT ID, SGBMID, SGBM_NR, MAJOR, MINOR, PATCH, FLASHBAR, BESCHREIBUNG FROM KIS.TECHNISCHEEINHEIT LIMIT 10");
            while (rs.next()) {
                System.out.println("  TE: " + rs.getString("SGBM_NR") + " | ID=" + rs.getLong("SGBMID") + 
                                   " | Ver=" + rs.getInt("MAJOR") + "." + rs.getInt("MINOR") + "." + rs.getInt("PATCH") + 
                                   " | Flash=" + rs.getString("FLASHBAR") + " | " + rs.getString("BESCHREIBUNG"));
            }

            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
