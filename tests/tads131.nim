import unittest except check
import strutils
import bitops
import print
import typetraits

import mcu_utils/basics
import mcu_utils/basictypes

include devicedrivers/adcs/ads131


suite "bit ops":

  setup:
    var regCfg1 {.used.}: RegConfig1
    var regChSet1 {.used.}: RegChSet

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

  test "test toVolts":
    var calib = initVoltsCalib[4](
      vref = 4.Volts,
      gains = [2.0'f32, 2.0, 2.0, 2.0]
    )

    var reading: AdcReading[4, Bits24]
    reading.channels[0] = 100.Bits24
    reading.channels[1] = 500.Bits24
    reading.channels[2] = 0.Bits24
    reading.channels[3] = -100.Bits24

    echo "reading: ", repr(reading)

    let vreading = reading.toVolts(calib)
    echo "vreading: ", repr(vreading)
