import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:dslink_system/utils.dart";
import "package:dslink_system/io.dart";
import "package:args/args.dart";

LinkProvider link;

bool enableDsaDiagnosticMode = false;

typedef Action(Map<String, dynamic> params);
typedef ActionWithPath(Path path, Map<String, dynamic> params);

addAction(handler) {
  return (String path) {
    var p = new Path(path);
    return new SimpleActionNode(path, (params) {
      if (handler is Action) {
        return handler(params);
      } else if (handler is ActionWithPath) {
        return handler(p, params);
      } else {
        throw new Exception("Bad Action Handler");
      }
    });
  };
}

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
      "?value": PLATFORMS.containsKey(Platform.operatingSystem) ?
        PLATFORMS[Platform.operatingSystem] :
        Platform.operatingSystem
    },
    "Processor_Count": {
      r"$name": "Processor Count",
      r"$type": "number",
      "?value": Platform.numberOfProcessors
    },
    "Processes": {
      r"$name": "Processes",
      r"$type": "number",
      "?value": 0
    },
    "Operating_System": {
      r"$name": "Operating System",
      r"$type": "string",
      "?value": await getOperatingSystemVersion()
    },
    "Poll_Rate": {
      r"$name": "Poll Rate",
      r"$type": "number",
      r"$writable": "write",
      "?value": Platform.numberOfProcessors == 1 ? 3 : 1,
      "@unit": "seconds"
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
    "System_Time": {
      r"$name": "System Time",
      r"$type": "string"
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
    },
    "Architecture": {
      r"$type": "string",
      "?value": await getSystemArchitecture()
    },
    "Hostname": {
      r"$type": "string",
      "?value": Platform.localHostname
    },
    "Execute_Command": {
      r"$invokable": "write",
      r"$is": "executeCommand",
      r"$name": "Execute Command",
      r"$params": [
        {
          "name": "command",
          "type": "string"
        }
      ],
      r"$result": "values",
      r"$columns": [
        {
          "name": "output",
          "type": "string",
          "editor": "textarea"
        },
        {
          "name": "exitCode",
          "type": "number"
        }
      ]
    },
    "Execute_Command_Stream": {
      r"$invokable": "write",
      r"$is": "executeCommandStream",
      r"$name": "Execute Command Stream",
      r"$result": "stream",
      r"$params": [
        {
          "name": "command",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "type",
          "type": "string"
        },
        {
          "name": "value",
          "type": "dynamic"
        }
      ]
    }
  };

  if (await doesSupportCPUTemperature()) {
    NODES["CPU_Temperature"] = {
      r"$name": "CPU Temperature",
      "@unit": "°C",
      r"$type": "number"
    };
  }

  if (await doesSupportHardwareIdentifier()) {
    NODES["Hardware_Identifier"] = {
      r"$name": "Hardware Identifier",
      r"$type": "string",
      "?value": await getHardwareIdentifier()
    };
  }

  if (await doesSupportModel()) {
    NODES["Model"] = {
      r"$name": "Model",
      r"$type": "string",
      "?value": await getHardwareModel()
    };
  }

  if (await doesSupportProcessorName()) {
    NODES["Processor_Model"] = {
      r"$name": "Processor Model",
      r"$type": "string",
      "?value": await getProcessorName()
    };
  }

  if (await doesSupportOpenFilesCount()) {
    NODES["Open_Files"] = {
      r"$name": "Open Files",
      r"$type": "number"
    };
  }

  if (await hasBattery()) {
    NODES["Battery_Level"] = {
      r"$name": "Battery Level",
      r"$type": "number",
      "@unit": "%"
    };
  }

  if (Platform.isMacOS) {
    NODES["Run_AppleScript"] = {
      r"$is": "runAppleScript",
      r"$name": "Run AppleScript",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "script",
          "type": "string",
          "editor": "textarea"
        }
      ],
      r"$result": "values",
      r"$columns": [
        {
          "name": "output",
          "type": "string",
          "editor": "textarea"
        }
      ]
    };
  }

  link = new LinkProvider(
    args,
    "System-",
    defaultNodes: NODES,
    encodePrettyJson: true,
    autoInitialize: false,
    profiles: {
      "executeCommand": addAction((Map<String, dynamic> params) async {
        var cmd = params["command"];
        var result = await exec(Platform.isWindows ? "cmd.exe" : "bash", args: [
          Platform.isWindows ? "/C" : "-c",
          cmd
        ], writeToBuffer: true, outputHandler: (out) {
          logger.finest(out);
        });

        return {
          "output": result.output,
          "exitCode": result.exitCode
        };
      }),
      "runAppleScript": addAction((Map<String, dynamic> params) async {
        var result = await exec(
          "osascript",
          args: ["-e", params["script"]],
          writeToBuffer: true
        );

        return {
          "output": result.output
        };
      }),
      "executeCommandStream": addAction((Map<String, dynamic> params) async {
        var cmd = params["command"];
        Process process;
        var controller = new StreamController(onCancel: () {
          if (process != null) {
            process.kill();
          }
        });

        Process.start(Platform.isWindows ? "cmd.exe" : "bash", [
          Platform.isWindows ? "/C" : "-c",
          cmd
        ]).then((Process proc) {
          process = proc;
          proc.stdout
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen((line) {
            if (!controller.isClosed) {
              controller.add({
                "type": "stdout",
                "value": line
              });
            }
          });

          proc.stderr
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen((line) {
            if (!controller.isClosed) {
              controller.add({
                "type": "stderr",
                "value": line
              });
            }
          });

          proc.exitCode.then((code) {
            if (!controller.isClosed) {
              controller.add({
                "type": "exit",
                "value": code
              });
            }
            controller.close();
          });
        });

        return controller.stream;
      })
    }
  );

  var argp = new ArgParser();
  argp.addOption("linux_use_free_command", callback: (value) {
    useLinuxFreeCommand = getInputBoolean(value);
  }, help: "Use the 'free' command on Linux",
    defaultsTo: "true",
    valueHelp: "true/false");

  argp.addOption("offset_memory_disk_cache", callback: (value) {
    offsetLinuxDiskCache = getInputBoolean(value);
  }, help: "Offset Memory Usage based on Disk Cache",
    valueHelp: "true/false",
    defaultsTo: "true");

  argp.addOption("enable_dsa_diagnostics_mode", callback: (value) {
    enableDsaDiagnosticMode = getInputBoolean(value);
  }, help: "Enable DSA Diagnostic Mode",
    valueHelp: "true/false",
    defaultsTo: "false");
  link.configure(argp: argp);
  link.init();

  for (var key in NODES.keys) {
    if (key == "Poll_Rate") {
      continue;
    }

    link.removeNode("/${key}");
    link.addNode("/${key}", NODES[key]);
  }

  await getMemSizeBytes();
  totalMemoryNode.updateValue(totalMemoryMegabytes);
  await update(false);

  link.onValueChange("/Poll_Rate").listen((ValueUpdate u) async {
    var val = u.value;

    if (val is String) {
      try {
        val = num.parse(val);
      } catch (e) {
        val = 1;
      }
    }

    interval = new Duration(milliseconds: (val * 1000).toInt());
    if (timer != null) {
      timer.dispose();
      timer = null;
    }
    timer = Scheduler.safeEvery(interval, update);
    await link.saveAsync();
  });

  Scheduler.every(Interval.HALF_SECOND, () {
    if (systemTimeNode.hasSubscriber) {
      systemTimeNode.updateValue(new DateTime.now().toString());
    }
  });

  link.syncValue("/Poll_Rate");

  {
    var stats = await getFanStats();
    var fans = {};
    for (var key in stats.keys) {
      fans[key.replaceAll(" ", "_")] = {
        r"$name": key,
        "Speed": {
          r"$type": "number",
          "?value": stats[key]["Speed"],
          "@unit": "RPM"
        }
      };
    }

    if (fans.isNotEmpty) {
      SimpleNode fansNode = link.addNode("/Fans", fans);
      fansNode.serializable = false;

      for (var key in fans.keys) {
        fanNodes[key] = link.getNode("/Fans/${key.replaceAll(" ", "_")}");
      }
    }
  }

  link.connect();

  if (enableDsaDiagnosticMode == true && (Platform.isLinux || Platform.isMacOS)) {
    var tryPaths = [
      "../../.pids",
      ".pids"
    ];

    for (String p in tryPaths) {
      var file = new File(p);
      if (await file.exists()) {
        pidTrackingFile = file;
      }
    }
  }
}

