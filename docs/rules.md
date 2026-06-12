# Rules

## SYS-001 - Linux operating system

**Category:** System  
**Severity:** Blocking  
**Related requirement:** NFR-001

### Description

Checks whether the tool is running on a Linux-based operating system.

### Pass condition

The system is detected as Linux.

### Fail condition

The system is not Linux or the operating system cannot be identified.

### Recommendation

Run the tool on a Linux-based operating system.

---

## SYS-002 - Execution dependencies available

**Category:** System
**Severity:** Blocking
**Related requirement:** FR-011, NFR-005
**Status:** Draft

### Description

Checks whether the external required dependencies are available before starting the hotspot.

If one or more required dependencies are missing, the application should attempt to install or resolve them automatically when possible.

**The final list of dependencies and the automatic installation strategy will be defined later, during the architecture and implementation phase.**

### Pass condition

The rule passes when all required dependencies are installed, available in the system `PATH`, and executable by the application.

The rule may also pass if missing dependencies are successfully installed or resolved automatically before starting the hotspot.

### Fail condition

The rule fails when one or more required dependencies are missing and the application cannot install, resolve, or execute them.

It also fails if automatic installation is not supported for the current system, package manager, execution mode, or user permissions.

### Recommendation

Allow the application to install or resolve the missing dependencies automatically when possible.

If automatic installation fails, review the reported missing dependencies and install them manually according to the operating system and package manager being used.


---

## SYS-003 - Root privileges available

**Category:** System  
**Severity:** Blocking  
**Related requirement:** FR-002, FR-007, FR-010, NFR-005

### Description

Checks whether the command is running with the required privileges to modify network interfaces, IP addresses, DHCP services, and firewall rules.

### Pass condition

The command is executed as root or with sufficient privileges.

### Fail condition

The command requires elevated privileges but is executed by a non-privileged user.

### Recommendation

Run the command using `sudo`.

Example:

```bash
sudo autohotspot start
```

---

## HW-001 - Wireless interface detected

**Category:** Hardware  
**Severity:** Blocking  
**Related requirement:** FR-001

### Description

Checks whether at least one wireless network interface is available on the host machine.

### Pass condition

At least one wireless interface is detected.

### Fail condition

No wireless network interface is found.

### Recommendation

Make sure the Wi-Fi adapter is enabled and correctly recognized by the system.

---

## HW-002 - AP mode supported

**Category:** Hardware  
**Severity:** Blocking  
**Related requirement:** FR-001, FR-002

### Description

Checks whether the selected wireless interface supports AP mode.

AP mode is required to create a Wi-Fi access point.

### Pass condition

The selected wireless interface reports AP mode support.

### Fail condition

The selected wireless interface does not support AP mode.

### Recommendation

Use a wireless adapter that supports AP mode.

---

## HW-003 - Concurrent client/AP operation supported

**Category:** Hardware  
**Severity:** Warning  
**Related requirement:** FR-001, FR-006, FR-007

### Description

Checks whether the selected wireless interface can operate as a Wi-Fi client and as an access point at the same time.

This is required when the same wireless card is expected to stay connected to an upstream Wi-Fi network while also hosting the hotspot.

### Pass condition

The selected wireless interface appears to support concurrent client/AP operation.

### Fail condition

Concurrent client/AP operation is not supported or cannot be confirmed.

### Recommendation

Use a wireless adapter that supports concurrent client/AP mode, or use a separate network interface for the upstream connection.

---

## HW-004 - Hotspot interface selected

**Category:** Hardware  
**Severity:** Blocking  
**Related requirement:** FR-001, FR-002

### Description

Checks whether a valid wireless interface has been selected for hotspot creation.

This rule verifies that the selected interface exists, is wireless, and can be used as the target interface for the hotspot.

### Pass condition

A wireless interface is selected and exists on the host machine.

### Fail condition

No hotspot interface is selected, the selected interface does not exist, or the selected interface is not wireless.

### Recommendation

Select an available wireless interface to be used for hotspot creation.

---

## CFG-001 - Valid Hotspot SSID configured

**Category:** Configuration  
**Severity:** Blocking  
**Related requirement:** FR-003

### Description

Checks whether the hotspot SSID is configured and valid.

### Pass condition

The SSID is not empty and uses an accepted format.

### Fail condition

The SSID is missing, empty, or invalid.

### Recommendation

Provide a valid hotspot SSID.

