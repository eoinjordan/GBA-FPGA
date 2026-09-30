#!/usr/bin/env python3
"""GBA-FPGA helper. Same behaviour on Linux, macOS and Windows.

Commands:
  doctor                  list the tools found and what each project can do here
  bootstrap [NAME ...]    clone upstream projects at the versions pinned in UPSTREAMS.json
  test                    run every testbench and the Python unit tests
  lint                    Verilator lint of the synthesizable RTL
  build PROJECT           build a Tang Nano 20K bitstream
  fetch PROJECT           download the pinned upstream release bitstream and firmware
  flash PROJECT           program a Tang Nano 20K
  ide-project CORE        regenerate the Gowin IDE project for gbtang/snestang

Projects: gba_lcd_480x272 (in this repository), gbtang, snestang.
Standard library only; Python 3.8 or newer.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import unittest
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "build"
BOARD_BUILD = BUILD / "tangnano20k"
UPSTREAMS_FILE = REPO / "UPSTREAMS.json"
IS_WINDOWS = os.name == "nt"
IS_MACOS = sys.platform == "darwin"
EXE = ".exe" if IS_WINDOWS else ""


# ============================================================================
# Output helpers
# ============================================================================

def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    sys.stdout.flush()                    # keep the error after any progress output
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def run(cmd: List[str], cwd: Optional[Path] = None, log: Optional[Path] = None,
        check: bool = True) -> subprocess.CompletedProcess:
    """Run a command with the tool environment, optionally teeing output to a log."""
    cmd = [str(c) for c in cmd]
    # Windows resolves the program with the parent's PATH, not env["PATH"].
    if not os.path.isabs(cmd[0]):
        cmd[0] = tool(cmd[0]) or fail(f"{cmd[0]} not found (run 'doctor')")
    shown = " ".join(cmd)
    print(f"  $ {shown if len(shown) < 300 else shown[:297] + '...'}")
    result = subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=TOOL_ENV,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            errors="replace")
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(result.stdout, encoding="utf-8")
    if check and result.returncode != 0:
        print(result.stdout[-4000:])
        fail(f"command failed ({result.returncode}): {cmd[0]}" + (f"; full log: {log}" if log else ""))
    return result


def _home() -> Optional[Path]:
    """Home directory, or None when the environment does not define one
    (Windows Python started from an MSYS make, for example)."""
    try:
        return Path.home()
    except (RuntimeError, KeyError):
        pass
    if os.environ.get("HOME") and Path(os.environ["HOME"]).is_dir():   # MSYS passes a converted HOME
        return Path(os.environ["HOME"])
    if IS_WINDOWS and os.environ.get("USERNAME"):
        candidate = Path(os.environ.get("SystemDrive", "C:") + "/") / "Users" / os.environ["USERNAME"]
        if candidate.is_dir():
            return candidate
    return None


# ============================================================================
# Tool discovery
# ============================================================================
# OSS CAD Suite (yosys, nextpnr, iverilog, openFPGALoader...) is used from PATH
# or from OSS_CAD_SUITE / a standard unpack location. On Windows its lib/
# directory must also be on PATH for the DLLs.

def _oss_cad_suite() -> Optional[Path]:
    candidates = []
    if os.environ.get("OSS_CAD_SUITE"):
        candidates.append(Path(os.environ["OSS_CAD_SUITE"]))
    home = _home()
    candidates += ([home / "oss-cad-suite"] if home else []) + [Path("/opt/oss-cad-suite"), Path("C:/oss-cad-suite")]
    for root in candidates:
        if (root / "bin").is_dir():
            return root
    return None


def _tool_env() -> Dict[str, str]:
    env = dict(os.environ)
    suite = _oss_cad_suite()
    if suite:
        extra = [str(suite / "bin")] + ([str(suite / "lib")] if IS_WINDOWS else [])
        env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
        # The Windows verilator_bin.exe has a build-machine path compiled in.
        if IS_WINDOWS and "VERILATOR_ROOT" not in env and (suite / "share" / "verilator").is_dir():
            env["VERILATOR_ROOT"] = str(suite / "share" / "verilator")
    return env


TOOL_ENV = _tool_env()


TOOL_ALTERNATIVES = {"verilator": ["verilator_bin"]}   # Windows OSS CAD Suite ships verilator_bin.exe


def tool(name: str) -> Optional[str]:
    for candidate in [name] + TOOL_ALTERNATIVES.get(name, []):
        found = shutil.which(candidate, path=TOOL_ENV["PATH"])
        if found:
            return found
    return None


class GowinInstall(NamedTuple):
    root: Path
    version: str
    gw_sh: Path
    programmer_cli: Optional[Path]


def _gowin_from_root(root: Path) -> Optional[GowinInstall]:
    if (root / "bin" / f"gw_sh{EXE}").is_file():      # pointed at .../IDE
        root = root.parent
    gw_sh = root / "IDE" / "bin" / f"gw_sh{EXE}"
    if not gw_sh.is_file():
        return None
    match = re.search(r"(\d+\.\d+\.\d+(?:\.\d+)?)", root.name)
    programmer = root / "Programmer" / "bin" / f"programmer_cli{EXE}"
    return GowinInstall(root, match.group(1) if match else "unknown", gw_sh,
                        programmer if programmer.is_file() else None)


def gowin_installs(explicit: Optional[str] = None) -> List[GowinInstall]:
    """All Gowin EDA installs found, newest first. Gowin has no macOS release."""
    roots: List[Path] = []
    for value in (explicit, os.environ.get("GOWIN_HOME")):
        if value:
            roots.append(Path(value).expanduser())
    on_path = shutil.which(f"gw_sh{EXE}", path=TOOL_ENV["PATH"])
    if on_path:
        roots.append(Path(on_path).resolve().parents[2])
    home = _home()
    patterns = [(Path("C:/Gowin"), "Gowin_V*"), (Path("C:/"), "Gowin_V*"),
                (Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Gowin", "Gowin_V*"),
                (Path("/opt"), "[Gg]owin*")]
    if home:
        patterns += [(home, "Gowin*"), (home / "Gowin", "Gowin_V*")]
    for base, pattern in patterns:
        if base.is_dir():
            roots += sorted(base.glob(pattern))
    found: Dict[Path, GowinInstall] = {}
    for root in roots:
        install = _gowin_from_root(root)
        if install and install.root.resolve() not in found:
            found[install.root.resolve()] = install
    def version_key(install: GowinInstall):
        return [int(p) for p in re.findall(r"\d+", install.version)] or [0]
    return sorted(found.values(), key=version_key, reverse=True)


def pick_gowin(explicit: Optional[str], wanted_version: Optional[str]) -> Optional[GowinInstall]:
    installs = gowin_installs(explicit)
    if explicit:
        return installs[0] if installs else None
    if wanted_version:
        for install in installs:
            if install.version.startswith(wanted_version):
                return install
    return installs[0] if installs else None


# ============================================================================
# Projects and pinned upstream metadata
# ============================================================================

LOCAL_PROJECT = "gba_lcd_480x272"
LOCAL_DIR = REPO / "tangnano20k" / LOCAL_PROJECT
LOCAL_PROJECTS = {LOCAL_PROJECT, "gbtang_lcd", "studio_lcd"}
UPSTREAM_KEYS = {"gbtang": "GBTang", "snestang": "SNESTang"}
PROJECTS = sorted(LOCAL_PROJECTS) + sorted(UPSTREAM_KEYS)
BOARD = "tangnano20k"                      # openFPGALoader board name
NEXTPNR_FAMILY = {"GW2AR-18C": "GW2A-18C"}  # .gprj device name -> nextpnr/gowin_pack family


def upstreams() -> List[dict]:
    return json.loads(UPSTREAMS_FILE.read_text(encoding="utf-8"))["projects"]


def upstream(project: str) -> dict:
    name = UPSTREAM_KEYS[project]
    for entry in upstreams():
        if entry["name"] == name:
            return entry
    fail(f"{name} missing from UPSTREAMS.json")


def project_build_dir(project: str) -> Path:
    return BOARD_BUILD / project


# ---- Gowin project files (.gprj + impl/project_process_config.json) ----------

class GowinProject(NamedTuple):
    device_name: str      # e.g. GW2AR-18C
    part: str             # e.g. GW2AR-LV18QN88C8/I7
    verilog: List[Path]
    cst: List[Path]
    sdc: List[Path]
    top: str
    output_name: str
    options: dict


def read_gowin_project(project_dir: Path) -> GowinProject:
    gprj = next(project_dir.glob("*.gprj"), None)
    if gprj is None:
        fail(f"no .gprj in {project_dir}")
    root = ET.parse(gprj).getroot()
    device = root.find("Device")
    files: Dict[str, List[Path]] = {"file.verilog": [], "file.cst": [], "file.sdc": []}
    for entry in root.iter("File"):
        if entry.get("enable") == "1" and entry.get("type") in files:
            files[entry.get("type")].append((project_dir / entry.get("path")).resolve())
    config = json.loads((project_dir / "impl" / "project_process_config.json").read_text(encoding="utf-8"))
    return GowinProject(device.get("name"), device.get("pn"), files["file.verilog"], files["file.cst"],
                        files["file.sdc"], config["TopModule"], config["OUTPUT_BASE_NAME"], config)


# ============================================================================
# doctor
# ============================================================================

TOOLS = [
    ("python3", "tests, SD and ROM tools", True),
    ("iverilog", "simulation (make test)", True),
    ("vvp", "simulation (make test)", True),
    ("ghdl", "VHDL scaffold test (optional)", False),
    ("verilator", "lint (optional)", False),
    ("yosys", "open-source synthesis", False),
    ("nextpnr-himbaechel", "open-source place and route", False),
    ("gowin_pack", "open-source bitstream packing", False),
    ("openFPGALoader", "programming the board", False),
    ("git", "bootstrap", True),
    ("node", "GBA Studio builds (optional)", False),
    ("npm", "GBA Studio builds (optional)", False),
]


def cmd_doctor(args: argparse.Namespace) -> int:
    print(f"Platform: {platform.system()} {platform.machine()}, Python {platform.python_version()}")
    suite = _oss_cad_suite()
    print(f"OSS CAD Suite: {suite if suite else 'not found (tools must be on PATH)'}")
    missing_required = False
    for name, purpose, required in TOOLS:
        path = tool(name) or (sys.executable if name == "python3" else None)
        state = "ok      " if path else ("MISSING " if required else "-       ")
        missing_required |= required and not path
        print(f"  {state} {name:20s} {purpose}")
    installs = gowin_installs(args.gowin)
    if installs:
        for install in installs:
            prog = "programmer_cli ok" if install.programmer_cli else "no programmer_cli"
            print(f"  ok       Gowin EDA {install.version:10s} {install.root} ({prog})")
    else:
        note = "Gowin EDA has no macOS release" if IS_MACOS else "not found (set GOWIN_HOME or use --gowin)"
        print(f"  -        Gowin EDA            {note}")

    open_flow = all(tool(t) for t in ("yosys", "nextpnr-himbaechel", "gowin_pack"))
    print("\nWhat this machine can do:")
    print(f"  {LOCAL_PROJECT:16s} build: {'open-source flow' if open_flow else ''}"
          f"{' + ' if open_flow and installs else ''}{'Gowin' if installs else ''}"
          f"{'none (install OSS CAD Suite or Gowin EDA)' if not (open_flow or installs) else ''}")
    for project in sorted(UPSTREAM_KEYS):
        pin = upstream(project)
        checkout = REPO / pin["path"]
        state = "checked out" if (checkout / ".git").exists() else "not bootstrapped"
        how = f"Gowin {pin['nano20k']['gowin_version']} recommended" if installs else "use 'fetch' (needs Gowin to build)"
        print(f"  {project:16s} {pin['ref']} {state}; build: {how}")
    flasher = "openFPGALoader" if tool("openFPGALoader") else (
        "Gowin programmer_cli" if any(i.programmer_cli for i in installs) else "none found")
    print(f"  flash tool       {flasher}")
    return 1 if missing_required else 0


# ============================================================================
# bootstrap
# ============================================================================

def cmd_bootstrap(args: argparse.Namespace) -> int:
    git = tool("git") or fail("git is required")
    wanted = {name.lower() for name in args.names}
    selected = [p for p in upstreams() if not wanted or p["name"].lower() in wanted
                or p["path"].split("/")[-1].lower() in wanted]
    if wanted and not selected:
        fail(f"no upstream matches {sorted(wanted)}; see UPSTREAMS.json")
    for entry in selected:
        target = REPO / entry["path"]
        ref, commit = entry.get("ref"), entry.get("commit")
        print(f"== {entry['name']} ({ref or 'default branch'}) -> {entry['path']}")
        if not target.exists():
            clone = [git, "clone", "--depth", "1", "--recurse-submodules", "--shallow-submodules"]
            clone += ["--branch", ref] if ref else []
            run(clone + [entry["url"], target])
        elif not (target / ".git").exists():
            fail(f"{target} exists but is not a git checkout")
        elif commit:
            run([git, "-C", target, "fetch", "--depth", "1", "origin", commit])
            run([git, "-C", target, "checkout", "--quiet", commit])
        else:
            run([git, "-C", target, "pull", "--ff-only"])
        run([git, "-C", target, "submodule", "update", "--init", "--recursive", "--depth", "1"])
        if commit:
            head = run([git, "-C", target, "rev-parse", "HEAD"]).stdout.strip()
            if head != commit:
                print(f"  warning: {entry['name']} is at {head[:12]}, UPSTREAMS.json pins {commit[:12]}")
    return 0


# ============================================================================
# test
# ============================================================================
# Each testbench prints "PASS: ..." and finishes with exit code 0, or calls
# $fatal. The Tang Nano 20K board test compiles the sources listed in the
# Gowin project file, so the simulation always matches the hardware build.

def _testbenches() -> List[tuple]:
    rtl = REPO / "rtl"
    board = read_gowin_project(LOCAL_DIR)
    return [
        ("rgb_lcd_timing", "rgb_lcd_timing_tb",
         [rtl / "video/rgb_lcd_timing.sv", rtl / "video/rgb_lcd_timing_tb.sv"]),
        ("gba_to_480x272_mapper", "gba_to_480x272_mapper_tb",
         [rtl / "video/gba_to_480x272_mapper.sv", rtl / "video/gba_to_480x272_mapper_tb.sv"]),
        ("gba_test_pattern", "gba_test_pattern_tb",
         [rtl / "video/gba_test_pattern.sv", rtl / "video/gba_test_pattern_tb.sv"]),
        ("gba_buttons", "gba_buttons_tb",
         [rtl / "input/button_debouncer.sv", rtl / "input/gba_buttons.sv", rtl / "input/gba_buttons_tb.sv"]),
        ("uart_tx", "uart_tx_tb", [rtl / "common/uart_tx.sv", rtl / "common/uart_tx_tb.sv"]),
        ("GB LCD UART loader", "gb_uart_loader_tb",
         [REPO / "tangnano20k/gbtang_lcd/src/gb_uart_loader.sv",
          REPO / "tangnano20k/gbtang_lcd/sim/gb_uart_loader_tb.sv"]),
        ("GB LCD video", "gb_lcd_video_tb",
         [rtl / "video/rgb_lcd_timing.sv",
          REPO / "tangnano20k/gbtang_lcd/src/gb_lcd_video.sv",
          REPO / "tangnano20k/gbtang_lcd/sim/gb_lcd_video_tb.sv"]),
        ("Studio memory bus", "studio_bus_tb",
         [REPO / "tangnano20k/studio_lcd/src/rv_fast_bus.sv",
          REPO / "tangnano20k/studio_lcd/src/rv_sdram_bus.sv",
          REPO / "tangnano20k/studio_lcd/sim/studio_bus_tb.sv"]),
        ("Studio LCD video", "studio_lcd_video_tb",
         [rtl / "video/rgb_lcd_timing.sv",
          REPO / "tangnano20k/studio_lcd/src/studio_lcd_video.sv",
          REPO / "tangnano20k/studio_lcd/sim/studio_lcd_video_tb.sv"]),
        ("Studio hardware renderer", "studio_renderer_tb",
         [REPO / "tangnano20k/studio_lcd/src/studio_renderer.sv",
          REPO / "tangnano20k/studio_lcd/sim/studio_renderer_tb.sv"]),
        ("gba_cart_rom_reader", "gba_cart_rom_reader_tb",
         [rtl / "cart/gba_cart_rom_reader.sv", rtl / "cart/gba_cart_rom_reader_tb.sv"]),
        ("tangnano20k gba_lcd_top", "gba_lcd_top_tb",
         board.verilog + [LOCAL_DIR / "sim/rpll_model.v", LOCAL_DIR / "sim/gba_lcd_top_tb.sv"]),
    ]


def _run_testbench(name: str, top: str, sources: List[Path], out_dir: Path) -> tuple:
    binary = out_dir / f"{top}.vvp"
    log = out_dir / f"{top}.log"
    ivl = Path(tool("iverilog")).resolve().parent.parent / "lib" / "ivl"
    compiler = [tool("iverilog")] + (["-B", str(ivl)] if IS_WINDOWS and ivl.is_dir() else [])
    runtime = [tool("vvp")] + (["-M-", "-M", str(ivl)] if IS_WINDOWS and ivl.is_dir() else [])
    compiled = subprocess.run(compiler + ["-g2012", "-Wall", "-s", top, "-o", str(binary)]
                              + [str(s) for s in sources], env=TOOL_ENV, capture_output=True, text=True)
    if compiled.returncode != 0:
        log.write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
        return False, "compile error (see " + str(log.relative_to(REPO)) + ")"
    ran = subprocess.run(runtime + ["-n", str(binary)], cwd=str(out_dir), env=TOOL_ENV,
                         capture_output=True, text=True)
    log.write_text(compiled.stderr + ran.stdout + ran.stderr, encoding="utf-8")
    passed = ran.returncode == 0 and "PASS:" in ran.stdout and "FAIL" not in ran.stdout
    summary = next((l for l in ran.stdout.splitlines() if l.startswith(("PASS:", "FAIL", "ERROR"))),
                   "no PASS line")
    return passed, summary


def _run_vhdl(out_dir: Path) -> tuple:
    ghdl = tool("ghdl")
    port = REPO / "ports/fpgba-tang60k"
    out_dir.mkdir(parents=True, exist_ok=True)
    steps = [["-a", "--std=08", port / "rtl/fpgba_platform_pkg.vhd"],
             ["-a", "--std=08", port / "rtl/fpgba_tang60k_platform.vhd"],
             ["-a", "--std=08", port / "sim/fpgba_tang60k_platform_tb.vhd"],
             ["-e", "--std=08", "fpgba_tang60k_platform_tb"],
             ["-r", "--std=08", "fpgba_tang60k_platform_tb", "--assert-level=error", "--stop-time=200ns"]]
    output = ""
    for step in steps:
        result = subprocess.run([ghdl] + [str(s) for s in step], cwd=str(out_dir), env=TOOL_ENV,
                                capture_output=True, text=True)
        output += result.stdout + result.stderr
        if result.returncode != 0:
            return False, output.strip().splitlines()[-1] if output.strip() else "ghdl failed"
    return True, "PASS: fpgba_tang60k_platform"


def cmd_test(args: argparse.Namespace) -> int:
    if not (tool("iverilog") and tool("vvp")):
        fail("Icarus Verilog (iverilog, vvp) is required: see docs/TOOLCHAIN.md")
    out_dir = BUILD / "tests"
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name, top, sources in _testbenches():
        passed, summary = _run_testbench(name, top, sources, out_dir)
        results.append((name, "pass" if passed else "FAIL", summary))
        print(f"  {'pass' if passed else 'FAIL'}  {name:26s} {summary}")

    if tool("ghdl"):
        passed, summary = _run_vhdl(BUILD / "ghdl")
        results.append(("fpgba_tang60k (VHDL)", "pass" if passed else "FAIL", summary))
        print(f"  {'pass' if passed else 'FAIL'}  {'fpgba_tang60k (VHDL)':26s} {summary}")
    else:
        state = "FAIL" if args.require_ghdl else "skip"
        results.append(("fpgba_tang60k (VHDL)", state, "ghdl not installed"))
        print(f"  {state}  {'fpgba_tang60k (VHDL)':26s} ghdl not installed")

    sys.path.insert(0, str(REPO))
    suite = unittest.TestLoader().discover(str(REPO / "tests"))
    report = io.StringIO()
    outcome = unittest.TextTestRunner(verbosity=1, stream=report).run(suite)
    py_ok = outcome.wasSuccessful()
    if not py_ok:
        print(report.getvalue())
    results.append(("python unit tests", "pass" if py_ok else "FAIL", f"{outcome.testsRun} tests"))
    print(f"  {'pass' if py_ok else 'FAIL'}  {'python unit tests':26s} {outcome.testsRun} tests")

    counts = {state: sum(1 for r in results if r[1] == state) for state in ("pass", "skip", "FAIL")}
    print(f"\n{counts['pass']} passed, {counts['skip']} skipped, {counts['FAIL']} failed"
          + (f"; logs in {out_dir.relative_to(REPO)}" if counts["FAIL"] else ""))
    return 1 if counts["FAIL"] else 0


# ============================================================================
# lint
# ============================================================================

RPLL_STUB = """`timescale 1ns/1ps
// Port-compatible rPLL stub so Verilator can lint the board top level.
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
module rPLL #(parameter FCLKIN = "100.0", parameter DYN_IDIV_SEL = "false", parameter IDIV_SEL = 0,
  parameter DYN_FBDIV_SEL = "false", parameter FBDIV_SEL = 0, parameter DYN_ODIV_SEL = "false",
  parameter ODIV_SEL = 8, parameter PSDA_SEL = "0000", parameter DYN_DA_EN = "false",
  parameter DUTYDA_SEL = "1000", parameter CLKOUT_FT_DIR = 1'b1, parameter CLKOUTP_FT_DIR = 1'b1,
  parameter CLKOUT_DLY_STEP = 0, parameter CLKOUTP_DLY_STEP = 0, parameter CLKFB_SEL = "internal",
  parameter CLKOUT_BYPASS = "false", parameter CLKOUTP_BYPASS = "false", parameter CLKOUTD_BYPASS = "false",
  parameter DYN_SDIV_SEL = 2, parameter CLKOUTD_SRC = "CLKOUT", parameter CLKOUTD3_SRC = "CLKOUT",
  parameter DEVICE = "GW2AR-18C") (
  output CLKOUT, output LOCK, output CLKOUTP, output CLKOUTD, output CLKOUTD3,
  input RESET, input RESET_P, input CLKIN, input CLKFB, input [5:0] FBDSEL, input [5:0] IDSEL,
  input [5:0] ODSEL, input [3:0] PSDA, input [3:0] DUTYDA, input [3:0] FDLY);
  assign CLKOUT = CLKIN; assign LOCK = 1'b1; assign CLKOUTP = CLKIN; assign CLKOUTD = 1'b0; assign CLKOUTD3 = 1'b0;
endmodule
"""


def cmd_lint(args: argparse.Namespace) -> int:
    verilator = tool("verilator") or fail("verilator not found (it ships with OSS CAD Suite)")
    rtl = REPO / "rtl"
    out_dir = BUILD / "lint"
    out_dir.mkdir(parents=True, exist_ok=True)
    stub = out_dir / "rpll_stub.v"
    stub.write_text(RPLL_STUB, encoding="utf-8")
    board = read_gowin_project(LOCAL_DIR)
    targets = [
        ("rgb_lcd_timing", [rtl / "video/rgb_lcd_timing.sv"]),
        ("gba_to_480x272_mapper", [rtl / "video/gba_to_480x272_mapper.sv"]),
        ("gba_test_pattern", [rtl / "video/gba_test_pattern.sv"]),
        ("gba_buttons", [rtl / "input/button_debouncer.sv", rtl / "input/gba_buttons.sv"]),
        ("uart_tx", [rtl / "common/uart_tx.sv"]),
        ("gba_cart_rom_reader", [rtl / "cart/gba_cart_rom_reader.sv"]),
        (board.top, [stub] + board.verilog),
    ]
    failures = 0
    for top, sources in targets:
        result = subprocess.run([verilator, "--lint-only", "-Wall", "-Wno-DECLFILENAME", "-Wno-WIDTHEXPAND", "--top-module", top]
                                + [str(s) for s in sources], env=TOOL_ENV, capture_output=True, text=True)
        messages = [l for l in (result.stdout + result.stderr).splitlines() if l.startswith("%")]
        ok = result.returncode == 0 and not messages
        failures += not ok
        print(f"  {'clean' if ok else 'ISSUES'}  {top}")
        for line in messages[:20]:
            print(f"      {line}")
    return 1 if failures else 0


# ============================================================================
# build
# ============================================================================

def _build_open(out_dir: Path) -> Path:
    """yosys -> nextpnr-himbaechel -> gowin_pack, sources taken from the .gprj."""
    for name in ("yosys", "nextpnr-himbaechel", "gowin_pack"):
        if not tool(name):
            fail(f"{name} not found; install OSS CAD Suite (docs/TOOLCHAIN.md) or use --flow gowin")
    proj = read_gowin_project(LOCAL_DIR)
    family = NEXTPNR_FAMILY.get(proj.device_name) or fail(f"no nextpnr family for {proj.device_name}")
    netlist, routed = out_dir / "synth.json", out_dir / "pnr.json"
    bitstream = out_dir / f"{proj.output_name}.fs"

    # The .sdc is written for Gowin (pin names from its netlist). nextpnr sees
    # yosys names and supports only create_clock, so it gets the "// nextpnr:" lines.
    sdc = out_dir / "nextpnr.sdc"
    clocks = [line.split("// nextpnr:", 1)[1].strip()
              for s in proj.sdc for line in s.read_text(encoding="utf-8").splitlines()
              if line.strip().startswith("// nextpnr:")]
    sdc.write_text("\n".join(clocks) + "\n", encoding="utf-8")

    sources = " ".join(f'"{p.as_posix()}"' for p in proj.verilog)
    run(["yosys", "-q", "-l", out_dir / "synth.log", "-p",
         f"read_verilog -sv {sources}; synth_gowin -top {proj.top} -json {netlist.as_posix()}"])
    run(["nextpnr-himbaechel", "--json", netlist, "--write", routed, "--device", proj.part,
         "--vopt", f"family={family}", "--vopt", f"cst={proj.cst[0]}", "--sdc", sdc,
         "--freq", "27", "--log", out_dir / "pnr.log"])
    run(["gowin_pack", "-d", family, "-o", bitstream, routed])

    # Report: resource use plus the post-route (last reported) Fmax of each clock.
    log = (out_dir / "pnr.log").read_text(encoding="utf-8", errors="replace").splitlines()
    usage = [l.replace("Info: ", "").strip() for l in log
             if re.search(r"\b(LUT4|DFF|ALU|MULT9X9|BSRAM|rPLL|IOB):\s", l)]
    fmax: Dict[str, str] = {}
    for line in log:
        match = re.search(r"Max frequency for clock\s+'([^']+)'", line)
        if match:
            fmax[match.group(1)] = line.replace("Info: ", "").strip()
    keep = usage + list(fmax.values())
    (out_dir / "report.txt").write_text("\n".join(keep) + "\n", encoding="utf-8")
    print("\n".join(f"    {l}" for l in keep))
    return bitstream


def _gowin_tcl_for_local(proj: GowinProject, out_dir: Path) -> Path:
    """gw_sh script equivalent to opening the .gprj in the IDE."""
    options = proj.options
    lines = [f"set_device {proj.part} -device_version {proj.device_name[-1]}"]
    lines += [f'add_file -type verilog "{p.as_posix()}"' for p in proj.verilog]
    lines += [f'add_file -type cst "{p.as_posix()}"' for p in proj.cst]
    lines += [f'add_file -type sdc "{p.as_posix()}"' for p in proj.sdc]
    lines += [f"set_option -top_module {proj.top}",
              f"set_option -output_base_name {proj.output_name}",
              "set_option -verilog_std sysv2017",
              f"set_option -use_mspi_as_gpio {int(bool(options.get('MSPI')))}",
              f"set_option -use_sspi_as_gpio {int(bool(options.get('SSPI')))}",
              "run all"]
    tcl = out_dir / "gowin_build.tcl"
    tcl.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return tcl


def _build_gowin(project: str, out_dir: Path, gowin_dir: Optional[str]) -> Path:
    if IS_MACOS:
        fail("Gowin EDA is not available for macOS. Use 'fetch' for gbtang/snestang, "
             "or the open-source flow for gba_lcd_480x272.")
    wanted = upstream(project)["nano20k"]["gowin_version"] if project in UPSTREAM_KEYS else None
    install = pick_gowin(gowin_dir, wanted) or fail(
        "Gowin EDA not found. Install it, then set GOWIN_HOME to the install folder "
        "(the one containing IDE/) or pass --gowin PATH.")
    print(f"  Gowin EDA {install.version} at {install.root}")
    if wanted and not install.version.startswith(wanted):
        print(f"  warning: upstream builds {project} with Gowin {wanted}; results may differ")

    if project in LOCAL_PROJECTS:
        proj = read_gowin_project(REPO / "tangnano20k" / project)
        work = out_dir / "gowin"
        work.mkdir(parents=True, exist_ok=True)
        tcl = _gowin_tcl_for_local(proj, work)
        run([install.gw_sh, tcl], cwd=work, log=out_dir / "gowin.log")
        produced = work / "impl" / "pnr" / f"{proj.output_name}.fs"
        target = out_dir / f"{proj.output_name}.fs"
    else:
        pin = upstream(project)
        meta = pin["nano20k"]
        checkout = REPO / pin["path"]
        if not (checkout / ".git").exists():
            fail(f"{pin['path']} missing: run 'python3 scripts/gbafpga.py bootstrap {project}'")
        run([install.gw_sh, meta["gowin_tcl"]] + meta["gowin_args"], cwd=checkout, log=out_dir / "gowin.log")
        produced = checkout / meta["gowin_output"]
        target = out_dir / meta["bitstream"]
    if not produced.is_file():
        fail(f"Gowin finished but {produced} was not produced; see {out_dir / 'gowin.log'}")
    shutil.copy2(produced, target)
    return target


def cmd_build(args: argparse.Namespace) -> int:
    out_dir = project_build_dir(args.project)
    out_dir.mkdir(parents=True, exist_ok=True)
    flow = args.flow
    if args.project != LOCAL_PROJECT:
        if flow == "open":
            fail(f"{args.project} builds only with Gowin EDA (use 'fetch' for the release bitstream)")
        flow = "gowin"
    elif flow == "auto":
        flow = "open" if all(tool(t) for t in ("yosys", "nextpnr-himbaechel", "gowin_pack")) else "gowin"
    print(f"== build {args.project} ({flow} flow)")
    bitstream = _build_open(out_dir) if flow == "open" else _build_gowin(args.project, out_dir, args.gowin)
    print(f"bitstream: {bitstream}")
    return 0


# ============================================================================
# fetch
# ============================================================================

def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _download(url: str, target: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "gba-fpga-helper"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response, target.open("wb") as out:
            shutil.copyfileobj(response, out)
    except urllib.error.URLError as exc:
        hint = (" On macOS with python.org Python, run 'Install Certificates.command'."
                if IS_MACOS and "CERTIFICATE" in str(exc).upper() else "")
        fail(f"download failed: {url}: {exc}.{hint}")


def cmd_fetch(args: argparse.Namespace) -> int:
    if args.project not in UPSTREAM_KEYS:
        fail(f"fetch is for {', '.join(sorted(UPSTREAM_KEYS))}; {LOCAL_PROJECT} is built from this repository")
    pin = upstream(args.project)
    release = pin["nano20k"]["release"]
    repo_url = pin["url"][:-4] if pin["url"].endswith(".git") else pin["url"]
    out_dir = project_build_dir(args.project) / "release"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"== fetch {args.project} {release['tag']} -> {out_dir}")
    for asset in release["assets"]:
        target = out_dir / asset["name"]
        if not target.is_file() or args.force:
            url = f"{repo_url}/releases/download/{release['tag']}/{asset['name']}"
            print(f"  downloading {url} ({asset['size']:,} bytes)")
            _download(url, target)
        size, digest = target.stat().st_size, _sha256(target)
        if size != asset["size"]:
            target.unlink()
            fail(f"{asset['name']}: {size} bytes, expected {asset['size']}; deleted, try again")
        if asset.get("sha256") and digest != asset["sha256"]:
            target.unlink()
            fail(f"{asset['name']}: SHA-256 mismatch; deleted")
        print(f"  ok  {asset['name']}  sha256 {digest}"
              + ("" if asset.get("sha256") else "  (upstream publishes no checksum; size verified)"))
        for member in asset.get("extract", []):
            with zipfile.ZipFile(target) as archive:
                match = next((n for n in archive.namelist() if n.split("/")[-1] == member), None)
                if match is None:
                    fail(f"{member} not found in {asset['name']}")
                (out_dir / member).write_bytes(archive.read(match))
                print(f"  extracted {member} from {match}")
    print(f"next: python3 scripts/gbafpga.py flash {args.project}")
    return 0


# ============================================================================
# flash
# ============================================================================

def _bitstream_candidates(project: str) -> List[Path]:
    """Every place a build route leaves the bitstream."""
    out_dir = project_build_dir(project)
    if project in LOCAL_PROJECTS:
        project_dir = REPO / "tangnano20k" / project
        name = read_gowin_project(project_dir).output_name + ".fs"
        return [out_dir / name,                               # gbafpga.py build (open or gowin flow)
                project_dir / "impl" / "pnr" / name]            # Gowin IDE: Run All on the .gprj
    pin = upstream(project)
    meta = pin["nano20k"]
    return [out_dir / meta["bitstream"],                                          # gbafpga.py build
            REPO / "tangnano20k" / project / "impl" / "pnr" / meta["bitstream"],  # Gowin IDE project here
            REPO / pin["path"] / meta["gowin_output"],                            # upstream scripts run by hand
            out_dir / "release" / meta["bitstream"]]                              # gbafpga.py fetch


def _firmware_candidates(project: str) -> List[Path]:
    if project in LOCAL_PROJECTS:
        return []
    pin = upstream(project)
    meta = pin["nano20k"]
    candidates = [project_build_dir(project) / "release" / meta["firmware"]]  # gbafpga.py fetch
    if meta.get("firmware_in_checkout"):                                       # shipped in the upstream tree
        candidates.append(REPO / pin["path"] / meta["firmware_in_checkout"])
    return candidates


def _newest(paths: List[Path]) -> Optional[Path]:
    existing = [p for p in paths if p.is_file()]
    return max(existing, key=lambda p: p.stat().st_mtime) if existing else None


def _not_found(what: str, searched: List[Path], hints: List[str]) -> "NoReturn":  # type: ignore[name-defined]
    lines = [f"no {what} found. Looked in:"] + [f"    {p}" for p in searched] + hints
    fail("\n".join(lines))


def cmd_flash(args: argparse.Namespace) -> int:
    # ---- Pick the files: explicit paths win, otherwise the newest from any route.
    if args.bitstream:
        bitstream = Path(args.bitstream)
        if not bitstream.is_file():
            fail(f"--bitstream {bitstream} does not exist")
    else:
        searched = _bitstream_candidates(args.project)
        bitstream = _newest(searched) or _not_found("bitstream", searched, [
            f"  Build it:  python3 scripts/gbafpga.py build {args.project}",
            "  or run Run All on the project's .gprj in the Gowin IDE",
            "  or pass --bitstream PATH" + ("" if args.project == LOCAL_PROJECT
                                            else f", or download it: python3 scripts/gbafpga.py fetch {args.project}")])

    firmware: Optional[Path] = None
    if args.project not in LOCAL_PROJECTS and not args.no_firmware:
        if args.firmware:
            firmware = Path(args.firmware)
            if not firmware.is_file():
                fail(f"--firmware {firmware} does not exist")
        else:
            searched = _firmware_candidates(args.project)
            firmware = _newest(searched) or _not_found("menu firmware (firmware.bin)", searched, [
                f"  Download it:  python3 scripts/gbafpga.py fetch {args.project}",
                "  or pass --firmware PATH, or --no-firmware if the board already has it"])
    offset = upstream(args.project)["nano20k"]["firmware_offset"] if firmware else None
    print(f"  bitstream: {bitstream}")
    if firmware:
        print(f"  firmware:  {firmware} -> {offset}")

    # ---- Build the programmer commands: firmware first, then the bitstream.
    flasher = args.tool
    if flasher == "auto":
        flasher = "openfpgaloader" if tool("openFPGALoader") else "gowin"
    print(f"== flash {args.project} via {flasher} ({'SRAM, lost at power-off' if args.sram else 'SPI flash'})")
    commands: List[list] = []
    if flasher == "openfpgaloader":
        loader = tool("openFPGALoader") or fail("openFPGALoader not found (run 'doctor'); or use --tool gowin")
        if firmware:
            commands.append([loader, "-b", BOARD, "--external-flash", "-o", offset, firmware])
        commands.append([loader, "-b", BOARD] + ([] if args.sram else ["-f"]) + [bitstream])
    else:
        install = pick_gowin(args.gowin, None)
        if not install or not install.programmer_cli:
            fail("no flash tool: install openFPGALoader, or Gowin EDA with its Programmer")
        base = [install.programmer_cli, "--device", "GW2AR-18C", "--cable-index", str(args.cable_index)]
        if firmware:
            commands.append(base + ["--run", "36", "--spiaddr", offset, "--fsFile", firmware])
        if args.sram:
            commands.append(base + ["--run", "2", "--fsFile", bitstream])
        else:
            commands.append(base + ["--run", "36", "--spiaddr", "0x000000", "--fsFile", bitstream])

    for command in commands:
        if args.dry_run:
            print("  would run: " + " ".join(str(c) for c in command))
        else:
            run(command)
    print("dry run, nothing written" if args.dry_run else "done")
    return 0


# ============================================================================
# ide-project: Gowin IDE project generated from an upstream build.tcl
# ============================================================================
# Upstream build.tcl is what the release bitstreams are built from; the IDE
# projects checked in upstream have drifted from it (stale files, different
# options). This evaluates build.tcl with Python's bundled Tcl, recording
# set_device/add_file/set_option instead of running Gowin, and writes a
# matching .gprj and impl/project_process_config.json.

TCL_OPTION_TO_CONFIG = {
    "top_module": ("TopModule", str),
    "output_base_name": ("OUTPUT_BASE_NAME", str),
    "use_mspi_as_gpio": ("MSPI", bool),
    "use_sspi_as_gpio": ("SSPI", bool),
    "use_ready_as_gpio": ("READY", bool),
    "use_done_as_gpio": ("DONE", bool),
    "use_i2c_as_gpio": ("I2C", bool),
    "use_cpu_as_gpio": ("CPU", bool),
    "use_jtag_as_gpio": ("JTAG", bool),
    "use_reconfign_as_gpio": ("RECONFIG_N", bool),
    "multi_boot": ("Multi_Boot", bool),
    "rw_check_on_ram": ("Ram_RW_Check", bool),
    "place_option": ("Place_Option", str),
    "route_option": ("Route_Option", str),
}
GPRJ_FILE_TYPES = {"verilog": "file.verilog", "cst": "file.cst", "sdc": "file.sdc"}


def evaluate_build_tcl(checkout: Path, script: str, args: List[str]) -> dict:
    try:
        import tkinter
    except ImportError:
        fail("this needs Python's tkinter/Tcl (Debian/Ubuntu: apt install python3-tk; "
             "Homebrew: brew install python-tk)")
    record = {"device": None, "device_version": None, "files": [], "options": {}}

    def set_device(*words):
        record["device"] = words[0]
        if "-device_version" in words:
            record["device_version"] = words[words.index("-device_version") + 1]

    def add_file(*words):
        words, ftype, enabled = list(words), None, True
        while words and words[0].startswith("-"):
            flag = words.pop(0)
            if flag == "-type":
                ftype = words.pop(0)
            elif flag == "-disable":
                enabled = False
        name = words[0]
        if ftype is None:
            ftype = {"cst": "cst", "sdc": "sdc"}.get(name.rsplit(".", 1)[-1], "verilog")
        record["files"].append((name, ftype, enabled))

    def set_option(*words):
        words = list(words)
        while words:
            key = words.pop(0).lstrip("-")
            record["options"][key] = words.pop(0) if words and not words[0].startswith("-") else "1"

    tcl = tkinter.Tcl()
    for name, handler in (("set_device", set_device), ("add_file", add_file),
                          ("set_option", set_option), ("run", lambda *a: None),
                          ("exit", lambda *a: None)):
        tcl.createcommand(name, handler)
    tcl.eval(f"cd {{{checkout.as_posix()}}}; set argv0 {script}; set argc {len(args)}; "
             f"set argv [list {' '.join(args)}]")
    tcl.eval(f"source {{{script}}}")
    return record


def cmd_ide_project(args: argparse.Namespace) -> int:
    pin = upstream(args.project)
    meta = pin["nano20k"]
    checkout = REPO / pin["path"]
    if not (checkout / meta["gowin_tcl"]).is_file():
        fail(f"{pin['path']} missing: run 'bootstrap {args.project}' first")
    record = evaluate_build_tcl(checkout, meta["gowin_tcl"], meta["gowin_args"])
    out_dir = REPO / "tangnano20k" / args.project
    relative = os.path.relpath(checkout, out_dir).replace(os.sep, "/")

    device = record["device"]
    device_name = {"GW2AR-LV18QN88C8/I7": "GW2AR-18C"}.get(device) or fail(f"unexpected device {device}")
    lines = ['<?xml version="1" encoding="UTF-8"?>', "<!DOCTYPE gowin-fpga-project>", "<Project>",
             "    <Template>FPGA</Template>", "    <Version>5</Version>",
             f'    <Device name="{device_name}" pn="{device}">gw2ar18c-000</Device>', "    <FileList>"]
    missing = []
    for name, ftype, enabled in record["files"]:
        if ftype not in GPRJ_FILE_TYPES or not enabled:
            continue                                    # .gao debug files and disabled entries
        if not (checkout / name).is_file():
            missing.append(name)
        lines.append(f'        <File path="{relative}/{name}" type="{GPRJ_FILE_TYPES[ftype]}" enable="1"/>')
    lines += ["    </FileList>", "</Project>"]
    if missing:
        fail(f"build.tcl lists files that do not exist: {missing}")

    config = json.loads((LOCAL_DIR / "impl" / "project_process_config.json").read_text(encoding="utf-8"))
    config.update({"Verilog_Standard": "Vlg_Std_Sysv2017", "Synthesize_tool": "GowinSyn"})
    unmapped = []
    for key, value in record["options"].items():
        if key in TCL_OPTION_TO_CONFIG:
            field, kind = TCL_OPTION_TO_CONFIG[key]
            config[field] = (value not in ("0", "false")) if kind is bool else value
        elif key not in ("synthesis_tool", "verilog_std"):
            unmapped.append(f"{key}={value}")

    name = config["OUTPUT_BASE_NAME"]
    (out_dir / "impl").mkdir(parents=True, exist_ok=True)
    (out_dir / f"{name}.gprj").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    (out_dir / "impl" / "project_process_config.json").write_text(
        json.dumps(config, indent=1, sort_keys=True, separators=(",", " : ")) + "\n",
        encoding="utf-8", newline="\n")
    print(f"wrote {out_dir / (name + '.gprj')} ({sum(1 for l in lines if '<File ' in l)} files)")
    if unmapped:
        print(f"  note: set these by hand in Project > Configuration if needed: {', '.join(unmapped)}")
    return 0


# ============================================================================
# Command line
# ============================================================================

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="gbafpga", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    doctor = commands.add_parser("doctor", help="list tools and capabilities")
    doctor.add_argument("--gowin", help="Gowin EDA install folder (contains IDE/)")
    doctor.set_defaults(func=cmd_doctor)

    bootstrap = commands.add_parser("bootstrap", help="clone pinned upstream projects into external/")
    bootstrap.add_argument("names", nargs="*", help="upstream names (default: all), e.g. gbtang snestang")
    bootstrap.set_defaults(func=cmd_bootstrap)

    test = commands.add_parser("test", help="run all testbenches and Python tests")
    test.add_argument("--require-ghdl", action="store_true", help="fail instead of skipping the VHDL test")
    test.set_defaults(func=cmd_test)

    lint = commands.add_parser("lint", help="Verilator lint of the synthesizable RTL")
    lint.set_defaults(func=cmd_lint)

    build = commands.add_parser("build", help="build a Tang Nano 20K bitstream")
    build.add_argument("project", choices=PROJECTS)
    build.add_argument("--flow", choices=["auto", "open", "gowin"], default="auto",
                       help="gba_lcd_480x272 only: open-source tools or Gowin EDA (default: open if installed)")
    build.add_argument("--gowin", help="Gowin EDA install folder (contains IDE/)")
    build.set_defaults(func=cmd_build)

    fetch = commands.add_parser("fetch", help="download the pinned release bitstream and firmware")
    fetch.add_argument("project", choices=sorted(UPSTREAM_KEYS))
    fetch.add_argument("--force", action="store_true", help="download again even if present")
    fetch.set_defaults(func=cmd_fetch)

    flash = commands.add_parser("flash", help="program the Tang Nano 20K")
    flash.add_argument("project", choices=PROJECTS)
    flash.add_argument("--sram", action="store_true", help="load into SRAM only (quick test, lost at power-off)")
    flash.add_argument("--bitstream", help="bitstream to use instead of the build/fetch output")
    flash.add_argument("--firmware", help="firmware.bin to write at 0x500000 (gbtang/snestang)")
    flash.add_argument("--no-firmware", action="store_true", help="skip the firmware write")
    flash.add_argument("--tool", choices=["auto", "openfpgaloader", "gowin"], default="auto")
    flash.add_argument("--gowin", help="Gowin EDA install folder, for --tool gowin")
    flash.add_argument("--cable-index", type=int, default=4,
                       help="Gowin programmer cable index (4 = Tang Nano 20K onboard debugger)")
    flash.add_argument("--dry-run", action="store_true",
                       help="show the files and programmer commands without writing anything")
    flash.set_defaults(func=cmd_flash)

    ide = commands.add_parser("ide-project",
                              help="regenerate tangnano20k/<core>/ Gowin IDE project from upstream build.tcl")
    ide.add_argument("project", choices=sorted(UPSTREAM_KEYS))
    ide.set_defaults(func=cmd_ide_project)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
