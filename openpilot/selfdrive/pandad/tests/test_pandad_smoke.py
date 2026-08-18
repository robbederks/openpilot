import threading
import unittest
from unittest.mock import MagicMock, patch

from openpilot.selfdrive.pandad import pandad
from openpilot.common.hardware import HARDWARE


class TestPandadSmoke(unittest.TestCase):
  def test_pandad_hardware_methods_exist(self):
    """Verify every HARDWARE.* call in pandad.py resolves to a real method.

    This catches rebase conflicts where upstream removes a method that the
    multipanda pandad wrapper still calls (e.g. has_internal_panda was
    removed in upstream #38201 but pandad still calls it).
    """
    import inspect
    import re

    src = inspect.getsource(pandad)
    methods = set(re.findall(r'HARDWARE\.(\w+)', src))
    self.assertTrue(methods, "no HARDWARE calls found in pandad.py")

    missing = [m for m in sorted(methods) if not callable(getattr(HARDWARE, m, None))]
    self.assertFalse(missing, f"HARDWARE is missing methods called in pandad.py: {missing}")

  def test_pandad_multipanda_smoke(self):
    """Exercise the multipanda code path with a mocked panda.

    Mocks a panda being connected and runs pandad.main(). If any HARDWARE
    method called in the multipanda code path is missing, the AttributeError
    is caught by pandad's ``except Exception`` clause and main() loops
    forever (test times out). If all methods exist, main() reaches
    subprocess.Popen (mocked to raise SystemExit, which is NOT caught by
    ``except Exception``) and exits cleanly.
    """
    fake_panda = MagicMock()
    fake_panda.is_internal.return_value = True
    fake_panda.get_type.return_value = 0
    fake_panda.health.return_value = {"heartbeat_lost": False}
    fake_panda.bootstub = False

    with patch.object(pandad, 'Panda') as mock_panda_class, \
         patch.object(pandad, 'PandaDFU') as mock_dfu, \
         patch.object(pandad, 'flash_panda'), \
         patch('signal.signal'), \
         patch.object(pandad.subprocess, 'Popen', side_effect=SystemExit):
      mock_panda_class.list.return_value = ["fake_serial"]
      mock_panda_class.return_value.__enter__.return_value = fake_panda
      mock_dfu.list.return_value = []

      result: dict = {}

      def run_main():
        try:
          pandad.main()
        except SystemExit:
          result['exited'] = True
        except BaseException as e:
          result['error'] = e

      t = threading.Thread(target=run_main, daemon=True)
      t.start()
      t.join(timeout=5)

      if t.is_alive():
        self.fail(
          "pandad.main() is stuck in a loop — a HARDWARE method is likely "
          "missing (AttributeError swallowed by except Exception)"
        )

      self.assertTrue(result.get('exited', False),
                      f"pandad.main() exited unexpectedly: {result.get('error')}")


if __name__ == '__main__':
  unittest.main()