---

## CFG-002 - Valid hotspot password configured

**Category:** Configuration  
**Severity:** Blocking  
**Related requirement:** FR-003

### Description

Checks whether the hotspot password is valid for WPA/WPA2 usage.

### Pass condition

The password is configured and has at least 8 characters.

### Fail condition

The password is missing or has fewer than 8 characters.

### Recommendation

Use a password with at least 8 characters.

---

## NET-001 - Hotspot gateway IP assignable

**Category:** Network  
**Severity:** Blocking  
**Related requirement:** FR-002, NFR-007

### Description

Checks whether the automatically selected hotspot gateway IP can be assigned to the hotspot interface.

The application may generate or select a default hotspot subnet and gateway IP. Before applying it, the system must verify that the selected gateway IP is valid and does not conflict with existing interfaces, routes, or active networks.

### Pass condition

The selected hotspot gateway IP is valid, belongs to the selected hotspot subnet, is not already assigned to another active interface, and does not conflict with existing routes or active networks.

### Fail condition

The selected hotspot gateway IP is invalid, already in use, outside the selected hotspot subnet, or conflicts with an existing interface, route, or active network.

### Recommendation

Select another hotspot subnet and gateway IP automatically, or notify the user if no valid network configuration can be found.

---

## NET-002 - DHCP range valid

**Category:** Network  
**Severity:** Blocking  
**Related requirement:** FR-004, NFR-007

### Description

Checks whether the selected DHCP range belongs to the selected hotspot subnet.

The DHCP range may be provided manually by the user or generated automatically by the application.

### Pass condition

The DHCP range is valid, belongs to the hotspot subnet, and does not include reserved addresses such as the hotspot gateway IP.

### Fail condition

The DHCP range is invalid, outside the hotspot subnet, overlaps with the hotspot gateway IP, or cannot be applied by the DHCP service.

### Recommendation

Select a DHCP range inside the hotspot subnet.

If the range is generated automatically, the application should choose another valid range. If the range is manually configured, the user should provide a valid range.

Example:

```text
Gateway IP: 192.168.50.1
Hotspot subnet: 192.168.50.0/24
Valid DHCP range: 192.168.50.10 - 192.168.50.100
Invalid DHCP range: 192.168.51.10 - 192.168.51.100
```
---

## NET-003 - DHCP service started

**Category:** Network  
**Severity:** Blocking  
**Related requirement:** FR-004  
**Status:** Draft

### Description

Checks whether the selected DHCP provider starts successfully for the hotspot interface.

The DHCP provider is responsible for assigning IP addresses and network configuration to clients connected to the hotspot.

**The final DHCP implementation will be defined later during the architecture and implementation phase.**

### Pass condition

The selected DHCP provider starts successfully, is bound to the hotspot interface, and is able to serve addresses from the selected DHCP range.

### Fail condition

The selected DHCP provider fails to start, cannot bind to the hotspot interface, uses an invalid configuration, or conflicts with another DHCP service.

### Recommendation

Check whether another process is already providing DHCP on the hotspot interface, whether the selected DHCP configuration is valid, and whether the selected DHCP provider can be started by the application.

---

## NET-004 - Host services reachable through hotspot network

**Category:** Network  
**Severity:** Warning  
**Related requirement:** FR-005, NFR-006

### Description

Checks whether connected devices can reach the host machine through the hotspot network.

This enables access to host services such as SSH, Syncthing, KDE Connect, local APIs, or local web applications.

### Pass condition

Connected devices can reach the host IP address on the hotspot network.

### Fail condition

Connected devices cannot reach the host IP address.

### Recommendation

Check the hotspot interface IP address, local firewall rules, and whether the target services are listening on the hotspot network.

---

## NET-005 - Upstream connection detected

**Category:** Network  
**Severity:** Warning  
**Related requirement:** FR-006, FR-008, NFR-006, NFR-012

### Description

Checks whether an upstream internet connection is currently available.

### Pass condition

An upstream network interface or default route is detected.

### Fail condition

No upstream internet connection is detected.

### Recommendation

Continue in local-only mode or connect the host machine to an upstream network before enabling internet sharing.

---

## NET-006 - NAT and IP forwarding enabled when upstream exists

**Category:** Network  
**Severity:** Blocking  
**Related requirement:** FR-007
**Depends on:** NET-005 - Upstream connection detected

### Description

