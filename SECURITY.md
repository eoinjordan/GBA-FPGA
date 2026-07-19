# Security policy

This is experimental hardware and firmware. Treat cartridge write support, battery charging, and external power circuitry as safety-critical.

Report security or destructive-write issues privately to the repository owner before public disclosure. Include the exact hardware revision, bitstream or commit, and reproduction steps.

The ROM-only cartridge reader in this repository holds `/WR` inactive. Do not enable writes until save-memory type detection, voltage levels, write protection, and power-failure behaviour have been independently validated.
