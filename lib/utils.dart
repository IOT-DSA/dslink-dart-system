library dslink.system.utils;

import "dart:async";
import "dart:io";
import "dart:math";

import "package:path/path.dart" as pathlib;

final RegExp PERCENTAGE_REGEX = new RegExp(r"([0-9\.]+)%\;");
final bool useOldLinuxCpuUsageCalculator = false;
bool useLinuxFreeCommand = true;
bool offsetLinuxDiskCache = true;

Future<String> findExecutable(String name) async {
  var paths = Platform.environment["PATH"].split(Platform.isWindows ? ";" : ":");
  var tryFiles = [name];

  if (Platform.isWindows) {
    tryFiles.addAll(["${name}.exe", "${name}.bat"]);
  }

  for (var p in paths) {
    if (Platform.environment.containsKey("HOME")) {
      var home = Platform.environment["HOME"];
      if (!home.endsWith("/")) {
        home += "/";
      }
      p = p.replaceAll("~/", home);
    }

    var dir = new Directory(pathlib.normalize(p));

    if (!(await dir.exists())) {
      continue;
    }

    for (var t in tryFiles) {
      var file = new File("${dir.path}/${t}");

      if (await file.exists()) {
        return file.path;
      }
    }
  }

  return null;
}

Future<bool> isInSecureMode() async {
  return await new File(".secureMode").exists() || await new File("../../.secureMode").exists();
}

Future<bool> fileExists(String path) async {
  return await new File(path).exists();
}

Future<Map<String, String>> parseVariableFile(String path) async {
  var file = new File(path);
  var lines = await file.readAsLines();
  var map = <String, String>{};
  for (var line in lines) {
    if (line.trim().startsWith("#")) {
      continue;
    }
    var split = line.split("=").map((x) => x.trim()).toList();
    if (split.length <= 1) {
      continue;
    }

    var key = split[0];
    var value = split.skip(1).join("=");
    if (value.startsWith('"')) {
      value = value.substring(1);
    }

    if (value.endsWith('"')) {
      value = value.substring(0, value.length - 1);
    }

    map[key] = value;
  }

  return map;
}

File procStatFile = new File("/proc/stat");

num _prevTotal = 0;
num _prevIdle = 0;
num _prevLoad = 0;

onErrorNull(input) => null;

Future<double> getCpuUsage() async {
  if (Platform.isLinux || Platform.isAndroid) {
    if (useOldLinuxCpuUsageCalculator) {
      Future<List<int>> fetch() async {
        var lines = await procStatFile.readAsLines();
        String line = lines.firstWhere((x) {
          return x.startsWith("cpu ");
        }, orElse: () => null);

        if (line == null) {
          return null;
        }

        var parts = line.split(" ");

        parts.removeWhere((x) => x.isEmpty);

        var user = num.parse(parts[1]);
        var nice = num.parse(parts[2]);
        var system = num.parse(parts[3]);
        var idle = num.parse(parts[4]);
        var iowait = num.parse(parts[5]);
        var irq = num.parse(parts[6]);
        var softrig = num.parse(parts[7]);
        var steal = num.parse(parts[8]);
        var used = user + nice + system + irq + softrig + steal;
        var idlez = idle + iowait;

        return [used, idlez, used + idlez];
      }

      var first = await fetch();
      await new Future.delayed(const Duration(milliseconds: 500));
      var second = await fetch();

      var total = second[2];
      var oldTotal = first[2];
      var idle = second[1];
      var oldIdle = first[1];

      return ((total - oldTotal) - (idle - oldIdle)) / (total - oldTotal) * 100;
    } else {
      var content = await procStatFile.readAsString();
      var split = content.split(" ");
      var d = [];
      var idx = 0;
      var count = 0;
      while (count < 4) {
        var t = num.parse(split[idx], onErrorNull);
        if (t != null) {
          count++;
          d.add(t);
        }
        idx++;
      }

      num idle = d[3];
      num total = d[0] + d[1] + d[2];
      num load = 0;

      if (_prevTotal != 0) {
        var  p = ((total - _prevTotal) / ((total + idle - _prevTotal - _prevIdle)));
        if (p == double.NAN) {
          p = 0.0;
        }
        load = p * 100;
      }

      if (load == double.NAN) {
        load = 0.0;
      }

      load = min(100, max(0, load));

      _prevLoad = load;
      _prevTotal = total;
      _prevIdle = idle;

      split = content = null;
      d.clear();

      return load;
    }
  } else if (Platform.isMacOS) {
    var result = await Process.run("top", const ["-o", "cpu", "-l", "1", "-stats", "cpu"]);
    List<String> lines = result.stdout.split("\n");
    var str = lines.firstWhere((x) => x.startsWith("CPU usage: "), orElse: () => null);
    if (str == null) {
      return null;
    }

    var parts = str.split(" ");
    var l = parts[2];
    var r = parts[4];

    l = l.substring(0, l.length - 1);
    r = r.substring(0, r.length - 1);

    var a = num.parse(l);
    var b = num.parse(r);

    return a + b;
  } else if (Platform.isWindows) {
    return (await getWmicNumber("CPU get LoadPercentage")).toDouble();
  }

  return 0.0;
}

