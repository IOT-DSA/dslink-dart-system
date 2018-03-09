import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:dslink_system/utils.dart";
import "package:dslink_system/lm_sensors.dart";
import "package:dslink_system/io.dart";

import "package:args/args.dart";

const Map<String, String> iconFileNames = const <String, String>{
  "system/platform/macos": "Mac.png",
  "system/platform/linux": "Linux.png",
  "system/platform/windows": "Windows.png"
};

LinkProvider link;

bool secureMode = false;
bool enableLmSensorsRawMode = false;
bool enableLmSensorsFahrenheitMode = false;
bool enableDsaDiagnosticMode = false;

typedef SimpleNode Profile(String path);

typedef Action(Map<String, dynamic> params);
typedef ActionWithPath(Path path, Map<String, dynamic> params);

Profile addAction(handler, [bool isInsecure = false]) {
  if (secureMode && isInsecure) {
    return (String path) {
      return new SimpleNode(path);
    };
  }

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
  try {
    secureMode = await isInSecureMode();
  } catch(e) {
    print("Checking for secure mode failed, exiting System DSLink.");
    exit(1);
  }

  final Map<String, String> PLATFORMS = {
    "macos": "Mac",
    "linux": "Linux",
    "android": "Android",
    "windows": "Windows"
  };

  final Map<String, dynamic> NODES = {
    //* @Node Platform
    //* @Parent root
    //*
    //* Operating system the link is running on.
    //* @Value string
    "Platform": {
      r"$type": "string",
      "?value": PLATFORMS.containsKey(Platform.operatingSystem) ?
        PLATFORMS[Platform.operatingSystem] :
        Platform.operatingSystem
    },
    //* @Node Processor_Count
    //* @Parent root
    //*
    //* Number of processors the system has.
    //* @Value number
    "Processor_Count": {
      r"$name": "Processor Count",
      r"$type": "number",
      "?value": Platform.numberOfProcessors
    },
    //* @Node Processes
    //* @Parent root
    //*
    //* Number of processes currently running on the operating system.
    "Processes": {
      r"$name": "Processes",
      r"$type": "number",
      "?value": 0
    },
    //* @Node Operating_System
    //* @Parent root
    //*
    //* Full version of the operating system.
    //* @Value string
    "Operating_System": {
      r"$name": "Operating System",
      r"$type": "string",
      "?value": await getOperatingSystemVersion()
    },
    //* @Node Poll_Rate
    //* @Parent root
    //*
    //* Frequency to update system values.
    //*
    //* Poll Rate is how often the system should be polled for updates. Only
    //* values which have a subscription will be updated. Default poll rate
    //* is in seconds.
    //*
    //* @Value number write
    "Poll_Rate": {
      r"$name": "Poll Rate",
      r"$type": "number",
      r"$writable": "write",
      "?value": Platform.numberOfProcessors == 1 ? 3 : 1,
      "@unit": "seconds"
    },
    //* @Node CPU_Usage
    //* @Parent root
    //*
    //* System CPU Usage percentage.
    //* @Value number
    "CPU_Usage": {
      r"$name": "CPU Usage",
      r"$type": "number",
      "@unit": "%"
    },
    //* @Node Memory_Usage
    //* @Parent root
    //*
    //* System Memory Usage percentage.
    //* @Value number
    "Memory_Usage": {
      r"$name": "Memory Usage",
      r"$type": "number",
      "@unit": "%"
    },
    //* @Node Total_Memory
    //* @Parent root
    //*
    //* Total MB of memory in the system.
    "Total_Memory": {
      r"$name": "Total Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node System_Time
    //* @Parent root
    //*
    //* Current Date/Time reported by the system.
    //* @Value string
    "System_Time": {
      r"$name": "System Time",
      r"$type": "string"
    },
    //* @Node Free_Memory
    //* @Parent root
    //*
    //* Total MB of unused memory in the system.
    //* @Value number
    "Free_Memory": {
      r"$name": "Free Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node Used_Memory
    //* @Parent root
    //*
    //* Total MB of used memory in the system.
    //* @Value number
    "Used_Memory": {
      r"$name": "Used Memory",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node Disk_Usage
    //* @Parent root
    //*
    //* Percentage of used disk space.
    //* @Value number
    "Disk_Usage": {
      r"$name": "Disk Usage",
      r"$type": "number",
      "@unit": "%"
    },
    //* @Node Total_Disk_Space
    //* @Parent root
    //*
    //* Total MB of disk space.
    //* @Value number
    "Total_Disk_Space": {
      r"$name": "Total Disk Space",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node Used_Disk_Space
    //* @Parent root
    //*
    //* Total MB of used disk space.
    //* @Value number
    "Used_Disk_Space": {
      r"$name": "Used Disk Space",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node Free_Disk_Space
    //* @Parent root
    //*
    //* Total MB of free disk space.
    //* @Value number
    "Free_Disk_Space": {
      r"$name": "Free Disk Space",
      r"$type": "number",
      "@unit": "mb"
    },
    //* @Node Architecture
    //* @Parent root
    //*
    //* System processor architecture type. (eg: x386, xamd64)
    //* @Value string
    "Architecture": {
      r"$type": "string",
      "?value": await getSystemArchitecture()
    },
    //* @Node Hostname
    //* @Parent root
    //*
    //* System's host name
    //* @Value string
    "Hostname": {
      r"$type": "string",
      "?value": Platform.localHostname
    }
  };

  // insecure nodes are nodes that could in theory (but not likely in practice)
  // be used through DSA to compromise a system.
  // disabled by ./.secureMode or ../../.secureMode
  final Map<String, dynamic> INSECURE_NODES = {
    //* @Action Execute_Command
    //* @Is executeCommand
    //* @Parent root
    //*
    //* Attempts to execute the specified command in the system's CLI.
    //*
    //* Execute Command will try to execute the specified command in the
    //* command line interface of the system. It returns the output of the
    //* command and the exit code it returned.
    //*
    //* @Param command string The command to try and run.
    //*
    //* @Return values
    //* @Column output string Standard out and standard error output text from
    //* running the command.
    //* @Column exitCode number The exit code returned by running the command.
    "Execute_Command": {
      r"$invokable": "config",
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
    //* @Action Execute_Command_Stream
    //* @Parent root
    //* @Is executeCommandStream
    //*
    //* Attempts to execute the specified command returning live data as it executes.
    //*
    //* Execute Command Stream will try to run the specified command and return
    //* a live view of the standard output and standard error from the command as
    //* it runs. This is beneficial for a long running command with progress
    //* updates as it executes.
    //*
    //* @Param command string The command to try and execute in the system's CLI.
    //*
    //* @Return stream
    //* @Column type string Output type, such as stderr or stdout
    //* @Column value dynamic The output from the command itself.
    "Execute_Command_Stream": {
      r"$invokable": "config",
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
    //* @Node CPU_Temperature
    //* @Parent root
    //*
    //* If supported, displays the system's CPU temperature.
    //*
    //* The system's CPU temperature if it is supported. If the system does
    //* not support this feature, the node will not be available. Default
    //* unit is measured in °C
    //*
    //* @Value number
    NODES["CPU_Temperature"] = {
      r"$name": "CPU Temperature",
      "@unit": "°C",
      r"$type": "number"
    };
  }

  if (await doesSupportHardwareIdentifier()) {
    //* @Node Hardware_Identifier
    //* @Parent root
    //*
    //* If supported, displays the system's hardware identifier.
    //*
    //* The systems hardware identifier if it is supported. This value may
    //* be derived from different locations on different platforms. If the
    //* functionality is not supported on the system, the node will not be
    //* available.
    //*
    //* @Value string
    NODES["Hardware_Identifier"] = {
      r"$name": "Hardware Identifier",
      r"$type": "string",
      "?value": await getHardwareIdentifier()
    };
  }

  if (await doesSupportModel()) {
    //* @Node Model
    //* @Parent root
    //*
    //* If supported, displays the systems model name/number.
    //*
    //* The system model name/number if supported by the system. If the
    //* functionality is not supported this node will not be available.
    //*
    //* @Value string
    NODES["Model"] = {
      r"$name": "Model",
      r"$type": "string",
      "?value": await getHardwareModel()
    };
  }

  if (await doesSupportProcessorName()) {
    //* @Node Processor_Model
    //* @Parent root
    //*
    //* If supported, displays the system's processor model.
    //*
    //* The system's processor model name, if supported by the system. If the
    //* functionality is not supported, this node will not be available.
    //*
    //* @Value string
    NODES["Processor_Model"] = {
      r"$name": "Processor Model",
      r"$type": "string",
      "?value": await getProcessorName()
    };
  }

  if (await doesSupportOpenFilesCount()) {
    //* @Node Open_Files
    //* @Parent root
    //*
    //* If supported, number of open files on the system.
    //* @Value number
    NODES["Open_Files"] = {
      r"$name": "Open Files",
      r"$type": "number"
    };
  }

  //* @Node Network_Interfaces
  //* @Parent root
  //*
  //* Collection of Network interfaces detected on the system.
  NODES["Network_Interfaces"] = {
    r"$name": "Network Interfaces"
  };

  if (await hasBattery()) {
    //* @Node Battery_Level
    //* @Parent root
    //*
    //* If supported, current battery level percentage.
    //*
    //* If detected, reports the battery percentage level of the system.
    //* Because some systems report battery differently if the power is
    //* connected, this node may not be available even if the system has an
    //* internal battery.
    //*
    //* @Value number
    NODES["Battery_Level"] = {
      r"$name": "Battery Level",
      r"$type": "number",
      "@unit": "%"
    };
  }

  if (await isLmSensorsAvailable()) {
    NODES["Sensors"] = {
      r"$name": "Sensors"
    };
  }

  if (Platform.isMacOS) {
    //* @Action Run_AppleScript
    //* @Is runAppleScript
    //* @Parent root
    //*
    //* On MacOS, run the specified apple script
    //*
    //* On MacOS systems, try to run the specified AppleScript. Returns the
    //* standard output and standard error from running the script. If the
    //* platform is not detected as being macOS, then this action will not
    //* be available.
    //*
    //* @Param script string The text script to try and execute.
    //*
    //* @Return values
    //* @Column output string Standard output and standard error results.
    INSECURE_NODES["Run_AppleScript"] = {
      r"$is": "runAppleScript",
      r"$name": "Run AppleScript",
      r"$invokable": "config",
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

  if (Platform.isWindows) {
    //* @Action Read_WMIC
    //* @Is readWmicData
    //* @Parent root
    //*
    //* On Windows platforms, query WMIC for data.
    //*
    //* On Windows platform, return a formatted list of the query response
    //* from WMIC. Number of columns in the return will vary depending on the
    //* response from the query.
    //*
    //* @Return table
    INSECURE_NODES["Read_WMIC"] = {
      r"$is": "readWmicData",
      r"$name": "Read WMIC Data",
      r"$invokable": "config",
      r"$params": [
        {
          "name": "query",
          "type": "string",
          "default": "OS"
        }
      ],
      r"$result": "table"
    };
  }

  //* @Node Diagnostics_Mode
  //* @Is diagnosticsMode
  //* @Parent root
  //*
  //* Enable/Disable diagnostic mode to monitor processes.
  //*
  //* Enabling Diagnostics Mode will add process monitoring for active DsLinks
  //* connected to the DgLux instance.
  //*
  //* @Value bool[disabled,enabled] write
  NODES["Diagnostics_Mode"] = {
    r"$is": "diagnosticsMode",
    r"$name": "Diagnostics Mode",
    r"$type": "bool[disabled,enabled]",
    r"$writable": "write",
    "?value": false
  };

  // add secure mode nodes to NODES before initialization
  if (!secureMode) {
    NODES.addAll(INSECURE_NODES);
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

        return [[result.output, result.exitCode]];
      }, true),
      "runAppleScript": addAction((Map<String, dynamic> params) async {
        var result = await exec(
          "osascript",
          args: ["-e", params["script"]],
          writeToBuffer: true
        );

        return [[result.output]];
      }, true),
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
              controller.add([[
                "stdout",
                line
              ]]);
            }
          });

          proc.stderr
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen((line) {
            if (!controller.isClosed) {
              controller.add([[
                "stderr",
                line
              ]]);
            }
          });

          proc.exitCode.then((code) {
            if (!controller.isClosed) {
              controller.add([[
                "exit",
                code
              ]]);
            }
            controller.close();
          });
        });

        return controller.stream;
      }, true),
      "readWmicData": (String path) {
        if (secureMode) {
          return new SimpleNode(path);
        }

        return new SimpleActionNode(path, (Map<String, dynamic> m) async* {
          var query = m["query"].toString();
          var data = await dumpWmicQuery(query);

          if (data.isNotEmpty) {
            var m = data.first.keys.toList();

            yield new TableColumns(m
              .map((x) => new TableColumn(x, "dynamic"))
              .toList()
            );

            for (var x in data) {
              yield [x.values.toList()];
            }
          }
        });
      },
      "diagnosticsMode": (String path) {
        return new DiagnosticsModeNode(path);
      }
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

  argp.addOption("lmsensors_fahrenheit_mode", callback: (value) {
    enableLmSensorsFahrenheitMode = getInputBoolean(value);
  }, help: "Enable Fahrenheit Mode for Linux Sensors",
    valueHelp: "true/false",
    defaultsTo: "false");

  argp.addOption("lmsensors_raw_mode", callback: (value) {
    enableLmSensorsRawMode = getInputBoolean(value);
  }, help: "Enable Raw Mode for Linux Sensors",
    valueHelp: "true/false",
    defaultsTo: "false");

  String baseDir = Platform.script.resolve("..").toFilePath();

  link.configure(argp: argp, optionsHandler: (ArgResults res) {
    if (res["base-path"] is String) {
      baseDir = res["base-path"];
    }
  });
  link.init();

  SimpleNodeProvider np = link.provider;

  np.setIconResolver((String path) async {
    if (iconFileNames.containsKey(path)) {
      var fileName = iconFileNames[path];
      var file = new File("${baseDir}/data/${fileName}");
      if (await file.exists()) {
        Uint8List data = await file.readAsBytes();
        return data.buffer.asByteData(
          data.offsetInBytes,
          data.lengthInBytes
        );
      }
    }

    return null;
  });

  if (iconFileNames.containsKey(
    "system/platform/${Platform.operatingSystem.toLowerCase()}"
  )) {
    link.getNode("/").attributes["@icon"] =
      "system/platform/${Platform.operatingSystem.toLowerCase()}";
  }

  for (var key in NODES.keys) {
    if (key == "Poll_Rate") {
      continue;
    }

    if (key == "Diagnostics_Mode" && link["/Diagnostics_Mode"] is DiagnosticsModeNode) {
      continue;
    }

    link.removeNode("/${key}");
    SimpleNode x = link.addNode("/${key}", NODES[key]);
    x.serializable = false;
  }

  // make sure secure mode nodes are always removed
  // even though they wouldn't work, listing them may cause panic
  if (secureMode) {
    for (var key in INSECURE_NODES.keys) {
      link.removeNode("/$key");
    }
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
  link.syncValue("/Diagnostics_Mode");
  enableDsaDiagnosticMode = link.val("/Diagnostics_Mode") == true;

  {
    var stats = await getFanStats();
    var fans = {};
    for (var key in stats.keys) {
      //* @Node
      //* @MetaType FanStat
      //* @Parent Fans
      //*
      //* A fan detected within the system.
      fans[key.replaceAll(" ", "_")] = {
        r"$name": key,
        //* @Node Speed
        //* @Parent FanStat
        //*
        //* Speed of the detected fan in RPM.
        //* @Value number
        "Speed": {
          r"$type": "number",
          "?value": stats[key]["Speed"],
          "@unit": "RPM"
        }
      };
    }

    if (fans.isNotEmpty) {
      //* @Node Fans
      //* @Parent root
      //*
      //* If supported, collection of fans detected on the system.
      SimpleNode fansNode = link.addNode("/Fans", fans);
      fansNode.serializable = false;

      for (var key in fans.keys) {
        fanNodes[key] = link.getNode("/Fans/${key.replaceAll(" ", "_")}");
      }
    }
  }

  link.connect();
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
SimpleNode networkInterfacesNode = link["/Network_Interfaces"];
SimpleNode sensorsNode = link["/Sensors"];

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

    try {
      var interfaces = await NetworkInterface.list(
        includeLinkLocal: true,
        includeLoopback: true
      );

      var names = interfaces.map((x) => x.name).toList();

      for (String name in networkInterfacesNode.children.keys.where((x) => !names.contains(x)).toList()) {
        link.removeNode("${networkInterfacesNode.path}/${name}");
      }

      for (NetworkInterface interface in interfaces) {
        var name = interface.name;

        //* @Node
        //* @MetaType NetworkInterface
        //* @Parent Network_Interfaces
        //*
        //* Network Interface detected on the system.
        //*
        //* A network interface may be real or virtual. The value is a comma
        //* separated list of all addresses bound to that interface.
        //*
        //* @Value string
        var p = "${networkInterfacesNode.path}/${name}";
        var node = link.getNode(p);
        if (node == null) {
          node = link.addNode(p, {
            r"$name": name,
            r"$type": "string"
          });
        }

        node.updateValue(interface.addresses.map((x) => x.address).join(","));
      }
    } catch (e, stack) {
      logger.warning("Error while fetching the network interfaces.", e, stack);
    }
  } catch (e, stack) {
    logger.warning("Error in statistic updater.", e, stack);
  }

  if (sensorsNode != null) {
    var sensorData = await getLmSensorData(
      friendly: !enableLmSensorsRawMode,
      fahrenheit: enableLmSensorsFahrenheitMode
    );
    for (var sensorType in sensorData.keys) {
      SimpleNode sensorTypeNode = sensorsNode.getChild(sensorType);
      if (sensorTypeNode == null) {
        sensorTypeNode = link.addNode("${sensorsNode.path}/${sensorType}", {
          r"$name": sensorType
        });
      }

      var data = sensorData[sensorType];

      for (var name in data.keys) {
        var fakeName = name.replaceAll(" ", "_");
        var sensorValue = data[name];

        SimpleNode sensorNode = sensorTypeNode.getChild(fakeName);

        if (sensorNode == null) {
          sensorNode = link.addNode("${sensorTypeNode.path}/${fakeName}", {
            r"$name": name,
            r"$type": "number",
            "?value": sensorValue.value
          });

          if (sensorValue.unit != null && sensorValue.unit.isNotEmpty) {
            sensorNode.attributes["@unit"] = sensorValue.unit;
          }
        } else {
          sensorNode.updateValue(sensorValue.value);
        }
      }
    }
  }

  try {
    if (enableDsaDiagnosticMode == true && pidTrackingFile == null && (Platform.isLinux || Platform.isMacOS)) {
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

    if (enableDsaDiagnosticMode != true || pidTrackingFile == null || !(await pidTrackingFile.exists())) {
      return;
    }

    var pids = const JsonDecoder().convert(await pidTrackingFile.readAsString());

    Map<int, String> pidmap = {};

    if (pids is List) {
      for (var i in pids) {
        pidmap[i] = i.toString();
      }
    } else if (pids is Map) {
      for (var key in pids.keys) {
        pidmap[int.parse(key)] = pids[key];
      }
    }

    //* @Node proc
    //* @Parent root
    //*
    //* Collection of DgLux processes if Diagnostics is enabled.
    SimpleNode procNode = link["/proc"];
    if (procNode == null) {
      procNode = link.addNode("/proc", {
        r"$name": "Processes"
      });

      procNode.serializable = false;
    }

    procNode.children.keys.where((x) {
      return !pidmap.containsValue(x);
    }).toList().forEach((e) {
      link.removeNode("/proc/${e}");
    });

    for (var pid in pidmap.keys) {
      String p = pidmap[pid];
      //* @Node
      //* @MetaType procProcess
      //* @Parent proc
      //*
      //* DgLux process and collection of its related values.
      SimpleNode node = link["/proc/${p}"];
      if (node == null) {
        var cmd = await getProcessCommand(pid);

        node = link.addNode("/proc/${p}", {
          r"$name": p,
          //* @Node command
          //* @Parent procProcess
          //*
          //* Command which started the process.
          //* @Value string
          "command": {
            r"$name": "Command",
            r"$type": "string",
            "?value": cmd
          },
          //* @Node memory
          //* @Parent procProcess
          //*
          //* Memory usage by the process, in MB.
          //* @Value number
          "memory": {
            r"$name": "Memory Usage",
            r"$type": "number",
            "@unit": "mb",
            "?value": 0.0
          },
          //* @Node filesOpen
          //* @Parent procProcess
          //*
          //* Number of open files by the process.
          //* @Value number
          "filesOpen": {
            r"$name": "Open Files",
            r"$type": "number",
            "@unit": "file descriptors",
            "?value": 0
          }
        });

        node.serializable = false;
      }

      SimpleNode cmdNode = link["/proc/${p}/command"];
      SimpleNode memoryNode = link["/proc/${p}/memory"];
      SimpleNode openFilesNode = link["/proc/${p}/filesOpen"];

      if (cmdNode != null && cmdNode.hasSubscriber) {
        cmdNode.updateValue(await getProcessCommand(pid));
      }

      if (memoryNode != null && memoryNode.hasSubscriber) {
        var usage = await getProcessMemoryUsage(pid);
        memoryNode.updateValue(usage / 1024 / 1024);
      }

      if (openFilesNode != null && openFilesNode.hasSubscriber) {
        var files = await getProcessOpenFiles(pid);
        openFilesNode.updateValue(files);
      }
    }

    lastPidSet = pidmap.keys.toSet();
  } catch (e, stack) {
    logger.warning("Error in PID tracker.", e, stack);
  }
}

class DiagnosticsModeNode extends SimpleNode {
  DiagnosticsModeNode(String path) : super(path);

  @override
  onSetValue(val) {
    if (val == true) {
      enableDsaDiagnosticMode = true;
    } else {
      try {
        link.removeNode("/proc");
      } catch (e) {}

      lastPidSet.clear();
      enableDsaDiagnosticMode = false;
    }

    updateValue(val);

    link.save();

    return true;
  }
}

Disposable timer;
