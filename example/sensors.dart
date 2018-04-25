import "package:dslink_system/lm_sensors.dart";

main() async {
  var data = await getLmSensorData(graceful: false);

  for (var bus in data.keys) {
    var sensors = data[bus];

    print("${bus}:");
    for (var key in sensors.keys) {
      print("  ${key}: ${sensors[key]}");
    }
  }
}
