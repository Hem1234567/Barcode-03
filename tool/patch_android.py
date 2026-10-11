"""Adds permissions + app label, and installs the native printer transport."""
import re, pathlib, glob

p = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = p.read_text()
perms = """
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
    <uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>
    <uses-feature android:name="android.hardware.usb.host" android:required="false"/>
"""
if "BLUETOOTH_CONNECT" not in s:
    s = re.sub(r"(<manifest[^>]*>)", r"\1" + perms, s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Barcode Studio"', s, count=1)
p.write_text(s)
print("Manifest patched")

files = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
assert files, "MainActivity.kt not found"
target = pathlib.Path(files[0])
pkg = re.search(r"^package\s+([\w.]+)", target.read_text(), re.M).group(1)
target.write_text(pathlib.Path("tool/MainActivity.kt").read_text().replace("PKG_PLACEHOLDER", pkg))
print("Native transport installed in", target)

# ---- force every plugin to compile against a recent Android SDK ----
KTS_BLOCK = '''

// forceCompileSdk: some plugins still compile against old Android SDKs
subprojects {
    val forceCompileSdk = Action<Project> {
        val ext = extensions.findByName("android")
        if (ext != null) {
            for (name in listOf("setCompileSdkVersion", "compileSdkVersion", "setCompileSdk")) {
                try {
                    val m = ext.javaClass.methods.firstOrNull { m ->
                        m.name == name && m.parameterCount == 1 &&
                            (m.parameterTypes[0].name == "int" || m.parameterTypes[0].name == "java.lang.Integer")
                    }
                    if (m != null) {
                        m.invoke(ext, 36)
                        break
                    }
                } catch (e: Exception) {
                }
            }
        }
    }
    if (state.executed) forceCompileSdk.execute(this) else afterEvaluate(forceCompileSdk)
}
'''
b = pathlib.Path("android/build.gradle.kts")
if b.exists():
    t = b.read_text()
    if "forceCompileSdk" not in t:
        b.write_text(t + KTS_BLOCK)
        print("compileSdk override added to android/build.gradle.kts")
else:
    print("WARNING: android/build.gradle.kts not found")