bool _hasFreeCommand;

final File PROC_MEMINFO = new File("/proc/meminfo");

Future<num> getFreeMemory() async {
  if (Platform.isLinux || Platform.isAndroid) {
    if (_hasFreeCommand == null) {
      _hasFreeCommand = Platform.isAndroid ?
        false :
        (await findExecutable("free")) != null;
    }

    if (_hasFreeCommand && useLinuxFreeCommand) {
      try {
        var result = await Process.run("free", const ["-b"]);
        List<String> lines = result.stdout.split("\n");

        if (offsetLinuxDiskCache) {
          var lid = (result.stdout.contains("available") ||
            !result.stdout.contains("-/+ buffers/cache")) ? 1 : 2;
          var line = lines[lid];
          var parts = line.split(" ");

          parts.removeWhere((x) => x.trim().isEmpty);

          var bytes = num.parse(parts[(lid == 1) ? 6 : 3]);

          lines.clear();
          lines = null;
          parts = null;

          return bytes;
        } else {
          var lid = 1;
          var line = lines[lid];
          var parts = line.split(" ");
          parts.removeWhere((x) => x.trim().isEmpty);
          var bytes = num.parse(parts[3]);

          lines.clear();
          lines = null;
          parts = null;

          return bytes;
        }
      } catch (e) {
        return 0;
      }
    } else {
      try {
        var lines = await PROC_MEMINFO.readAsLines();
        var line = lines.firstWhere((line) {
          return line.startsWith("MemFree:");
        });
        var partial = line.replaceAll(" ", "").split(":")[1];
        if (partial.endsWith("kB")) {
          partial = partial.substring(0, partial.length - 2);
        }
        lines.clear();
        lines = null;
        return num.parse(partial) * 1024; // KB => Bytes
      } catch (e) {
        print(e);
        return 0;
      }
    }
  } else if (Platform.isMacOS) {
    var result = await Process.run("vm_stat", []);
    List<String> lines = result.stdout.split("\n");
    var firstLine = lines.first;
    var pageSize = int.parse(firstLine.substring(45, firstLine.lastIndexOf(" bytes)")).trim());

    int get(String n) {
      var m = lines.firstWhere((x) => x.startsWith(n + ": "), orElse: () => null);

      if (m == null) {
        return null;
      }

      m = m.replaceAll(" ", "").replaceAll(".", "");
      return int.parse(m.split(":").last);
    }

    var free = get("Pages free");
    var spec = get("Pages speculative");

    lines.clear();
    lines = null;

    return ((free + spec) * pageSize);
  } else if (Platform.isWindows) {
    return await getWmicNumber("OS get FreePhysicalMemory") * 1024; // KB => Bytes
  }

  return 0;
}

double totalMemoryMegabytes;

int _memSizeBytes;


Future<String> getSystemArchitecture() async {
  if (Platform.isAndroid) {
    var result = await Process.run("getprop", const ["ro.product.cpu.abi"]);
    return result.stdout.toString().trim();
  }

  if (Platform.isWindows) {
    var hw = await getWmicString("OS get OSArchitecture");
    return hw.toString().trim();
  }

  try {
    if (Platform.isLinux || Platform.isMacOS) {
      var result = await Process.run("uname", const ["-m"]);
      return result.stdout.toString().trim();
    } else if (Platform.isAndroid) {
      var result = await Process.run("getprop", const ["ro.product.cpu.abi"]);
      return result.stdout.toString().trim();
    }
  } catch (e) {
  }
  return "Unknown";
}

