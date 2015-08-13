library dslink.system.utils;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;
import "package:intl/intl.dart";

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

Future<bool> setWifiNetwork(
  String interface, String ssid, String password) async {
  if (Platform.isMacOS) {
    var args = ["-setairportnetwork", interface, ssid];

    if (password != null && password.isNotEmpty) {
      args.add(password);
    }

    var result = await Process.run("networksetup", args);

    if (result.exitCode != 0) {
      return false;
    }

    return true;
  } else {
    var args = [interface, "essid", ssid];

    if (password != null && password.isNotEmpty) {
      args.addAll(["key", password]);
    }

    var result = await Process.run("iwconfig", args);

    if (result.exitCode != 0) {
      return false;
    }

    return true;
  }
}

Future startAccessPoint() async {
  if (await isProbablyDGBox()) {
    await exec("bash", args: ["tools/dreamplug/wireless.sh", "base"]);
  } else {
    await Process.run("hotspotd", ["start"]);
  }
}

Future stopAccessPoint() async {
  if (await isProbablyDGBox()) {
    await exec("bash", args: ["tools/dreamplug/wireless.sh", "client"]);
  } else {
    await Process.run("hotspotd", ["stop"]);
    await Process.run("pkill", ["hostapd"]);
  }
}

Future<bool> isAccessPointOn() async {
  if (await isProbablyDGBox()) {
    return (await exec("ifconfig", args: ["uap0"])).exitCode != 1;
  }

  return (await Process.run("pgrep", ["hostapd"])).exitCode == 0;
}

Future<bool> isWifiInterface(String name) async {
  if (Platform.isMacOS) {
    var result = await Process.run("networksetup", ["-listallhardwareports"]);

    if (result.exitCode != 0) {
      return false;
    }

    List<String> lines =
    result.stdout.split("\n").map((x) => x.trim()).toList();

    lines.removeWhere((x) => x.isEmpty);

    var buff = [];

    for (var line in lines) {
      if (line.startsWith("Device: ${name}")) {
        var hp = buff[buff.length - 1];
        return hp.contains("Wi-Fi");
      } else {
        buff.add(line);
      }
    }

    return false;
  } else {
    var result = await Process.run("iwconfig", [name]);

    if (result.exitCode != 0) {
      return false;
    } else {
      return true;
    }
  }
}

Future configureNetworkAutomatic(String interface) async {
  if (Platform.isMacOS) {
    var service = await getNetworkServiceForInterface(interface);
    var args = ["-setdhcp", service];

    return Process.run("networksetup", args).then((result) {
      return result.exitCode == 0;
    });
  }

  var resultA =
  await Process.run("ifconfig", [interface, "0.0.0.0", "0.0.0.0"]);
  if (resultA.exitCode != 0) {
    return false;
  }

  await Process.run("dhclient", ["-r", interface]);
  var resultB = await Process.run("dhclient", [interface]);

  return resultB.exitCode == 0;
}

Future configureNetworkManual(
  String interface, String ip, String netmask, String gateway) async {
  if (Platform.isWindows) {
    throw new Exception("Unsupported on Windows");
  }

  if (Platform.isMacOS) {
    var service = await getNetworkServiceForInterface(interface);
    var args = ["-setmanual", service, ip, netmask, gateway];

    return Process.run("networksetup", args).then((result) {
      return result.exitCode == 0;
    });
  }

  await Process.run("killall", ["dhclient"]);

  var gw = await getGatewayIp(interface);

  await Process.run("route", ["add", "del", "default", "gw", gw, interface]);

  var resultB =
  await Process.run("route", ["add", "default", "gw", gateway, interface]);
  if (resultB.exitCode != 0) {
    return false;
  }

  var resultC =
  await Process.run("ifconfig", [interface, ip, "netmask", netmask]);

  return resultC.exitCode == 0;
}

Future<String> getWifiNetwork(String interface) async {
  if (Platform.isMacOS) {
    var result =
    await Process.run("networksetup", ["-getairportnetwork", interface]);
    if (result.exitCode != 0) {
      return null;
    } else {
      return result.stdout.trim().replaceAll("Current Wi-Fi Network: ", "");
    }
  } else {
    var result = await Process.run("iwconfig", [interface]);
    if (result.exitCode != 0) {
      return null;
    } else {
      try {
        var line = result.stdout.split("\n").first;
        var regex = new RegExp(r'ESSID\:"(.*)"');
        return regex.firstMatch(line).group(1);
      } catch (e) {
        return null;
      }
    }
  }
}

Future<String> getNetworkServiceForInterface(String interface) async {
  var result = await Process.run("networksetup", ["-listnetworkserviceorder"]);
  List<String> lines = result.stdout.split("\n");
  var results = {};
  lines.where((x) => x.startsWith("(Hardware Port:")).forEach((x) {
    var mn = x.substring(1, x.length - 1).split(",");
    results[mn[1].split(":")[1].trim()] = mn[0].split(":")[1].trim();
  });
  return results[interface];
}