Checks whether NAT and IP forwarding are configured when an upstream connection is available.

### Pass condition

IP forwarding is enabled and NAT rules are configured between the hotspot network and the upstream interface.

### Fail condition

An upstream connection exists, but IP forwarding or NAT configuration fails.

### Recommendation

Check firewall backend compatibility, forwarding settings, and whether the upstream interface was detected correctly.

---

## NET-007 - Local-only mode allowed without upstream

**Category:** Network  
**Severity:** Blocking  
**Related requirement:** FR-008, NFR-006, NFR-012
**Depends on:** NET-005 - Upstream connection detected

### Description

Checks whether the hotspot can continue operating without internet sharing when no upstream connection is available.

### Pass condition

The hotspot starts successfully and connected devices can communicate with the host machine even without upstream internet access.

### Fail condition

The hotspot fails only because no upstream connection is available.

### Recommendation

Do not treat missing upstream internet as a blocking error. Start the hotspot in local-only mode.

---

## AP-001 - Access point service started

**Category:** Access Point  
**Severity:** Blocking  
**Related requirement:** FR-002

### Description

Checks whether the Wi-Fi access point service starts successfully.

### Pass condition

`hostapd` starts successfully using the selected hotspot interface and configuration.

### Fail condition

`hostapd` fails to start, the interface is invalid, AP mode is unsupported, or the configuration is invalid.

### Recommendation

Check the selected wireless interface, AP mode support, SSID, password, and generated `hostapd` configuration.

---

## LFC-001 - Start command behavior

**Category:** Lifecycle  
**Severity:** Blocking  
**Related requirement:** FR-009, FR-010, NFR-004, NFR-011

### Description

Defines the expected behavior of the `start` command.

This case validates the complete startup flow, including readiness checks, cleanup, hotspot creation, DHCP startup, and NAT configuration when applicable.

### Pass condition

The `start` command completes the startup flow successfully.

It should:

- validate required dependencies and permissions
- check that the selected hotspot interface is available
- clean previous hotspot state before applying new changes
- configure the hotspot interface
- start the access point service
- start the DHCP service
- configure NAT when an upstream interface is used
- report a clear success or failure result

### Fail condition

The command starts only part of the hotspot and leaves the system in an inconsistent state.

Examples of failure include:

- access point starts but DHCP does not
- DHCP starts but interface configuration fails
- NAT rules are partially applied
- startup fails without rolling back partial changes
- the command reports success even though required components failed

### Recommendation

The start process should validate requirements before applying changes.

If startup fails after changes were applied, the tool should clean up partial changes or clearly report what remains active.
---

## LFC-002 - Stop command behavior

**Category:** Lifecycle  
**Severity:** Blocking  
**Related requirement:** FR-009, FR-010, NFR-003, NFR-008

### Description

Defines the expected behavior of the `stop` command.

### Pass condition

The `stop` command stops hotspot-related processes and removes temporary resources created by the tool.

### Fail condition

The command leaves active hotspot processes, virtual interfaces, IP addresses, or firewall rules created by the tool.

### Recommendation

Track created resources and remove only resources owned by the tool.

---

## LFC-003 - Restart command behavior

**Category:** Lifecycle  
**Severity:** Blocking  
**Related requirement:** FR-009, FR-010, NFR-004

### Description

Defines the expected behavior of the `restart` command.

### Pass condition

The `restart` command performs a safe stop followed by a start.

### Fail condition

The command duplicates interfaces, processes, IP addresses, or firewall rules.

### Recommendation

Implement restart as a controlled sequence of stop and start operations.

---

## LFC-004 - Status command behavior

**Category:** Lifecycle  
**Severity:** Non-blocking  
**Related requirement:** FR-009, NFR-010

### Description

Defines the expected behavior of the `status` command.

### Pass condition

The command reports the current hotspot state in a human-readable format.

The status output may include:

- hotspot running state
- hotspot interface
- gateway IP
- DHCP service state
- access point service state
- upstream interface
- NAT status

### Fail condition

The command provides no useful state information or reports misleading information.

### Recommendation

Use clear status indicators such as `running`, `stopped`, `partial`, or `failed`.

---

## LFC-005 - Lifecycle commands are idempotent

**Category:** Lifecycle  
**Severity:** Blocking  
**Related requirement:** NFR-004

### Description

Checks whether lifecycle commands can be executed repeatedly without breaking the system state.

### Pass condition