Future<int> getProcessCount() async {
  if (Platform.isAndroid) {
    return 0;
  }

  try {
    if (Platform.isWindows) {
      var result = await Process.run("wmic", "PROCESS LIST BRIEF".split(" "));
      var lines = result.stdout.split("\n").where((String x) => x.isNotEmpty).skip(1).toList();
      var count = lines.length;
      lines.clear();
      lines = null;

      return count;
    } else {
      var result = await Process.run("ps", Platform.isMacOS ?
        const ["-A", "-o", "pid"] :
        const ["-A", "--no-headers"]);

      if (result.exitCode != 0) {
        throw "Error";
      }

      var len = result.stdout
        .split("\n")
        .length;
      result = null;
      return len;
    }
  } catch (e) {
    return 0;
  }
}

Future<bool> hasBattery() async {
  try {
    if (Platform.isMacOS) {
      var result = await Process.run("pmset", ["-g", "batt"]);
      if (result.exitCode != 0) {
        return false;
      }

      if (!result.stdout.contains("Battery")) {
        return false;
      }

      return true;
    } else if (Platform.isWindows) {
      var result = await getWmicNumber("PATH Win32_Battery Get Availability");
      return result == 3;
    } else {
      return false;
    }
  } catch (e) {
    return false;
  }
}

Future<num> getBatteryPercentage() async {
  try {
    if (Platform.isMacOS) {
      var result = await Process.run("pmset", const ["-g", "batt"]);
      if (result.exitCode != 0) {
        throw "Fail";
      }

      return num.parse(PERCENTAGE_REGEX.firstMatch(result.stdout).group(1));
    } else if (Platform.isWindows) {
      return await getWmicNumber("path Win32_Battery Get EstimatedChargeRemaining");
    } else {
      return 0;
    }
  } catch (e) {
    return 0;
  }
}

Future<int> getMemSizeBytes() async {
  if (_memSizeBytes != null) {
    return _memSizeBytes;
  }

  if (Platform.isMacOS) {
    var result = await Process.run("sysctl", const ["-n", "hw.memsize"]);
    _memSizeBytes = int.parse(result.stdout);
  } else if (Platform.isLinux || Platform.isAndroid) {
    if (_hasFreeCommand == null) {
      _hasFreeCommand = Platform.isAndroid ?
        false :
        (await findExecutable("free")) != null;
    }

    if (_hasFreeCommand) {
      var result = await Process.run("free", const ["-b"]);
      List<String> lines = result.stdout.split("\n");
      var line = lines[1];
      var parts = line.split(" ");
      parts.removeWhere((x) => x.trim().isEmpty);
      var bytes = num.parse(parts[1]);

      lines.clear();
      parts.clear();
      result = line = lines = parts = null;

      _memSizeBytes = bytes;
    } else {
      var lines = await PROC_MEMINFO.readAsLines();
      var line = lines.firstWhere((line) {
        return line.startsWith("MemFree:");
      });
      var partial = line.replaceAll(" ", "").split(":")[1];
      if (partial.endsWith("kB")) {
        partial = partial.substring(0, partial.length - 2);
      }
      _memSizeBytes = (num.parse(partial) * 1024).toInt();
    }
  } else {
    _memSizeBytes = await getWmicNumber("ComputerSystem get TotalPhysicalMemory");
  }

  totalMemoryMegabytes = _memSizeBytes / 1024 / 1024;

  return _memSizeBytes;
}

Future<Map<String, Map<String, dynamic>>> getFanStats() async {
  try {
    if (Platform.isMacOS && await findExecutable("istats") != null) {
      var map = {};
      var result = await Process.run("istats", const ["fan", "speed"]);
      String out = result.stdout;
      List<String> lines = out.split("\n");
      for (String line in lines) {
        if (!line.startsWith("Fan ")) {
          continue;
        }
        List<String> parts = line.split(" ");
        int id = int.parse(parts[1]);
        num speed = num.parse(parts[3]);
        map["Fan ${id}"] = {
          "Speed": speed
        };
        line = null;
      }
      result = out = null;
      lines.clear();
      return map;
    }
  } catch (e) {}
  return const {};
}

