import "package:dslink_system/lm_sensors.dart";

const String SensorInputA = """
lm92-i2c-0-48
Adapter: SMBus I801 adapter at f000
temp1:        +14.0°C  (low  = +14.0°C, hyst = +28.0°C)
                       (high = +14.0°C, hyst =  +0.0°C)
                       (crit = +14.0°C, hyst =  +0.0°C)

asus-isa-0000
Adapter: ISA adapter
cpu_fan:        0 RPM

coretemp-isa-0000
Adapter: ISA adapter
Package id 0:  +26.0°C  (high = +80.0°C, crit = +100.0°C)
Core 0:        +25.0°C  (high = +80.0°C, crit = +100.0°C)
Core 1:        +23.0°C  (high = +80.0°C, crit = +100.0°C)
Core 2:        +22.0°C  (high = +80.0°C, crit = +100.0°C)
Core 3:        +22.0°C  (high = +80.0°C, crit = +100.0°C)
""";

const String SensorInputB = """
lm92-i2c-0-48
Adapter: SMBus I801 adapter at f000
temp1:
  temp1_input: 14.000
  temp1_max: 14.000
  temp1_max_hyst: 0.000
  temp1_min: 14.000
  temp1_crit: 14.000
  temp1_crit_hyst: 0.000
  temp1_min_hyst: 28.000
  temp1_max_alarm: 0.000
  temp1_min_alarm: 0.000
  temp1_crit_alarm: 0.000

asus-isa-0000
Adapter: ISA adapter
cpu_fan:
  fan1_input: 0.000

coretemp-isa-0000
Adapter: ISA adapter
Package id 0:
  temp1_input: 25.000
  temp1_max: 80.000
  temp1_crit: 100.000
  temp1_crit_alarm: 0.000
Core 0:
  temp2_input: 21.000
  temp2_max: 80.000
  temp2_crit: 100.000
  temp2_crit_alarm: 0.000
Core 1:
  temp3_input: 23.000
  temp3_max: 80.000
  temp3_crit: 100.000
  temp3_crit_alarm: 0.000
Core 2:
  temp4_input: 21.000
  temp4_max: 80.000
  temp4_crit: 100.000
  temp4_crit_alarm: 0.000
Core 3:
  temp5_input: 22.000
  temp5_max: 80.000
  temp5_crit: 100.000
  temp5_crit_alarm: 0.000
""";

main() async {
  test(SensorInputA);
  test(SensorInputB);
}

void test(String input) {
  var data = parseSensorsOutput(input);

  for (var bus in data.keys) {
    var sensors = data[bus];

    print("${bus}:");
    for (var key in sensors.keys) {
      print("  ${key}: ${sensors[key]}");
    }
  }
}
