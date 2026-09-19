from panda import Panda
from panda.python.usb import PandaUsbHandle


class FakeUsbHandle:
  def __init__(self, response: bytes):
    self.response = response

  def controlRead(self, *args):
    return self.response


def get_type(response: bytes, bcd_hw_type: bytes | None, bootstub: bool = True):
  panda = Panda.__new__(Panda)
  panda._handle = PandaUsbHandle(FakeUsbHandle(response), bcd_hw_type)
  panda.bootstub = bootstub
  return panda.get_type()


def test_old_h7_bootstub_uses_usb_descriptor_type():
  old_bootstub_response = bytes.fromhex("ff00c13edeadd00d80ea0208")
  assert get_type(old_bootstub_response, Panda.HW_TYPE_RED_PANDA) == Panda.HW_TYPE_RED_PANDA


def test_old_bootstub_does_not_restore_unsupported_hardware():
  old_bootstub_response = bytes.fromhex("ff00c13edeadd00d80ea0208")
  assert get_type(old_bootstub_response, b'\x03') == old_bootstub_response


def test_hardware_type_endpoint_takes_precedence():
  assert get_type(Panda.HW_TYPE_TRES, Panda.HW_TYPE_RED_PANDA) == Panda.HW_TYPE_TRES


def test_application_response_does_not_use_bootstub_fallback():
  response = bytes.fromhex("ff00c13edeadd00d80ea0208")
  assert get_type(response, Panda.HW_TYPE_RED_PANDA, bootstub=False) == response
