import "package:dslink_system/utils.dart";
import "dart:io" as IO;

main() async {
  logAllExceptions = true;

  print("Operating System: ${await getOperatingSystemVersion()}");

  await getCpuUsage(); // Linux needs to have getCpuUsage() called twice

  print("CPU Usage: ${await getCpuUsage()}%");
  print("Total Memory: ${await getMemSizeBytes()} bytes");
  print("Free Memory: ${await getFreeMemory()} bytes");

  if (await doesSupportCPUTemperature()) {
    print("CPU Temperature: ${await getCpuTemp()}°C");
  }

  if (await doesSupportHardwareIdentifier()) {
    print("Hardware Identifier: ${await getHardwareIdentifier()}");
  }

  if (await doesSupportModel()) {
    print("Model: ${await getHardwareModel()}");
  }

  if (await doesSupportProcessorName()) {
    print("Processor: ${await getProcessorName()}");
  }

  print("Fan Stats: ${await getFanStats()}");
  var size = await getProcessMemoryUsage(IO.pid) / 1024 / 1024;
  print("Our Memory Usage: ${size}mb");
}