File pidTrackingFile;
Set<int> lastPidSet = new Set<int>();
Duration interval = new Duration(seconds: 2);

SimpleNode cpuUsageNode = link["/CPU_Usage"];
SimpleNode freeMemoryNode = link["/Free_Memory"];
SimpleNode usedMemoryNode = link["/Used_Memory"];
SimpleNode totalMemoryNode = link["/Total_Memory"];
SimpleNode memoryUsageNode = link["/Memory_Usage"];
SimpleNode diskUsageNode = link["/Disk_Usage"];
SimpleNode totalDiskSpaceNode = link["/Total_Disk_Space"];
SimpleNode availableDiskSpaceNode = link["/Free_Disk_Space"];
SimpleNode usedDiskSpaceNode = link["/Used_Disk_Space"];
SimpleNode cpuTemperatureNode = link["/CPU_Temperature"];
SimpleNode processCountNode = link["/Processes"];
SimpleNode batteryLevelNode = link["/Battery_Level"];
SimpleNode systemTimeNode = link["/System_Time"];
SimpleNode openFilesNode = link["/Open_Files"];
Map<String, SimpleNode> fanNodes = {};

update([bool shouldScheduleUpdate = true]) async {
  if (!shouldScheduleUpdate && timer != null) {
    timer.dispose();
    timer = null;
  }

  try {
    if (!shouldScheduleUpdate ||
        cpuUsageNode.hasSubscriber) {
      var usage = await getCpuUsage();
      cpuUsageNode.updateValue(usage);
    }

    if (!shouldScheduleUpdate ||
        freeMemoryNode.hasSubscriber ||
        memoryUsageNode.hasSubscriber ||
        usedMemoryNode.hasSubscriber) {
      var total = await getMemSizeBytes();
      var free = await getFreeMemory();
      var used = total - free;
      var percentage = (used / total) * 100;
      freeMemoryNode.updateValue(convertBytesToMegabytes(free));
      usedMemoryNode.updateValue(convertBytesToMegabytes(used));
      memoryUsageNode.updateValue(percentage);
    }

    if (!shouldScheduleUpdate ||
        diskUsageNode.hasSubscriber ||
        totalDiskSpaceNode.hasSubscriber ||
        availableDiskSpaceNode.hasSubscriber ||
        usedDiskSpaceNode.hasSubscriber) {
      var usage = await getDiskUsage();
      diskUsageNode.updateValue(usage["percentage"]);
      totalDiskSpaceNode.updateValue(usage["total"]);
      usedDiskSpaceNode.updateValue(usage["used"]);
      availableDiskSpaceNode.updateValue(usage["available"]);
    }

    if (cpuTemperatureNode != null &&
      (!shouldScheduleUpdate || cpuTemperatureNode.hasSubscriber)) {
      var temp = await getCpuTemp();
      cpuTemperatureNode.updateValue(temp);
    }

    if (processCountNode != null &&
      (!shouldScheduleUpdate || processCountNode.hasSubscriber)) {
      var count = await getProcessCount();
      processCountNode.updateValue(count);
    }

    if (batteryLevelNode != null &&
      (!shouldScheduleUpdate || batteryLevelNode.hasSubscriber)) {
      var level = await getBatteryPercentage();
      batteryLevelNode.updateValue(level);
    }

    if (openFilesNode != null &&
      (!shouldScheduleUpdate || openFilesNode.hasSubscriber)) {
      var count = await getOpenFilesCount();
      openFilesNode.updateValue(count);
    }

    {
      Map stats;
      for (SimpleNode node in fanNodes.values) {
        SimpleNode speed = node.getChild("Speed");
        if (speed.hasSubscriber) {
          if (stats == null) {
            stats = await getFanStats();
          }
          speed.updateValue(stats[node.configs[r"$name"]]["Speed"]);
        }
      }
    }
  } catch (e, stack) {
    logger.warning("Error in statistic updater.", e, stack);
  }

  try {
    if (enableDsaDiagnosticMode != true || pidTrackingFile == null || !(await pidTrackingFile.exists())) {
      return;
    }

    Set<int> pids = (const JsonDecoder()
      .convert(await pidTrackingFile.readAsString())
      as List<int>
    ).toSet();

    for (var p in lastPidSet.difference(pids)) {
      link.removeNode("/${p}");
    }

    for (var p in pids) {
      SimpleNode node = link["/${p}"];
      if (node == null) {
        node = link.addNode("/${p}", {
          "command": {
            r"$name": "Command",
            r"$type": "string"
          },
          "memory": {
            r"$name": "Memory Usage",
            r"$type": "number",
            "@unit": "mb",
            "?value": -1.0
          }
        });
      }

      SimpleNode cmdNode = link["/${p}/command"];
      SimpleNode memoryNode = link["/${p}/memory"];

      if (cmdNode != null && cmdNode.hasSubscriber) {
        cmdNode.updateValue(await getProcessCommand(p));
      }

      if (memoryNode != null && memoryNode.hasSubscriber) {
        memoryNode.updateValue(await getProcessMemoryUsage(p));
      }
    }
  } catch (e, stack) {
    logger.warning("Error in PID tracker.", e, stack);
  }
}

Disposable timer;