Running `start`, `stop`, `restart`, or `status` multiple times produces predictable results.

### Fail condition

Repeated command execution creates duplicate resources, crashes unnecessarily, or leaves stale state behind.

### Recommendation

Before creating resources, check whether they already exist. Before deleting resources, check whether they are owned by the tool.

---

## CLN-001 - Cleanup only managed resources

**Category:** Cleanup  
**Severity:** Blocking  
**Related requirement:** FR-010, NFR-002, NFR-003

### Description

Checks whether cleanup operations only affect resources created or managed by the tool.

### Pass condition

The tool only removes its own virtual interfaces, IP addresses, processes, temporary files, and firewall rules.

### Fail condition

The tool removes unrelated interfaces, firewall rules, routes, services, or user processes.

### Recommendation

Use predictable names, generated configuration files, PID files, comments, or dedicated chains to identify resources owned by the tool.

---

## CLN-002 - Cleanup before start

**Category:** Cleanup  
**Severity:** Blocking  
**Related requirement:** FR-010, NFR-004, NFR-011

### Description

Checks whether stale hotspot resources from previous executions are cleaned before starting.

### Pass condition

Before starting, the tool removes stale hotspot-related resources created by previous executions.

### Fail condition

Startup fails or duplicates resources because stale state was not cleaned.

### Recommendation

Run a safe cleanup routine before creating the hotspot.

---

## FW-001 - No destructive firewall operations

**Category:** Firewall  
**Severity:** Blocking  
**Related requirement:** NFR-002, NFR-009

### Description

Checks whether the tool avoids destructive firewall operations.

### Pass condition

The tool only adds or removes firewall rules that are required and owned by the tool.

### Fail condition

The tool flushes global firewall rules or removes rules unrelated to the hotspot.

### Recommendation

Do not use destructive commands such as global firewall flushes. Prefer dedicated chains, rule comments, or exact rule deletion.

---

## FW-002 - NAT rules are reversible

**Category:** Firewall  
**Severity:** Blocking  
**Related requirement:** FR-007, NFR-008, NFR-009

### Description

Checks whether NAT rules created by the tool can be safely removed when the hotspot stops.

### Pass condition

The tool can identify and remove the NAT rules it created.

### Fail condition

The tool cannot distinguish its own NAT rules from unrelated system firewall rules.

### Recommendation

Create identifiable NAT rules and store enough state to remove them safely.

---

## DIAG-001 - Doctor command checks system readiness

**Category:** Diagnostics  
**Severity:** Non-blocking  
**Related requirement:** FR-011, NFR-005

### Description

Checks whether the diagnostic command reports system readiness before starting the hotspot.

### Pass condition

The diagnostic command checks dependencies, permissions, wireless capabilities, upstream connection state, and possible stale hotspot resources.

### Fail condition

The diagnostic command does not detect relevant startup problems or provides unclear output.

### Recommendation

Implement a `doctor` command that reports checks using clear statuses such as `OK`, `WARN`, and `ERROR`.

---

## DIAG-002 - Diagnostic messages are actionable

**Category:** Diagnostics  
**Severity:** Warning  
**Related requirement:** NFR-005, NFR-010

### Description

Checks whether error and warning messages explain what failed and how the user can fix it.

### Pass condition

Messages clearly describe the problem and provide a concrete recommendation.

### Fail condition

Messages are vague, misleading, or do not help the user fix the issue.

### Recommendation

Each error should explain:

- what failed
- why it matters
- what the user can do next

---

## FAIL-001 - Failed startup is safely handled

**Category:** Failure Handling  
**Severity:** Blocking  
**Related requirement:** NFR-011

### Description

Checks whether the system handles partial startup failures safely.

### Pass condition

If startup fails, the tool stops the operation and attempts to clean up partial changes.

### Fail condition

The tool leaves behind broken interfaces, running processes, assigned IP addresses, or firewall rules after a failed startup.

### Recommendation

Use a fail-safe startup flow and call cleanup routines when any critical step fails.

---

## OUT-001 - Human-readable terminal output

**Category:** Output  
**Severity:** Non-blocking  
**Related requirement:** NFR-010

### Description

Checks whether command output is readable and understandable in a terminal.

### Pass condition

The tool prints clear, structured, human-readable output.

### Fail condition

The output is confusing, too verbose, too silent, or difficult to understand.

### Recommendation

Use concise messages and clear status labels.