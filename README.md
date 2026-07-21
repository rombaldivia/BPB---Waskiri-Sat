# BPB — Waskiri-Sat

<p align="center">
  <strong>Reconfigurable Backplane Communication Architecture for the Waskiri-Sat CubeSat Platform</strong>
</p>

<p align="center">
  CPLD/FPGA-based interface control, deterministic serial routing, and safe subsystem interconnection for embedded spacecraft development.
</p>

---

## Executive Overview

The **Backplane Board (BPB)** is the central digital-interconnection subsystem of the Waskiri-Sat CubeSat architecture. It provides a controlled communication layer between the mission controller and the distributed spacecraft subsystems, allowing serial interfaces to be selectively enabled, isolated, monitored, and routed through programmable digital logic.

Rather than operating as a passive wiring element, the BPB is conceived as an **active and reconfigurable backplane**. Its logic establishes deterministic communication paths, prevents unintended bus contention, preserves safe electrical states when interfaces are disconnected, and provides a scalable foundation for subsystem integration, debugging, and mission-level validation.

This repository documents the digital-logic implementation and verification workflow used to prototype the BPB communication architecture on CPLD/FPGA hardware.

---

## System Role

Within Waskiri-Sat, the BPB acts as the intermediary between the central controller and backplane-connected devices. Its principal responsibilities include:

- Controlled routing of UART and SPI communication channels.
- Selective activation and isolation of spacecraft subsystems.
- Protection against simultaneous or conflicting interface selection.
- Preservation of defined idle and safe states on disconnected buses.
- Interface-status indication for integration and debugging activities.
- Support for rear-access interface functions within the BPB subsystem.
- Hardware abstraction between the mission controller and connected payload or service modules.

The design is intended to reduce direct point-to-point wiring complexity while improving testability, modularity, and operational control.

---

## Digital Architecture

The current prototype is organized around two principal logic blocks:

### UART Multiplexer

The UART stage behaves as a configurable digital gate between the controller and a selected backplane device. When a channel is disabled, the receive path is maintained in a defined idle state to avoid floating or invalid logic conditions.

### UART/SPI Multiplexer

The combined UART/SPI stage extends the routing concept to synchronous serial communication. Disabled SPI signals are driven to safe states, reducing the possibility of unintended clocking, chip-selection conflicts, or undefined peripheral behavior.

Together, these blocks establish a deterministic communication fabric that can later be expanded to accommodate additional subsystem-selection, arbitration, and health-monitoring functions.

---

## Engineering Objectives

| Objective | Engineering Intent |
| --- | --- |
| Deterministic routing | Ensure that only the intended communication path is active. |
| Safe isolation | Maintain predictable UART and SPI states when a subsystem is disconnected. |
| Modular integration | Allow subsystem interfaces to be validated independently before spacecraft-level integration. |
| Reconfigurability | Implement communication control in programmable logic rather than fixed discrete routing. |
| Observability | Expose interface states through LEDs and simulation waveforms for verification. |
| Flight-oriented evolution | Use the FPGA prototype to validate logic before migration to a lower-power CPLD implementation. |

---

## Prototype Platform

The communication architecture is currently validated using:

```text
Development board : Terasic DE10-Lite
Programmable logic: Intel MAX 10 — 10M50DAF484C7G
Toolchain         : Quartus Prime Lite 20.1
Design language   : VHDL
Verification      : Compilation, testbench simulation, waveform inspection, and hardware tests
```

The MAX 10 platform is used as a development and verification environment. The final BPB architecture is intended to retain the validated logic while targeting a lower-power implementation appropriate for the spacecraft design.

---

## Verification Strategy

The BPB verification process follows a staged engineering workflow:

1. **RTL definition** — describe the required UART and SPI routing behavior in VHDL.
2. **Compilation and elaboration** — validate syntax, hierarchy, and target-device compatibility in Quartus.
3. **Functional simulation** — exercise interface-selection states through dedicated testbenches.
4. **Waveform inspection** — confirm routing, isolation, idle-state behavior, and conflict handling.
5. **Pin-assignment review** — verify consistency between the logical design and the prototype hardware.
6. **Hardware validation** — program the development device and evaluate the interfaces with representative controllers and peripherals.
7. **Subsystem integration** — incorporate the validated communication blocks into the wider BPB and Waskiri-Sat architecture.

---

## Design Principles

- **Fail-safe behavior:** inactive interfaces must not produce uncontrolled transitions.
- **Deterministic selection:** communication ownership must be explicit and observable.
- **Separation of concerns:** interface routing is isolated from higher-level mission software.
- **Incremental verification:** logic is validated in simulation before hardware integration.
- **Technology portability:** the architecture remains conceptually transferable between FPGA and CPLD targets.
- **Traceable development:** requirements, implementation, simulation, and hardware evidence are treated as connected engineering artifacts.

---

## Repository Scope

This repository contains the programmable-logic work associated with the BPB prototype, including VHDL communication blocks, simulation resources, hardware-integration material, and technical documentation.

```text
BPB---Waskiri-Sat/
├── VHDL design sources
├── UART and SPI multiplexing logic
├── Testbenches and simulation resources
├── Quartus project and pin-assignment files
├── Embedded-interface prototypes
└── Technical documentation
```

Exact filenames and prototype configurations may evolve as the BPB progresses through subsystem and mission-level reviews.

---

## Project Status

The repository represents an active engineering-development environment for the Waskiri-Sat Backplane Board. The present work focuses on validating the serial communication interconnection, programmable routing behavior, and safe interface states required before final hardware consolidation.

Current and subsequent development stages include:

- UART and SPI multiplexing verification.
- CPLD/FPGA resource and timing evaluation.
- Controller-to-backplane communication tests.
- Rear-access interface integration within the BPB subsystem.
- Electrical and connector-level consolidation.
- Migration from the development FPGA platform to the selected flight-oriented programmable-logic device.

---

## Waskiri-Sat Context

Waskiri-Sat is a modular CubeSat development initiative in which subsystem integration, verification, and maintainability are treated as primary design requirements. The BPB contributes to this objective by providing a programmable digital backbone for controlled communication between the mission controller and distributed spacecraft electronics.

---

<p align="center">
  <strong>Controlled interfaces. Deterministic communication. Modular spacecraft integration.</strong>
</p>