Future<bool> doesSupportCPUTemperature() async {
  if (_supportsCpuTemperature != null) {
    return _supportsCpuTemperature;
  }

  if (Platform.isMacOS) {
    var path = await findExecutable("istats");
    if (path != null) {
      return _supportsCpuTemperature = true;
    }
  }

  if (Platform.isLinux) {
    var path = await findExecutable("sensors");
    if (path != null) {
      var temp = await getCpuTemp();
      return _supportsCpuTemperature = temp != 0.0;
    }
  }

  if (Platform.isWindows) {
    var result = await dumpWmicQuery("path Win32_TemperatureProbe");
    return _supportsCpuTemperature = result.isNotEmpty;
  }

  return _supportsCpuTemperature = false;
}

Future<String> getOperatingSystemVersion() async {
  try {
    if (Platform.isAndroid) {
      var result = await Process.run("getprop", const ["ro.build.version.release"]);
      return "Android " + result.stdout.toString().trim();
    } else if (Platform.isMacOS) {
      var result = await Process.run(
        "system_profiler", const ["SPSoftwareDataType", "-detailLevel", "mini"]);
      String out = result.stdout;
      if (OSX_VERSION_REGEX.hasMatch(out)) {
        return OSX_VERSION_REGEX.firstMatch(out).group(1);
      }
    } else if (Platform.isLinux) {
      if (await fileExists("/etc/arch-release")) {
        return "Arch Linux";
      } else if (await fileExists("/etc/lsb-release")) {
        var data = await parseVariableFile("/etc/lsb-release");
        if (data["DISTRIB_DESCRIPTION"] != null && data["DISTRIB_DESCRIPTION"].isNotEmpty) {
          return data["DISTRIB_DESCRIPTION"];
        } else if (data["DISTRIB_ID"] != null && data["DISTRIB_ID"].isNotEmpty) {
          return data["DISTRIB_ID"];
        }
      } else {
        var result = await Process.run("uname", const ["-r"]);
        if (result.exitCode != 0) {
          return "Linux";
        }
        return "Linux ${result.stdout.toString().trim()}";
      }
    } else if (Platform.isWindows) {
      var result = await getWmicString("OS get Caption");
      if (result == null) {
        return "Unknown";
      }
      return result;
    }
  } catch (e) {}

  return "Unknown";
}

RegExp OSX_VERSION_REGEX = new RegExp(r"System Version\: (.*)");

bool _supportsCpuTemperature;

Future<num> getCpuTemp() async {
  if (Platform.isMacOS) {
    try {
      var result = await Process.run("istats", const ["cpu", "temp"]);
      result = null;
      if (result.exitCode != 0) {
        return 0.0;
      }
      List<String> lines = result.stdout.split("\n");
      var temp = num.parse(lines.first.split(" ")[2].split("°")[0]);
      lines.clear();
      result = lines = null;
      return temp;
    } catch (e) {
      return 0.0;
    }
  }

  if (Platform.isLinux) {
    try {
      var result = await Process.run("sensors", const ["coretemp-isa-0000"]);
      if (result.exitCode != 0) {
        result = null;
        return 0.0;
      }
      List<String> lines = result.stdout.split("\n");
      String line = lines.firstWhere(
        (x) => x.startsWith("Physical id 0:"),
          orElse: () => null
      );
      if (line == null) {
        return 0.0;
      }
      String x = line.substring("Physical id 0:".length).trim();

      var deg = num.parse(x.split("°")[0]);
      lines.clear();
      lines = result = line = x = null;
      return deg;
    } catch (e) {
      return 0.0;
    }
  }

  if (Platform.isWindows) {
    var result = await dumpWmicQuery(
      "path Win32_PerfFormattedData_Counters_ThermalZoneInformation"
    );

    if (result.isNotEmpty) {
      var out = 0.0;

      for (var m in result) {
        var x = m["Temperature"] is num ? m["Temperature"] : 0.0;
        x = (x / 10.0);
        out += x;
      }

      return out / result.length;
    }
  }

  return 0.0;
}

num convertBytesToMegabytes(num bytes) {
  return (bytes / 1024) / 1024;
}

Future<String> getWmicString(String query) async {
  try {
    var result = await Process.run("wmic", query.split(" "));
    var out = result.stdout.toString()
      .split("\n")
      .skip(1)
      .join("\n")
      .trim();

    return out;
  } catch (e) {
    return null;
  }
}

Future<num> getWmicNumber(String query) async {
  try {
    var result = await Process.run("wmic", query.split(" "));
    var lines = result.stdout
      .split("\n")
      .where((String x) => x.isNotEmpty)
      .skip(1)
      .toList();
    return num.parse(lines[0]);
  } catch (e) {
    return 0;
  }
}

