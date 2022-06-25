import unittest except check
import strutils
import bitops
import print

import mcu_utils/basics

include devicedrivers/adcs/ads131


suite "bit ops":

  setup:
    var regCfg1: RegConfig1

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
