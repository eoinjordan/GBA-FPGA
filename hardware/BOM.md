# Nano 20K handheld bill of materials

This BOM records the working USB-powered LCD setup and the parts needed to
package it. The [CSV](nano20k_handheld_bom.csv) includes quantities, status and
fit notes. Unselected parts have no invented part number, cost or screw count.

## Working electronics and controls

| Part | Quantity | Status |
|---|---:|---|
| Sipeed Tang Nano 20K, GW2AR-LV18QN88C8/I7 | 1 | Owned; Studio and Game Boy tested |
| HT043IBB-16A3047-H4, 4.3-inch 480x272 RGB LCD | 1 | Owned; tested on the board's LCD connector |
| USB data/power cable matching the board | 1 | Used for programming, UART and bench power |
| Passive split GBA button PCBs | 1 set | Owned; external GPIO wiring pending |
| Existing GBA button caps, D-pad and silicone contacts | 1 set | Reuse; case fit needs checking |
| Button wiring and connectors | As required | Pin map, lengths and connector selection pending |

S1 and S2 provide Start and A during bring-up. The current FPGA targets have
no assigned GPIO for the external button PCBs. Keep HDMI unplugged while
using the LCD because it shares data pins. See the
[LCD notes](../docs/LCD_480X272.md) for the interface; screen diagonal
or resolution alone does not establish connector compatibility.

## Printed parts and fasteners

| Part | Quantity | File |
|---|---:|---|
| Front shell | 1 | [STL](../3D-Case/gba_fpga_front_shell_v2.stl) |
| Back shell | 1 | [STL](../3D-Case/gba_fpga_back_shell_v2.stl) |
| Sloped rear module cover | 1 | [STL](../3D-Case/gba_fpga_sloped_rear_module_cover_v2.stl) |
| LCD retainer | 1 | [STL](../3D-Case/gba_fpga_lcd_retainer_v2.stl) |
| Nano 20K tray | 1 | [STL](../3D-Case/gba_fpga_tang_nano_20k_tray_v2.stl) |
| Button PCB clamps | 1 set, 8 clamps | [STL](../3D-Case/gba_fpga_button_pcb_clamp_set_v2.stl) |
| Cartridge adapter tray | 1, optional | [STL](../3D-Case/gba_fpga_cartridge_adapter_tray_v2.stl) |
| Screws and inserts | To be measured | Match each boss and hole; lengths and counts are not validated |
| Filament | Slicer estimate | Measure from the chosen print profile |

The enclosure dimensions are estimates from the existing v2 design, not
measurements of an assembled handheld. The generator uses several hole
diameters, including 2.2, 2.4, 2.5, 2.8 and 3.0 mm. A single fastener size
must not be assumed for the whole assembly. Check inserts and screw depth
on a small test print before selecting the fasteners.

The [case notes](../3D-Case/README.md) explain dimensions, printing and
validation limits. The packaged v2 case is intended for the larger LCD;
no existing v1 or smaller-LCD case was found in the local drive search on
1 October. A new [compact prototype](../3D-Case/compact/README.md) adds a
smaller-screen shell and interchangeable 20K/60K SOM mounting adapters.

For that variant, substitute its front/back shells, display bezel, LCD
retainer and clamp set for the v2 printed parts. Select **one** board adapter.
Its small LCD model, carrier, fastener sizes and physical fit remain pending.
The separate [compact BOM CSV](compact_handheld_bom.csv) lists both board
options and the unselected smaller panel.
The compact design uses six perimeter, four adapter and four retainer
fastener positions; these counts describe the CAD, not a validated kit.

## Future additions

Battery cell, charging/power-path board, regulators, power switch, audio
amplifier and speaker remain unselected. They are recorded as pending in the
CSV rather than presented as a complete battery-powered build.

The optional cartridge assembly has its own
[reader BOM](gba_cartridge_reader_bom.csv). Its connector and bridge are not
part of the currently validated Nano 20K LCD flow. The case's adapter tray
assumes an 86x54 mm board envelope; verify the actual board before printing.
