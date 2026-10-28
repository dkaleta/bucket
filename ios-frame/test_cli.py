"""Integration checks against the installed Apple frame; no app or network required."""
import pathlib
import subprocess
import tempfile
import unittest

CLI = pathlib.Path(__file__).resolve().with_name('ios-frame')


def magick(*args):
    return subprocess.check_output(['magick', *map(str, args)], text=True).strip()


class FrameTests(unittest.TestCase):
    def test_render_and_protect_inputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, output = root / 'input with spaces.png', root / 'output.png'
            magick('-size', '1206x2622', 'xc:#e23456', source)
            original = source.read_bytes()
            def call(*args):
                return subprocess.run([str(CLI), str(source), *map(str, args)], capture_output=True, text=True)
            result = call('-o', output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(magick('identify', '-format', '%wx%h', output), '1350x2760')
            # Screen center is faithfully copied; the device exterior is transparent.
            self.assertEqual(magick(output, '-depth', '8', '-format', '%[hex:p{675,1380}]', 'info:')[:6], 'E23456')
            self.assertEqual(magick(output, '-format', '%[fx:p{0,0}.a]', 'info:'), '0')
            self.assertEqual(magick(output, '-format', '%[fx:p{675,165}.a]', 'info:'), '1')
            self.assertNotEqual(call('-o', output).returncode, 0)
            self.assertNotEqual(call('-o', source, '--force').returncode, 0)
            white = root / 'white.png'
            self.assertEqual(call('-o', white, '--background', 'white', '--padding', 160).returncode, 0)
            self.assertEqual(magick('identify', '-format', '%wx%h', white), '1670x3080')
            self.assertEqual(magick(white, '-depth', '8', '-format', '%[hex:p{0,0}]', 'info:')[:6], 'FFFFFF')
            self.assertEqual(source.read_bytes(), original)
            self.assertEqual(call('-o', output, '--force').returncode, 0)
            magick('-size', '600x600', 'xc:red', source)
            self.assertNotEqual(call('-o', root / 'bad.png').returncode, 0)
            self.assertFalse((root / 'bad.png').exists())
            magick('-size', '603x1311', 'xc:blue', source)
            self.assertEqual(call('-o', root / 'scaled.png').returncode, 0)


if __name__ == '__main__':
    unittest.main()
