# Third-party protocol references

DivoomProtocol.swift is an independent Swift implementation informed by the following reverse-engineered protocol implementations. Divoom is a trademark of its respective owner; this app is an unofficial controller.

## hass-divoom

- Source: https://github.com/d03n3rfr1tz3/hass-divoom
- Inspected revision: 0e9959a9009d9f8ce3be79476f464d593d85bc91
- Copyright (c) 2020 Dirk Sarodnick
- MIT License: full notice in LICENSE-hass-divoom.txt.
- Used for Ditoo model characteristics, command layouts, palette-frame layout, bit-packing semantics and animation chunk sizes. Golden vectors were independently derived from those layouts.

## node-divoom-timebox-evo

- Source: https://github.com/RomRider/node-divoom-timebox-evo
- Inspected revision: 2a086b86feaca1b544029f97803336579f0d3a25
- Protocol document used for independent corroboration of framing, palette bit packing, and the 0x44/0x49 formats. No JavaScript source copied.

## divoom-ditoo-pro-controller

- Source: https://github.com/andreas-mausch/divoom-ditoo-pro-controller
- Inspected revision: 88003f6360c6f6a1fa6e1ab2e79bf9379911907e
- Rust protocol/alarm.rs used to corroborate alarm field order. No Rust source copied. Ditoo-Pro behavior does not establish Ditoo-Plus compatibility.

## divoom-minitoo-osx

- Source: https://github.com/alvinunreal/divoom-minitoo-osx
- Existing workspace clone used as a transport reference and negative comparison for the incompatible LCD/Zstandard payload. The Swift palette codec does not use its media encoder.
