import "package:dslink_system/utils.dart";

main() async {
  print("Operating System: ${await getOperatingSystemVersion()}");
  print("CPU Usage: ${await getCpuUsage()}%");

  if (await doesSupportCPUTemperature()) {
    print("CPU Temperature: ${await getCpuTemp()}°C");
  }

  if (await doesSupportHardwareIdentifier()) {
    print("Hardware Identifier: ${await getHardwareIdentifier()}");
  }

  if (await doesSupportModel()) {
    print("Model: ${await getHardwareModel()}");
  }

  print("Processor: ${await getProcessorName()}");
  print("Fan Stats: ${await getFanStats()}");
}
