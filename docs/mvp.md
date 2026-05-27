# MVP - Local Wi-Fi Hotspot Manager

## Overview

The MVP is a Bash-based Linux CLI tool that creates a local Wi-Fi hotspot from a compatible wireless network card.

The tool verifies whether the wireless card supports AP mode and whether it can operate as a hotspot while the host machine is connected to an upstream Wi-Fi network.

The hotspot provides a local network for connected devices, allows those devices to communicate with the host machine, and optionally shares the host's internet connection through NAT when an upstream connection is available.

## Goal

Build a first working version of a Linux CLI tool that allows the user to:

- Create a local Wi-Fi hotspot.
- Connect external devices to the host machine through that hotspot.
- Access local services exposed by the host machine.
- Share the host's upstream internet connection when available.
- Work as a local-only hotspot when no upstream connection is available.

## Problem

In some environments, such as universities, labs, public networks, or workplaces, a user may need a private local network between their notebook and other devices.

This is useful for accessing local services such as:

- KDE Connect
- Syncthing
- SSH
- Local web applications
- Local APIs
- Development or debugging tools

The system solves this by allowing the notebook to act as a controlled Wi-Fi access point.

## MVP Scope

The MVP includes the following features:

- Detect available wireless network interfaces.
- Check whether a wireless interface supports AP/hotspot mode.
- Check whether the selected wireless interface can support hotspot creation while the host is connected to an upstream Wi-Fi network.
- Allow the user to select the wireless interface used for the hotspot.
- Allow the user to configure the hotspot SSID and password.
- Create a local Wi-Fi hotspot using the selected wireless interface.
- Assign a local gateway IP address to the hotspot interface.
- Provide DHCP leases to devices connected to the hotspot.
- Allow connected devices to access services exposed by the host machine over the hotspot network.
- Detect whether an upstream internet connection is available.
- Configure NAT and IP forwarding when an upstream connection is available.
- Work as a local-only hotspot when no upstream connection is available.
- Provide commands to start, stop, restart, and check the hotspot status.
- Clean up hotspot-related processes, virtual interfaces, IP addresses, and firewall rules before starting or stopping.

## Out of Scope

The following features are not included in the first MVP:

- Graphical user interface.
- Full scheduling engine.
- Time-based execution rules.
- Location-based execution rules.
- Automatic execution based on known Wi-Fi networks.
- Permanent systemd service installation.
- Advanced profile management.
- Multi-hotspot support.
- Automatic KDE Connect or Syncthing configuration.
- Support for multiple Linux distributions with different networking stacks.

## Expected CLI Commands

```bash
autohotspot start
autohotspot stop
autohotspot restart
autohotspot status