library dslink.system.utils;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;

typedef void ProcessHandler(Process process);
typedef void OutputHandler(String str);

Stdin get _stdin => stdin;

class BetterProcessResult extends ProcessResult {
  final String output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output)
  : super(pid, exitCode, stdout, stderr);
}

Future<BetterProcessResult> exec(String executable,
                                 {List<String> args: const [], String workingDirectory,
                                 Map<String, String> environment, bool includeParentEnvironment: true,
                                 bool runInShell: false, stdin, ProcessHandler handler,
                                 OutputHandler stdoutHandler, OutputHandler stderrHandler,
                                 OutputHandler outputHandler, File outputFile, bool inherit: false,
                                 bool writeToBuffer: false}) async {
  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  try {
    Process process = await Process.start(executable, args,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell);

    if (raf != null) {
      await raf.writeln(
        "[${currentTimestamp}] == Executing ${executable} with arguments ${args} (pid: ${process.pid}) ==");
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    process.stdout.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        ob.write(str);
        buff.write(str);
      }

      if (stdoutHandler != null) {
        stdoutHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stdout.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    process.stderr.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        eb.write(str);
        buff.write(str);
      }

      if (stderrHandler != null) {
        stderrHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stderr.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    } else if (inherit) {
      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
    }

    var code = await process.exitCode;
    var pid = process.pid;

    if (raf != null) {
      await raf
      .writeln("[${currentTimestamp}] == Exited with status ${code} ==");
      await raf.flush();
      await raf.close();
    }

    return new BetterProcessResult(
      pid, code, ob.toString(), eb.toString(), buff.toString());
  } finally {
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

Future<String> findExecutable(String name) async {
  var paths =
  Platform.environment["PATH"].split(Platform.isWindows ? ";" : ":");
  var tryFiles = [name];

  if (Platform.isWindows) {
    tryFiles.addAll(["${name}.exe", "${name}.bat"]);
  }

  for (var p in paths) {
    if (Platform.environment.containsKey("HOME")) {
      p = p.replaceAll("~/", Platform.environment["HOME"]);
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

Future<bool> isPortOpen(int port, {String host: "0.0.0.0"}) async {
  try {
    ServerSocket server = await ServerSocket.bind(host, port);
    await server.close();
    return true;
  } catch (e) {
    return false;
  }
}

String get currentTimestamp {
  return new DateTime.now().toString();
}

String fseType(FileSystemEntity entity) {
  if (entity is Directory) {
    return "directory";
  } else if (entity is File) {
    return "file";
  } else if (entity is Link) {
    return "link";
  }

  return "unknown";
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

Future<double> getCpuUsage() async {
  if (Platform.isLinux) {
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
    return (await getWMICNumber("CPU get LoadPercentage")).toDouble();
  }

  return 0.0;
}

Future<num> getFreeMemory() async {
  if (Platform.isLinux) {
    try {
      var result = await Process.run("free", const ["-b"]);
      List<String> lines = result.stdout.split("\n");
      var line = lines[1];
      var parts = line.split(" ");

      parts.removeWhere((x) => x.trim().isEmpty);

      var bytes = num.parse(parts[result.stdout.contains("available") ? 6 : 3]);

      return convertBytesToMegabytes(bytes);
    } catch (e) {
      return 0;
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

    return ((free + spec) * pageSize) / 1024 / 1024;
  } else if (Platform.isWindows) {
    return await getWMICNumber("OS get FreePhysicalMemory") / 1024;
  }

  return 0;
}

double totalMemoryMegabytes;

int _memSizeBytes;


Future<String> getSystemArchitecture() async {
  try {
    if (Platform.isLinux || Platform.isMacOS) {
      var result = await Process.run("uname", const ["-m"]);
      return result.stdout.trim();
    }
  } catch (e) {
  }
  return "Unknown";
}

Future<int> getProcessCount() async {
  try {
    if (Platform.isWindows) {
      var result = await Process.run("wmic", "PROCESS LIST BRIEF".split(" "));
      var lines = result.stdout.split("\n").where((String x) => x.isNotEmpty).skip(1).toList();
      return lines.length;
    } else {
      var result = await Process.run("ps", Platform.isMacOS ?
      const ["-A", "-o", "pid"] :
      const ["-A", "--no-headers"]);

      if (result.exitCode != 0) {
        throw "Error";
      }

      return result.stdout
        .split("\n")
        .length;
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
      var result = await getWMICNumber("PATH Win32_Battery Get Availability");
      return result == 3;
    }else {
      return false;
    }
  } catch (e) {
    return false;
  }
}

RegExp PERCENTAGE_REGEX = new RegExp(r"([0-9\.]+)%\;");

Future<num> getBatteryPercentage() async {
  try {
    if (Platform.isMacOS) {
      var result = await Process.run("pmset", const ["-g", "batt"]);
      if (result.exitCode != 0) {
        throw "Fail";
      }

      return num.parse(PERCENTAGE_REGEX.firstMatch(result.stdout).group(1));
    } else if (Platform.isWindows) {
      return await getWMICNumber("path Win32_Battery Get EstimatedChargeRemaining");
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
  } else if (Platform.isLinux) {
    var result = await Process.run("free", const ["-b"]);
    List<String> lines = result.stdout.split("\n");
    var line = lines[1];
    var parts = line.split(" ");
    parts.removeWhere((x) => x.trim().isEmpty);
    var bytes = num.parse(parts[1]);

    _memSizeBytes = bytes;
  } else {
    _memSizeBytes = await getWMICNumber("ComputerSystem get TotalPhysicalMemory");
    _memSizeBytes = _memSizeBytes;
  }

  totalMemoryMegabytes = _memSizeBytes / 1024 / 1024;

  return _memSizeBytes;
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
    var result = await getWMICNumber("path Win32_TemperatureProbe Get Availability");
    return _supportsCpuTemperature = (result == 3);
  }

  return _supportsCpuTemperature = false;
}

Future<String> getOperatingSystemVersion() async {
  try {
    if (Platform.isMacOS) {
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
      if (result.exitCode != 0) {
        return 0.0;
      }
      List<String> lines = result.stdout.split("\n");
      return num.parse(lines.first.split(" ")[2].split("°")[0]);
    } catch (e) {
      return 0.0;
    }
  }

  if (Platform.isLinux) {
    try {
      var result = await Process.run("sensors", const ["coretemp-isa-0000"]);
      if (result.exitCode != 0) {
        return 0.0;
      }
      List<String> lines = result.stdout.split("\n");
      String line = lines.firstWhere((x) => x.startsWith("Physical id 0:"), orElse: () => null);
      if (line == null) {
        return 0.0;
      }
      String x = line.substring("Physical id 0:".length).trim();

      return num.parse(x.split("°")[0]);
    } catch (e) {
      return 0.0;
    }
  }

  if (Platform.isWindows) {
    return await getWMICNumber("path Win32_TemperatureProbe Get CurrentReading");
  }

  return 0.0;
}

num convertBytesToMegabytes(num bytes) {
  return (bytes / 1024) / 1024;
}

Future<int> getWMICNumber(String query) async {
  try {
    var result = await Process.run("wmic", query.split(" "));
    var lines = result.stdout.split("\n").where((String x) => x.isNotEmpty).skip(1).toList();
    return int.parse(lines[0]);
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

    return {
      "used": used,
      "available": available,
      "total": total,
      "percentage": (used / total) * 100
    };
  }

  return {};
}
