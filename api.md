 <pre>
-[root](#root)
 |-[@Execute_Command(command)](#execute_command)
 |-[@Execute_Command_Stream(command)](#execute_command_stream)
 |-[@Run_AppleScript(script)](#run_applescript)
 |-[@Read_WMIC()](#read_wmic)
 |-[Platform](#platform) - string
 |-[Processor_Count](#processor_count) - number
 |-[Processes](#processes)
 |-[Operating_System](#operating_system) - string
 |-[Poll_Rate](#poll_rate) - number
 |-[CPU_Usage](#cpu_usage) - number
 |-[Memory_Usage](#memory_usage) - number
 |-[Total_Memory](#total_memory)
 |-[System_Time](#system_time) - string
 |-[Free_Memory](#free_memory) - number
 |-[Used_Memory](#used_memory) - number
 |-[Disk_Usage](#disk_usage) - number
 |-[Total_Disk_Space](#total_disk_space) - number
 |-[Used_Disk_Space](#used_disk_space) - number
 |-[Free_Disk_Space](#free_disk_space) - number
 |-[Architecture](#architecture) - string
 |-[Hostname](#hostname) - string
 |-[CPU_Temperature](#cpu_temperature) - number
 |-[Hardware_Identifier](#hardware_identifier) - string
 |-[Model](#model) - string
 |-[Processor_Model](#processor_model) - string
 |-[Open_Files](#open_files) - number
 |-[Network_Interfaces](#network_interfaces)
 | |-[NetworkInterface](#networkinterface) - string
 |-[Battery_Level](#battery_level) - number
 |-[Diagnostics_Mode](#diagnostics_mode) - bool[disabled,enabled]
 |-[Fans](#fans)
 | |-[FanStat](#fanstat)
 | | |-[Speed](#speed) - number
 |-[proc](#proc)
 | |-[procProcess](#procprocess)
 | | |-[command](#command) - string
 | | |-[memory](#memory) - number
 | | |-[filesOpen](#filesopen) - number
 </pre>

---

### root  

Root node of the DsLink  

Type: Node   

---

### Execute_Command  

Attempts to execute the specified command in the system's CLI.  

Type: Action   
$is: executeCommand   
Parent: [root](#root)  

Description:  
Execute Command will try to execute the specified command in the command line interface of the system. It returns the output of the command and the exit code it returned.  

Params:  

Name | Type | Description
--- | --- | ---
command | `string` | The command to try and run.

Return type: values   
Columns:  

Name | Type | Description
--- | --- | ---
output | `string` | Standard out and standard error output text from running the command. 
exitCode | `number` | The exit code returned by running the command. 

---

### Execute_Command_Stream  

Attempts to execute the specified command returning live data as it executes.  

Type: Action   
$is: executeCommandStream   
Parent: [root](#root)  

Description:  
Execute Command Stream will try to run the specified command and return a live view of the standard output and standard error from the command as it runs. This is beneficial for a long running command with progress updates as it executes.  

Params:  

Name | Type | Description
--- | --- | ---
command | `string` | The command to try and execute in the system's CLI.

Return type: stream   
Columns:  

Name | Type | Description
--- | --- | ---
type | `string` | Output type, such as stderr or stdout 
value | `dynamic` | The output from the command itself. 

---

### Run_AppleScript  

On MacOS, run the specified apple script  

Type: Action   
$is: runAppleScript   
Parent: [root](#root)  

Description:  
On MacOS systems, try to run the specified AppleScript. Returns the standard output and standard error from running the script. If the platform is not detected as being macOS, then this action will not be available.  

Params:  

Name | Type | Description
--- | --- | ---
script | `string` | The text script to try and execute.

Return type: values   
Columns:  

Name | Type | Description
--- | --- | ---
output | `string` | Standard output and standard error results. 

---

### Read_WMIC  

On Windows platforms, query WMIC for data.  

Type: Action   
$is: readWmicData   
Parent: [root](#root)  

Description:  
On Windows platform, return a formatted list of the query response from WMIC. Number of columns in the return will vary depending on the response from the query.  

Return type: table   

---

### Platform  

Operating system the link is running on.  

Type: Node   
Parent: [root](#root)  
Value Type: `string`  
Writable: `never`  

---

### Processor_Count  

Number of processors the system has.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Processes  

Number of processes currently running on the operating system.  

Type: Node   
Parent: [root](#root)  

---

### Operating_System  

Full version of the operating system.  

Type: Node   
Parent: [root](#root)  
Value Type: `string`  
Writable: `never`  

---

### Poll_Rate  

Frequency to update system values.  

Type: Node   
Parent: [root](#root)  

Description:  
Poll Rate is how often the system should be polled for updates. Only values which have a subscription will be updated. Default poll rate is in seconds.  

Value Type: `number`  
Writable: `write`  

---

### CPU_Usage  

System CPU Usage percentage.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Memory_Usage  

System Memory Usage percentage.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Total_Memory  

Total MB of memory in the system.  

Type: Node   
Parent: [root](#root)  

---

### System_Time  

Current Date/Time reported by the system.  

Type: Node   
Parent: [root](#root)  
Value Type: `string`  
Writable: `never`  

---

### Free_Memory  

Total MB of unused memory in the system.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Used_Memory  

Total MB of used memory in the system.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Disk_Usage  

Percentage of used disk space.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Total_Disk_Space  

Total MB of disk space.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Used_Disk_Space  

Total MB of used disk space.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Free_Disk_Space  

Total MB of free disk space.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Architecture  

System processor architecture type. (eg: x386, xamd64)  

Type: Node   
Parent: [root](#root)  
Value Type: `string`  
Writable: `never`  

---

### Hostname  

System's host name  

Type: Node   
Parent: [root](#root)  
Value Type: `string`  
Writable: `never`  

---

### CPU_Temperature  

If supported, displays the system's CPU temperature.  

Type: Node   
Parent: [root](#root)  

Description:  
The system's CPU temperature if it is supported. If the system does not support this feature, the node will not be available. Default unit is measured in °C  

Value Type: `number`  
Writable: `never`  

---

### Hardware_Identifier  

If supported, displays the system's hardware identifier.  

Type: Node   
Parent: [root](#root)  

Description:  
The systems hardware identifier if it is supported. This value may be derived from different locations on different platforms. If the functionality is not supported on the system, the node will not be available.  

Value Type: `string`  
Writable: `never`  

---

### Model  

If supported, displays the systems model name/number.  

Type: Node   
Parent: [root](#root)  

Description:  
The system model name/number if supported by the system. If the functionality is not supported this node will not be available.  

Value Type: `string`  
Writable: `never`  

---

### Processor_Model  

If supported, displays the system's processor model.  

Type: Node   
Parent: [root](#root)  

Description:  
The system's processor model name, if supported by the system. If the functionality is not supported, this node will not be available.  

Value Type: `string`  
Writable: `never`  

---

### Open_Files  

If supported, number of open files on the system.  

Type: Node   
Parent: [root](#root)  
Value Type: `number`  
Writable: `never`  

---

### Network_Interfaces  

Collection of Network interfaces detected on the system.  

Type: Node   
Parent: [root](#root)  

---

### NetworkInterface  

Network Interface detected on the system.  

Type: Node   
Parent: [Network_Interfaces](#network_interfaces)  

Description:  
A network interface may be real or virtual. The value is a comma separated list of all addresses bound to that interface.  

Value Type: `string`  
Writable: `never`  

---

### Battery_Level  

If supported, current battery level percentage.  

Type: Node   
Parent: [root](#root)  

Description:  
If detected, reports the battery percentage level of the system. Because some systems report battery differently if the power is connected, this node may not be available even if the system has an internal battery.  

Value Type: `number`  
Writable: `never`  

---

### Diagnostics_Mode  

Enable/Disable diagnostic mode to monitor processes.  

Type: Node   
$is: diagnosticsMode   
Parent: [root](#root)  

Description:  
Enabling Diagnostics Mode will add process monitoring for active DsLinks connected to the DgLux instance.  

Value Type: `bool[disabled,enabled]`  
Writable: `write`  

---

### Fans  

If supported, collection of fans detected on the system.  

Type: Node   
Parent: [root](#root)  

---

### FanStat  

A fan detected within the system.  

Type: Node   
Parent: [Fans](#fans)  

---

### Speed  

Speed of the detected fan in RPM.  

Type: Node   
Parent: [FanStat](#fanstat)  
Value Type: `number`  
Writable: `never`  

---

### proc  

Collection of DgLux processes if Diagnostics is enabled.  

Type: Node   
Parent: [root](#root)  

---

### procProcess  

DgLux process and collection of its related values.  

Type: Node   
Parent: [proc](#proc)  

---

### command  

Command which started the process.  

Type: Node   
Parent: [procProcess](#procprocess)  
Value Type: `string`  
Writable: `never`  

---

### memory  

Memory usage by the process, in MB.  

Type: Node   
Parent: [procProcess](#procprocess)  
Value Type: `number`  
Writable: `never`  

---

### filesOpen  

Number of open files by the process.  

Type: Node   
Parent: [procProcess](#procprocess)  
Value Type: `number`  
Writable: `never`  

---

