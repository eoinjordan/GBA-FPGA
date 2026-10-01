import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import gbafpga
from studio_game import find_game


class StudioGameTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.game = self.folder / 'game.tang.bin'
        self.game.write_bytes(b'\x01\x02\x03\x04')
        (self.folder / 'build.json').write_text(json.dumps({
            'target': 'tangnano20k-rv32im', 'sha256': hashlib.sha256(self.game.read_bytes()).hexdigest()}))

    def test_folder_and_manifest(self):
        self.assertEqual(find_game(self.folder), self.game)
        self.game.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'manifest'): find_game(self.folder)

    def test_ambiguous_games_and_arm_rom_rejected(self):
        (self.folder / 'other.tang.bin').write_bytes(b'abcd')
        with self.assertRaisesRegex(ValueError, 'exactly one'): find_game(self.folder)
        with self.assertRaisesRegex(ValueError, 'ARM'): find_game(self.folder / 'game.gba')

    def test_invalid_game_never_invokes_programmer(self):
        self.game.write_bytes(b'bad')
        with patch.object(gbafpga, 'run') as run:
            with self.assertRaises(SystemExit):
                gbafpga.main(['flash', 'studio_lcd', '--game', str(self.folder), '--port', 'COM5'])
            run.assert_not_called()

    def test_dry_run_includes_loader_after_programmer(self):
        (self.folder / 'platform.fs').write_bytes(b'bitstream')
        with patch.object(gbafpga, 'tool', return_value='/tools/openFPGALoader'), patch('builtins.print') as output:
            gbafpga.main(['flash', 'studio_lcd', '--game', str(self.folder), '--port', 'COM5',
                         '--bitstream', str(self.folder / 'platform.fs'), '--dry-run'])
        lines = '\n'.join(str(call.args[0]) for call in output.call_args_list)
        self.assertLess(lines.index('would run:'), lines.index('would load game:'))


if __name__ == '__main__': unittest.main()
