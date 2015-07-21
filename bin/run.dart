import "dart:async";
import "dart:io";

import "package:dslink/dslink.dart";
import "package:dslink/io.dart";

LinkProvider link;

main(List<String> args) async {
  final Map<String, String> PLATFORMS = {
    "macos": "Mac",
    "linux": "Linux",
    "android": "Android",
    "windows": "Windows"
  };

  final Map<String, dynamic> NODES = {
    "Platform": {
      r"$type": "string",
      "?value": PLATFORMS.containsKey(Platform.operatingSystem) ? PLATFORMS[Platform.operatingSystem] : Platform.operatingSystem
    },
    "Processor_Count": {
      r"$name": "Processor Count",
      r"$type": "number",
      "?value": Platform.numberOfProcessors
    },
    "Poll_Rate": {
      r"$name": "Poll Rate",
      r"$type": "number",
      r"$writable": "write",
      "?value": 1,
      "@unit": "seconds",
      "@precision": 0
    },
    "CPU_Usage": {
      r"$name": "CPU Usage",
      r"$type": "number",
      "@unit": "%"
    },
    "Memory_Usage": {
      r"$name": "Memory Usage",
      r"$type": "number",
      "@unit": "%"
    },
    "Total_Memory": {
      r"$name": "Total Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    "Free_Memory": {
      r"$name": "Free Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    "Used_Memory": {
      r"$name": "Used Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    "Disk_Usage": {
      r"$name": "Disk Usage",
      r"$type": "number",
      "@unit": "%"
    },
    "Total_Disk_Space": {
      r"$name": "Total Disk Space",
      r"$type": "number",
      "@unit": "mb"
    },
    "Used_Disk_Space": {
      r"$name": "Used Disk Space",
      r"$type": "number",
      "@unit": "mb"
    },
    "Free_Disk_Space": {
      r"$name": "Free Disk Space",
      r"$type": "number",
      "@unit": "mb"
    }
  };

  link = new LinkProvider(
      args,
      "System-",
      defaultNodes: NODES,
      encodePrettyJson: true,
      autoInitialize: false
  );

  link.init();

  for (var key in NODES.keys) {
    if (key == "Poll_Rate") {
      continue;
    }

    link.removeNode("/${key}");
    link.addNode("/${key}", NODES[key]);
  }

  await getMemSizeBytes();
  await update(false);

  link.onValueChange("/Poll_Rate").listen((ValueUpdate u) async {
    var val = u.value;

    if (val is String) {
      val = 1;
    }

    interval = new Duration(seconds: val.toInt());
    update();
    await link.saveAsync();
  });

  link.syncValue("/Poll_Rate");
  link.connect();
}

Duration interval = new Duration(seconds: 1000);

SimpleNode cpuUsageNode = link["/CPU_Usage"];
SimpleNode freeMemoryNode = link["/Free_Memory"];
SimpleNode usedMemoryNode = link["/Used_Memory"];
SimpleNode totalMemoryNode = link["/Total_Memory"];
SimpleNode memoryUsageNode = link["/Memory_Usage"];
SimpleNode diskUsageNode = link["/Disk_Usage"];
SimpleNode totalDiskSpaceNode = link["/Total_Disk_Space"];
SimpleNode availableDiskSpaceNode = link["/Free_Disk_Space"];
SimpleNode usedDiskSpaceNode = link["/Used_Disk_Space"];

update([bool shouldScheduleUpdate = true]) async {
  if (shouldScheduleUpdate && timer != null) {
    timer.cancel();
  }

  if (shouldScheduleUpdate || cpuUsageNode.hasSubscriber) {
    var usage = await getCpuUsage();
    cpuUsageNode.updateValue(usage);
  }

  totalMemoryNode.updateValue(totalMemoryMegabytes);

  if (shouldScheduleUpdate || freeMemoryNode.hasSubscriber || memoryUsageNode.hasSubscriber || usedMemoryNode.hasSubscriber) {
    var free = await getFreeMemory();
    var used = totalMemoryMegabytes - free;
    var percentage = (used / totalMemoryMegabytes) * 100;
    freeMemoryNode.updateValue(free);
    usedMemoryNode.updateValue(used);
    memoryUsageNode.updateValue(percentage);
  }

  if (shouldScheduleUpdate || diskUsageNode.hasSubscriber || totalDiskSpaceNode.hasSubscriber || availableDiskSpaceNode.hasSubscriber || usedDiskSpaceNode.hasSubscriber) {
    var usage = await getDiskUsage();
    diskUsageNode.updateValue(usage["percentage"]);
    totalDiskSpaceNode.updateValue(usage["total"]);
    usedDiskSpaceNode.updateValue(usage["used"]);
    availableDiskSpaceNode.updateValue(usage["available"]);
  }

  if (shouldScheduleUpdate) {
    timer = new Timer(interval, update);
  }
}

Future<Map<String, num>> getDiskUsage() async {
  if (Platform.isLinux || Platform.isMacOS) {
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
  }

  return {};
}

Timer timer;

const Map<String, int> POLL_RATE = const {
  "1 second": 1000,
  "2 seconds": 2000,
  "3 seconds": 3000,
  "4 seconds": 4000,
  "5 seconds": 5000
};

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
      var guest = num.parse(parts[9]);
      var guest_nice = num.parse(parts[10]);

      var used = user + nice + system + irq + softrig + steal;
      var idlez = idle + iowait;

      return [used, idlez, used + idlez];
    }

    var first = await fetch();
    await new Future.delayed(new Duration(milliseconds: 500));
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
  }

  return null;
}

Future<num> getFreeMemory() async {
  if (Platform.isLinux) {
    var result = await Process.run("free", const ["-b"]);
    List<String> lines = result.stdout.split("\n");
    var line = lines[1];
    var parts = line.split(" ");

    parts.removeWhere((x) => x.trim().isEmpty);

    var bytes = num.parse(parts[result.stdout.contains("available") ? 6 : 3]);

    return convertBytesToMegabytes(bytes);
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
  }

  return null;
}

double totalMemoryMegabytes;

int _memSizeBytes;

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
    return null;
  }

  totalMemoryMegabytes = _memSizeBytes / 1024 / 1024;

  return _memSizeBytes;
}

num convertBytesToMegabytes(num bytes) {
  return (bytes / 1024) / 1024;
}
