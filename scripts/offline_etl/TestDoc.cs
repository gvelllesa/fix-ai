using System;
using System.IO;
using System.Reflection;
using System.Collections.Generic;
using System.Xml.Linq;

class TestDoc {
    static void Main(string[] args) {
        string lproDir = @"D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO";
        Environment.CurrentDirectory = lproDir;
        
        AppDomain.CurrentDomain.AssemblyResolve += (sender, resolveArgs) => {
            string name = new AssemblyName(resolveArgs.Name).Name + ".dll";
            string path = Path.Combine(lproDir, name);
            if (File.Exists(path)) return Assembly.LoadFrom(path);
            return null;
        };

        try {
            string dllPath = Path.Combine(lproDir, "PSdZHandler.dll");
            Assembly asm = Assembly.LoadFrom(dllPath);
            Type managerType = asm.GetType("LauncherPRO.PSdZHandler.MapperManager");
            object mapper = managerType.GetMethod("GetMapper").Invoke(null, null);
            Type mapperType = mapper.GetType();
            mapperType.GetMethod("EnsureInitialized", BindingFlags.Public | BindingFlags.Instance | BindingFlags.NonPublic).Invoke(mapper, null);
            
            string cafdPath = @"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\PSdZ\data\psdzdata\swe\cafd\cafd_000017be.caf.005_016_064";
            XDocument doc = XDocument.Load(cafdPath);
            
            MethodInfo procMethod = mapperType.GetMethod("ProcessCafd", new Type[] { typeof(XDocument).MakeByRefType(), typeof(string) });
            object[] paramsArr = new object[] { doc, "F025" };
            procMethod.Invoke(mapper, paramsArr);
            XDocument result = (XDocument)paramsArr[0];
            
            Console.WriteLine("Root: " + result.Root.Name);
            foreach (var elem in result.Root.Descendants()) {
                if (elem.Name.LocalName.Contains("group") || elem.Name.LocalName.Contains("Function") || elem.Name.LocalName.Contains("param") || elem.Name.LocalName.Contains("storage")) {
                    Console.WriteLine("  Found: " + elem.Name.LocalName + " attr=" + string.Join(" ", Array.ConvertAll(new List<XAttribute>(elem.Attributes()).ToArray(), a => a.Name + "=" + a.Value)));
                    if (elem.Name.LocalName.Contains("Function")) break;
                }
            }
            
            // Check GetCache
            MethodInfo getCache = mapperType.GetMethod("GetCache");
            if (getCache != null) {
                object cacheObj = getCache.Invoke(mapper, new object[] { "cafd_000017be" });
                Console.WriteLine("GetCache('cafd_000017be') = " + (cacheObj != null ? cacheObj.GetType().FullName : "null"));
            }
        } catch (Exception ex) {
            Console.WriteLine("Error: " + ex);
        }
    }
}
