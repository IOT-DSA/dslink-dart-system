library dslink.system.lm_sensors;

import "dart:async";
import "dart:io";

import "utils.dart" as util;

final RegExp rawValuePattern = new RegExp(r"[+-.0-9]+");

class SensorValue {
  final double value;
  final String unit;

  SensorValue(this.value, [this.unit]);

  @override
  String toString() => "${value}${unit == null ? '' : ' ' + unit}";
}

Map<String, Map<String, SensorValue>> parseSensorsOutput(String input) {
  var out = <String, Map<String, SensorValue>>{};
  var lines = input.split("\n");

  String currentSection;

  var values = <String, SensorValue>{};
  for (var line in lines) {
    if (line.isEmpty) {
      continue;
    }

    if (line.contains(":")) {
      if (
        (line.startsWith("  ") ||
        !line.startsWith("Adapter")) &&
        currentSection != null) {
        var name = line.substring(
          line.startsWith(" ") ? line.indexOf(" ") : 0,
          line.indexOf(":")
        );

        var range = line.lastIndexOf("(");
        var valueContent = line.substring(
          line.indexOf(":") + 1,
          range == -1 ? null : range
        ).trim();

        var rawValue = rawValuePattern.firstMatch(valueContent).group(0);
        var unitsLeft = valueContent.replaceAll(rawValue, "").trim();
        
        values[name] = new SensorValue(
          double.parse(rawValue),
          unitsLeft.isEmpty ? null : unitsLeft
        );
      }
    } else {
      values = <String, SensorValue>{};
      currentSection = line;
      out[currentSection] = values;
    }
  }

  return out;
}

Future<bool> isLmSensorsAvailable() async {
  if (!Platform.isLinux) {
    return false;
  }

  var path = await util.findExecutable("sensors");
  return path != null;
}

Future<Map<String, Map<String, SensorValue>>> getLmSensorData({
  bool fahrenheit: false,
  bool graceful: true
}) async {
  try {
    var path = await util.findExecutable("sensors");

    var result = await Process.run(path, fahrenheit ? const ["-f"] : const []);

    if (result.exitCode != 0) {
      return {};
    }

    return parseSensorsOutput(result.stdout.toString());
  } catch (e) {
    if (!graceful) {
      rethrow;
    }
    return <String, Map<String, SensorValue>>{};
  }
}
