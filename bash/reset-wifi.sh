#!/bin/bash
logger "Resetting PCIE device 0000:02:00.0 (WiFi)"
echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove
echo 1 > /sys/bus/pci/rescan