Future<Map<String, num>> getDiskUsage() async {
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      var result = await Process.run("df", const ["/"]);
      List<String> lines = result.stdout.split("\n");
      lines.removeWhere((x) => x.trim().isEmpty);
      String line = lines.last;

      var parts = line.split(" ");

      parts.removeWhere((x) => x.isEmpty);

      var used = int.parse(parts[2]) / 1024;
      var available = int.parse(parts[3]) / 1024;
      var total = int.parse(parts[1]) / 1024;

      lines.clear();
      parts.clear();
      lines = line = parts = null;

      return {
        "used": used,
        "available": available,
        "total": total,
        "percentage": (used / total) * 100
      };
    } catch (e) {
      return {};
    }
  } else if (Platform.isWindows) {
    var result = await Process.run("fsutil", ["volume", "diskfree", "C:"]);
    List<String> lines = result.stdout.split("\n");
    int getBytesFor(int n) {
      return int.parse(lines[n].split(":")[1].trim());
    }

    var total = getBytesFor(1) / 1024 / 1024;
    var available = getBytesFor(2) / 1024 / 1024;
    var used = total - available;

    result = null;
    lines.clear();
    lines = null;

    return {
      "used": used,
      "available": available,
      "total": total,
      "percentage": (used / total) * 100
    };
  }

  return {};
}

Future<bool> doesSupportModel() async {
  try {
    if (Platform.isMacOS) {
      return (await findExecutable("system_profiler")) != null;
    } else if (Platform.isLinux) {
      return await new Directory("/sys/devices/virtual/dmi/id").exists();
    } else if (Platform.isAndroid) {
      return true;
    } else if (Platform.isWindows) {
      return true;
    }
  } catch (e) {}
  return false;
}

Future<String> getHardwareModel() async {
  try {
    if (Platform.isMacOS) {
      return await getMacSystemProfilerProperty("SPHardwareDataType", "Model Name");
    } else if (Platform.isLinux) {
      var file = new File("/sys/devices/virtual/dmi/id/product_name");
      var content = await file.readAsString();
      if (content.trim() == "To be filled by O.E.M.") {
        file = new File("/sys/devices/virtual/dmi/id/board_name");
        content = await file.readAsString();
      }
      return content.trim();
    } else if (Platform.isAndroid) {
      var result = await Process.run("getprop", const ["ro.product.display"]);
      return result.stdout.toString().trim();
    } else if (Platform.isWindows) {
      var hw = await getWmicString("CPU get Name");

      if (hw != null) {
        return hw;
      }
    }
  } catch (e) {
  }
  return "Unknown";
}

Future<bool> doesSupportHardwareIdentifier() async {
  if (Platform.isMacOS) {
    return (await findExecutable("system_profiler")) != null;
  } else if (Platform.isAndroid) {
    return true;
  }
  return false;
}

Future<String> getHardwareIdentifier() async {
  try {
    if (Platform.isMacOS) {
      return await getMacSystemProfilerProperty("SPHardwareDataType", "Hardware UUID");
    } else if (Platform.isAndroid) {
      var result = await Process.run("getprop", const ["ro.serialno"]);
      return result.stdout.toString().trim();
    }
  } catch (e) {
  }
  return "Unknown";
}

Map<String, String> _macProfilerCache = {};

Future<String> getMacSystemProfilerProperty(String dataType, String name) async {
  if (!_macProfilerCache.containsKey(dataType)) {
    var result = await Process.run("system_profiler", [
      "-detailLevel",
      "full",
      dataType
    ]);

    _macProfilerCache[dataType] = result.stdout;
  }
  String out = _macProfilerCache[dataType];
  var needle = "${name}: ";
  var idx = out.indexOf(needle);
  var start = idx + needle.length;
  return out.substring(start, out.indexOf("\n", start)).trim();
}

Future<bool> doesSupportProcessorName() async {
  return Platform.isMacOS || Platform.isLinux || Platform.isAndroid;
}

Future<bool> doesSupportOpenFilesCount() async {
  return Platform.isMacOS || Platform.isLinux;
}

