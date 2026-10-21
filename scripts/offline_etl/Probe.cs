using System;
using System.Reflection;

class Probe {
    static void Main() {
        string dllPath = @"D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO\PSdZHandler.dll";
        Assembly asm = Assembly.LoadFrom(dllPath);
        Console.WriteLine("Loaded: " + asm.FullName);
        foreach (Type t in asm.GetTypes()) {
            if (t.Name.Contains("Mapper") || t.Name.Contains("Handler") || t.Name.Contains("Caf")) {
                Console.WriteLine("\nType: " + t.FullName);
                foreach (MethodInfo m in t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly)) {
                    Console.WriteLine("  Method: " + m.Name + " (" + string.Join(", ", Array.ConvertAll(m.GetParameters(), p => p.ParameterType.Name + " " + p.Name)) + ")");
                }
            }
        }
    }
}