Future<List<WifiNetwork>> scanWifiNetworks(String interface) async {
  if (Platform.isMacOS) {
    var airport =
    "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport";
    var result = await Process.run(airport, [interface, "scan"]);
    if (result.exitCode != 0) {
      return [];
    }
    String out = result.stdout;
    List<String> lines = out.split("\n");
    var firstLine = lines.removeAt(0);
    var ssidEnd = firstLine.indexOf("SSID") + 4;

    var networks = [];

    for (var line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      var ssid = line.substring(0, ssidEnd).trim();
      var hasSecurity = !line.contains("NONE");
      var network = new WifiNetwork(ssid, hasSecurity);
      networks.add(network);
    }

    return networks;
  } else {
    var result = await Process.run("iwlist", [interface, "scan"]);

    if (result.exitCode != 0) {
      return [];
    }

    List<String> lines = result.stdout.split("\n");
    lines.removeAt(0);

    var buff = [];
    var networks = [];
    for (var line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      if (buff.isEmpty && line.trim().startsWith("Cell ")) {
        continue;
      }

      if (line.trim().startsWith("Cell ") || line == lines.last) {
        var content = buff.join("\n");
        var regex = new RegExp(r'ESSID\:"(.*)"');
        var ssid = regex.firstMatch(content).group(1);
        var hasSecurity = content.contains("Encryption key:on");
        var network = new WifiNetwork(ssid, hasSecurity);
        networks.add(network);
        buff.clear();
        continue;
      }

      buff.add(line);
    }

    return networks;
  }
}

class WifiNetwork {
  final String ssid;
  final bool hasSecurity;

  WifiNetwork(this.ssid, this.hasSecurity);

  List toRows() => [ssid, hasSecurity];
}

class System {
  static void reboot() {
    var result = Process.runSync("reboot", []);

    if (result.exitCode != 0) {
      print("ERROR: Failed to reboot.");
    }
  }

  static void shutdown() {
    var result = Process.runSync(
      isUnix ? "poweroff" : "shutdown", isUnix ? [] : ["-h", "now"]);

    if (result.exitCode != 0) {
      print("ERROR: Failed to shutdown. Exit Code: ${result.exitCode}");
    }
  }
}

bool get isUnix => Platform.isLinux || Platform.isMacOS;

Future<List<String>> getCurrentNameServers() async {
  var file = new File("/etc/resolv.conf");

  if (!(await file.exists())) {
    return [];
  }

  var lines = (await file.readAsLines())
  .map((x) => x.trim())
  .where((x) => x.isNotEmpty && !x.startsWith("#"))
  .toList();

  return lines
  .where((x) => x.startsWith("nameserver "))
  .map((x) => x.replaceAll("nameserver ", ""))
  .toList();
}

Future<String> getCurrentTimezone() async {
  var type = await FileSystemEntity.type("/etc/localtime", followLinks: false);

  if (type == FileSystemEntityType.LINK) {
    var link = new Link("/etc/localtime");

    return (await link.resolveSymbolicLinks()).substring("/usr/share/zoneinfo/".length);
  } else if (type == FileSystemEntityType.FILE) {
    var mf = new File("/etc/localtime");
    var tz = await getAllTimezones();
    List<File> files = tz.map((x) => new File("/usr/share/zoneinfo/${x}")).toList();
    var codec = new Utf8Codec(allowMalformed: true);
    var mfb = await mf.readAsString(encoding: codec);
    var i = 0;
    for (var file in files) {
      try {
        if (await file.readAsString(encoding: codec) == mfb) {
          return tz[i];
        }
      } catch (e) {}
      i++;
    }
  }

  return "UTC";
}

Future<List<String>> getAllTimezones() async {
  var dir = new Directory("/usr/share/zoneinfo");

  if (!(await dir.exists())) {
    return ["UTC"];
  }

  var files = await dir.list(recursive: true).toList();
  var zones = [];

  for (var file in files) {
    if (file is! File) {
      continue;
    }

    if (file.path.contains(".")) {
      continue;
    }

    var name = file.path.substring("/usr/share/zoneinfo/".length);

    if (name[0].toLowerCase() == name[0]) {
      continue;
    }

    zones.add(name);
  }

  zones.sort();

  return zones;
}

bool _hasAptUpdated = false;