Future<String> getProcessorName() async {
  try {
    if (Platform.isMacOS) {
      return await getMacSystemProfilerProperty("SPHardwareDataType", "Processor Name");
    } else if (Platform.isLinux) {
      var file = new File("/proc/cpuinfo");
      var lines = await file.readAsLines();
      var line = lines.firstWhere((line) => line.startsWith("model name"), orElse: () => null);
      if (line != null) {
        var parts = line.split(":");
        return parts.skip(1).join(":");
      }
    }
  } catch (e) {}
  return "Unknown";
}

Future<int> getOpenFilesCount() async {
  try {
    if (Platform.isMacOS) {
      var result = await Process.run("sysctl", const ["-n", "kern.num_files"]);
      var count = int.parse(result.stdout.toString().trim());
      result = null;
      return count;
    } else if (Platform.isLinux) {
      var result = await Process.run("sysctl", const ["-n", "fs.file-nr"]);
      String out = result.stdout;
      var count = int.parse(out.split(WHITESPACE).first.trim());
      result = out = null;
      return count;
    }
  } catch (e) {}
  return 0;
}

final RegExp WHITESPACE = new RegExp(r"\t|\n| ");
final RegExp ROOT_DEV_REGEX = new RegExp(r"root=([^ ]*)");

class ProcessInfo {
  final int pid;

  ProcessInfo(this.pid);
}

Future<String> getRootDeviceName() async {
  if (!Platform.isLinux) {
    return null;
  }

  try {
    var file = new File("/proc/cmdline");
    var cmdline = await file.readAsString();
    if (!cmdline.contains("root=")) {
      return null;
    }
    String device = ROOT_DEV_REGEX.firstMatch(cmdline).group(1);
    if (device.startsWith("/dev/")) {
      device = device.substring(5);
    }

    return device;
  } catch (e) {
    return null;
  }
}

bool getInputBoolean(input) {
  if (input == null) {
    return false;
  }

  if (input == true) {
    return true;
  }

  if (input == false) {
    return false;
  }

  if (input is String) {
    return const [
      "true",
      "yes",
      "on",
      "y"
    ].contains(input.toLowerCase());
  }

  return false;
}

Future<bool> doesSupportPerProcessStats() async {
  return (Platform.isLinux || Platform.isMacOS) &&
    (await findExecutable("ps")) != null;
}

Future<String> getProcessCommand(int pid) async {
  try {
    var result = await Process.run("ps", [
      "-p",
      pid.toString(),
      "-o",
      "command"
    ]);

    if (result.exitCode != 0) {
      throw "Failed";
    }

    List<String> lines = result.stdout.toString().split("\n");
    lines.removeWhere((a) => a.trim().isEmpty);

    return lines.last.trim();
  } catch (e) {
  }

  return "Unknown";
}

Future<int> getProcessMemoryUsage(int pid) async {
  try {
    var result = await Process.run("ps", [
      "-p",
      pid.toString(),
      "-o",
      "rss"
    ]);

    if (result.exitCode != 0) {
      throw "Failed";
    }

    List<String> lines = result.stdout.toString().split("\n");
    lines.removeWhere((a) => a.trim().isEmpty);

    return int.parse(lines.last.trim()) * 1024;
  } catch (e) {
  }

  return -1;
}

Future<int> getProcessOpenFiles(int pid) async {
  if (Platform.isMacOS) {
    return -1;
  }

  try {
    var dir = new Directory("/proc/${pid}/fd");
    return await dir.list(followLinks: false).length;
  } catch (e) {
  }

  return -1;
}

Future<List<Map<String, dynamic>>> dumpWmicQuery(String section) async {
  var args = [];
  args.addAll(section.split(" "));
  args.addAll([
    "GET",
    "/format:list"
  ]);

  var result = await Process.run(
    "wmic",
    args
  );

  var list = [];
  var sections = result.stdout.toString().split("\n\n");
  var current = {};

  for (String section in sections) {
    for (String line in section.split("\n")) {
      if (!line.contains("=")) {
        continue;
      }

      String key = line.substring(0, line.indexOf("="));

      if (current.containsKey(key)) {
        list.add(current);
        current = {};
      }

      var value = line.substring(line.indexOf("=") + 1).trim();

      try {
        value = num.parse(value);
      } catch (e) {}

      if (value == "TRUE" || value == "FALSE") {
        value = value == "TRUE";
      }

      current[key] = value;
    }

    if (current.isNotEmpty) {
      list.add(current);
      current = {};
    }
  }

  return list;
}
