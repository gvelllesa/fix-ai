using System;
using System.IO;
using System.Reflection;
using System.Xml.Linq;

class TestMapper {
    static void Main(string[] args) {
        string lproDir = @"D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO";
        Environment.CurrentDirectory = lproDir;
        
        AppDomain.CurrentDomain.AssemblyResolve += (sender, resolveArgs) => {
            string name = new AssemblyName(resolveArgs.Name).Name + ".dll";
            string path = Path.Combine(lproDir, name);
            if (File.Exists(path)) {
                return Assembly.LoadFrom(path);
            }
            return null;
        };

        try {
            string dllPath = Path.Combine(lproDir, "PSdZHandler.dll");
            Assembly asm = Assembly.LoadFrom(dllPath);
            Type managerType = asm.GetType("LauncherPRO.PSdZHandler.MapperManager");
            MethodInfo getMapper = managerType.GetMethod("GetMapper", BindingFlags.Public | BindingFlags.Static);
            object mapper = getMapper.Invoke(null, null);
            Console.WriteLine("Mapper retrieved: " + mapper);

            Type mapperType = mapper.GetType();
            MethodInfo init = mapperType.GetMethod("EnsureInitialized", BindingFlags.Public | BindingFlags.Instance | BindingFlags.NonPublic);
            if (init != null) {
                init.Invoke(mapper, null);
                Console.WriteLine("Mapper EnsureInitialized succeeded!");
            }
            
            // Test processing a CAFD file
            string cafdPath = @"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\PSdZ\data\psdzdata\swe\cafd\cafd_000017be.caf.005_016_064";
            if (File.Exists(cafdPath)) {
                XDocument doc = XDocument.Load(cafdPath);
                Console.WriteLine("Loaded CAFD doc, root=" + doc.Root.Name);
                
                MethodInfo procMethod = mapperType.GetMethod("ProcessCafd", new Type[] { typeof(XDocument).MakeByRefType(), typeof(string) });
                if (procMethod != null) {
                    object[] paramsArr = new object[] { doc, "F025" };
                    procMethod.Invoke(mapper, paramsArr);
                    XDocument processedDoc = (XDocument)paramsArr[0];
                    Console.WriteLine("ProcessCafd returned! Child count=" + processedDoc.Root.Elements().ToString());
                    foreach (var elem in processedDoc.Root.Elements()) {
                        Console.WriteLine("  Element: " + elem.Name.LocalName);
                    }
                }
            }
        } catch (Exception ex) {
            Console.WriteLine("Exception: " + ex);
            if (ex.InnerException != null) {
                Console.WriteLine("Inner Exception: " + ex.InnerException);
            }
        }
    }
}
