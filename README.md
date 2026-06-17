# AutoHotspot

AutoHotspot is a Linux command-line tool designed to create and manage a local Wi-Fi access point from a Linux notebook.

The main goal of the project is to provide a stable local network for a mobile phone, allowing it to connect automatically to the notebook and use local services such as KDE Connect, Syncthing, SSH, local web applications, or file sharing tools.

AutoHotspot is not intended to be only a basic hotspot launcher, since most desktop environments already provide that feature. Instead, the project focuses on automating a more specific use case: keeping the notebook connected to an existing network while also hosting a local access point, when the wireless hardware and drivers support it.

If possible, AutoHotspot can also share internet access from the notebook's upstream connection to the hosted access point.

## Main idea

AutoHotspot tries to support the following scenario:

1. The notebook is connected to an existing network.
2. The notebook creates a local Wi-Fi access point.
3. The mobile phone connects automatically to that access point.
4. The phone can access local services running on the notebook.
5. If supported and configured, the phone can also access the internet through the notebook.

Example:

```text
Existing Wi-Fi / Internet
        |
        | upstream connection
        v
    Notebook
        |
        | hosted access point
        v
    Mobile phone
```

This allows the phone and notebook to communicate through a predictable local network, even when the user does not want to depend on an external router, changing Wi-Fi networks, or unstable LAN discovery.

## Network modes

AutoHotspot should support different operating modes depending on hardware and configuration.

### Local-only mode

The notebook creates an access point for local communication only.

In this mode:

- the phone connects to the notebook hotspot
- DHCP assigns an IP address to the phone
- the phone can access local services on the notebook
- internet sharing is not enabled

Example use cases:

- KDE Connect
- Syncthing
- SSH
- Local web apps
- Local development servers

### Shared-internet mode

The notebook creates an access point and shares internet from an upstream interface.

In this mode:

- The notebook has an upstream connection
- The hotspot provides DHCP to connected clients
- NAT and IP forwarding are configured
- The phone can access both local services and the internet

The upstream interface may be:

- Ethernet
- Another Wi-Fi interface
- The same Wi-Fi card, only if concurrent client/AP mode is supported

### Concurrent Wi-Fi mode

When supported by the wireless card and driver, the notebook may stay connected to an existing Wi-Fi network while also hosting an access point.

This is the most important advanced use case of AutoHotspot.

Example:

```text
wlan0 as client  -> connected to home Wi-Fi
wlan0 as AP      -> hosting AutoHotspot network
```

## Planned commands

### `start`

Starts the hotspot.

Expected behavior:

1. Validate required permissions and dependencies.
2. Detect wireless interface capabilities.
3. Check whether AP mode is supported.
4. Check whether concurrent client/AP mode is possible, if requested.
5. Clean stale resources from previous executions.
6. Configure the hotspot interface.
7. Start the access point service.
8. Start the DHCP service.
9. Configure NAT if internet sharing is enabled.
10. Report success or failure clearly.

Example local-only hotspot:

```bash
sudo autohotspot start --interface wlan0
```

Example with custom hotspot name and password:

```bash
sudo autohotspot start --interface wlan0 --ssid AutoHotspot --password "change-this-password"
```

The `--ssid` argument sets the Wi-Fi network name exposed by the hotspot.
The `--password` argument sets the WPA/WPA2 password used by connected devices.
The password must be at least 8 characters long.

`--passphrase` may also be supported as an alias for `--password`.

Example with internet sharing from Ethernet:

```bash
sudo autohotspot start --interface wlan0 --upstream eth0 --share-internet
```

Example attempting concurrent Wi-Fi mode:

```bash
sudo autohotspot start --interface wlan0 --upstream wlan0 --share-internet
```

### `status`

Shows the current hotspot state in a human-readable format.

Example:

```text
AutoHotspot status: running

Hotspot interface: wlan0_ap
Gateway IP: 192.168.50.1
DHCP service: running
Access point service: running
Connected clients: 1
Upstream interface: wlan0
Internet sharing: enabled
NAT: enabled
Concurrent Wi-Fi mode: supported
```

Possible global states:

- `running`
- `stopped`
- `partial`
- `failed`

### `stop`

Stops the hotspot and removes resources created by the tool.

Expected behavior:

1. Stop hotspot-related services.
2. Remove hotspot IP configuration.
3. Remove NAT rules created by the tool.
4. Remove virtual interfaces created by the tool, if applicable.
5. Restore the system to a clean state when possible.

### `cleanup`

Removes stale hotspot-related resources from previous executions.

## Hardware considerations

Not every Wi-Fi card supports hosting an access point while also being connected to another Wi-Fi network.

AutoHotspot should detect and report this clearly.

Possible outcomes:

- AP mode supported.
- AP mode not supported.
- Concurrent client/AP mode supported.
- Concurrent client/AP mode not supported.
- Internet sharing available through another interface.
- Internet sharing unavailable.

The tool should not assume that concurrent Wi-Fi mode is always possible.
