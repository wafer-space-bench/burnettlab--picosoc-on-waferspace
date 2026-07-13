# picorv32 SoC with wafer.space flow

An attempt to make a simple SoC based on a PicoRV32 CPU. Formed by mashing components from the following projects together:

https://github.com/wafer-space/gf180mcu-project-template
https://github.com/JBFSF/SensorSoC
https://github.com/YosysHQ/picorv32
https://github.com/lawrie/pico_ram_soc

Established as a FOSS flow proof of concept for SoC design.

Eventually we hope to add wishbone bus and peripherals, open-drain IO for I2C and I2C controller, bandgap reference and voltage regulator, a radio...

Pinout is mininal: power, ground, clock, reset, serial tx/rs, QSPI (6 pins).