Future installPackage(String pkg) async {
  if (Platform.isMacOS) {
    throw new Exception("Installing Packages on Mac OS X is not supported.");
  }

  var isArchLinux = await fileExists("/etc/arch-release");
  var isDebian = await fileExists("/usr/bin/apt-get");

  runCommand(String cmd, List<String> args) async {
    var result = await exec(cmd, args: args, inherit: true);
    if (result.exitCode != 0) {
      print("Failed to install package: ${pkg}");
      exit(1);
    }
  }

  if (isArchLinux) {
    await runCommand("pacman", ["-S", pkg]);
  } else if (isDebian) {
    if (!_hasAptUpdated) {
      await runCommand("apt-get", ["update"]);
      _hasAptUpdated = true;
    }

    await runCommand("apt-get", ["install", pkg]);
  } else {
    print("Unknown Linux Distribution. Please install the package '${pkg}' with your distribution's package manager.");
    exit(1);
  }
}

Future<bool> fileExists(String path) async => await new File(path).exists();

Future setCurrentTimezone(String name) async {
  var path = "/usr/share/zoneinfo/${name}";
  var link = new Link("/etc/localtime");
  if (await link.exists()) {
    await link.delete();
  }

  await link.create(path);
}

Future<bool> isProbablyDGBox() async {
  if (!Platform.isLinux) {
    return false;
  }

  if (_dgbox != null) {
    return _dgbox;
  }
  var file = new File("/proc/cpuinfo");
  var content = await file.readAsString();

  return _dgbox = content.contains("Feroceon 88FR131 rev 1 (v5l)");
}

File _dnsMasqFile = new File("/etc/dnsmaq.conf");

Future<String> readCaptivePortalConfig() async {
  return await _dnsMasqFile.readAsString();
}

Future writeCaptivePortalConfig(String config) async {
  await _dnsMasqFile.writeAsString(config);
}

Future<bool> hasCaptivePortalInConfig() async {
  var content = await _dnsMasqFile.readAsString();
  if (content.contains("## Begin DSA Host DSLink ##")) {
    return true;
  }
  return false;
}

bool _dgbox;

String getDnsMasqCaptivePortal(String address) {
  return [
    "## Begin DSA Host DSLink ##",
    "address=/#/${address}",
    "## End DSA Host DSLink ##"
  ].join("\n");
}

Future restartDnsMasq() async {
  if (await fileExists("/etc/init.d/dnsmasq")) {
    await exec("service", args: ["dnsmasq", "restart"]);
  } else {
    await exec("systemctl", args: ["restart", "dnsmasq"]);
  }
}

String removeCaptivePortalConfig(String input) {
  var lines = input.split("\n");
  var out = [];
  var flag = false;
  for (var line in lines) {
    if (line == "## Begin DSA Host DSLink ##" || line == "## End DSA Host DSLink ##") {
      flag = !flag;
    } else if (!flag) {
      out.add(line);
    }
  }
  return out.join("\n");
}

Future<String> getGatewayIp(String interface) async {
  if (Platform.isMacOS) {
    var no = await Process.run("networksetup", ["-getinfo", await getNetworkServiceForInterface(interface)]);
    String out = no.stdout;
    var lines = out.split("\n");
    for (var line in lines) {
      if (line.startsWith("Router: ")) {
        return line.substring("Router: ".length);
      }
    }
    return "unknown";
  }

  var ro = await Process.run("route", ["-n"]);
  List<String> lines = ro.stdout.toString().split("\n");
  lines.removeAt(0);
  lines.removeAt(0);
  for (var line in lines) {
    var parts = line.replaceAll("  ", "").replaceAll("\t", " ").split(" ");
    parts = parts.map((x) => x.trim()).toList();
    parts.removeWhere((x) => x.isEmpty);

    if (parts.length < 7) {
      continue;
    }

    var iface = parts[7];
    if (iface == interface && parts[1] != "0.0.0.0") {
      return parts[1];
    }
  }
  return "0.0.0.0";
}

Future<String> getSubnetIp(String interface) async {
  if (Platform.isMacOS) {
    var no = await Process.run("networksetup", ["-getinfo", await getNetworkServiceForInterface(interface)]);
    String out = no.stdout;
    var lines = out.split("\n");
    lines.removeAt(0);
    lines.removeAt(0);
    for (var line in lines) {
      if (line.startsWith("Subnet mask: ")) {
        return line.substring("Subnet mask: ".length);
      }
    }
    return "unknown";
  }

  var ro = await Process.run("route", ["-n"]);
  List<String> lines = ro.stdout.toString().split("\n");
  for (var line in lines) {
    var parts = reflix(line).split(" ");
    parts = parts.map((x) => x.trim()).toList();
    parts.removeWhere((x) => x.isEmpty);

    if (parts.length < 7) {
      continue;
    }

    var iface = parts[7];
    if (iface == interface && parts[2] != "0.0.0.0") {
      return parts[2];
    }
  }
  return "0.0.0.0";
}

String reflix(String n) {
  while (n.contains("  ")) {
    n = n.replaceAll("  ", " ");
  }

  n = n.replaceAll("\t", " ");
  return n;
}

String createSystemTime(DateTime date) {
  var format = new DateFormat("MMddHHmmyyyy.ss");
  return format.format(date);
}
