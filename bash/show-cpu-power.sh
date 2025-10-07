#!/bin/bash

# Enable cpu power usage for mangohud
sudo chmod o+r /sys/class/powercap/intel-rapl\:0/energy_uj
