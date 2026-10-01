"""Find and validate native Studio firmware before programming hardware."""
import hashlib
import json
from pathlib import Path


def find_game(path):
    path = Path(path).resolve()
    if path.is_dir():
        matches = sorted(path.glob('*.tang.bin'))
        if len(matches) != 1:
            raise ValueError('Put exactly one *.tang.bin and its build.json in ' + str(path))
        path = matches[0]
    if not path.name.endswith('.tang.bin'):
        raise ValueError('Use a native game.tang.bin exported from Studio; ARM .gba ROMs cannot run on studio_lcd')
    try:
        payload = path.read_bytes()
        manifest = json.loads(path.with_name('build.json').read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise ValueError('Missing or invalid firmware/build.json: ' + str(error)) from error
    if not 4 <= len(payload) <= 1048576:
        raise ValueError('Native game must be 4 bytes to 1 MiB')
    if manifest.get('target') != 'tangnano20k-rv32im' or manifest.get('sha256') != hashlib.sha256(payload).hexdigest():
        raise ValueError('Firmware does not match a Tang RV32IM build.json manifest')
    return path
