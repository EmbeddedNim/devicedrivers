import unittest except check
import strutils
import bitops
import print

import mcu_utils/basics

include devicedrivers/adcs/ads131


suite "bit ops":

  setup:
    var regCfg1: RegConfig1
    var regChSet1: RegChSet

  test "dr64k":
    regCfg1.dataRate = Dr64k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    unittest.check dr == Dr64k

  test "dr1k":
    regCfg1.dataRate = Dr1k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    unittest.check dr == Dr1k

  test "dr2k":
    regCfg1.dataRate = Dr2k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    unittest.check dr == Dr2k

  test "ch set":
    regChSet1.gain = ChGain.X2
    print $regChSet1
    let gn = regChSet1.gain
    print gn
    unittest.check gn == ChGain.X2

  test "ch set x16":
    regChSet1.gain = ChGain.X12
    print $regChSet1
    print regChSet1.uint8.toHex()
    let gn = regChSet1.gain
    print gn
    unittest.check gn == ChGain.X12
    unittest.check regChSet1.uint8 == 0x60
