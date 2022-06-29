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
    var calib = initAdcVoltsCalib[4](
      vref = 4.Volts,
      bits = 24,
      bipolar = true,
      gains = [1.0'f32, 1.0, 1.0, 1.0]
    )

    var reading: AdcReading[4, Bits24]
    reading.count = 4
    reading.channels[0] = 100.Bits24
    reading.channels[1] = 500.Bits24
    reading.channels[2].setSigned = 0x7FFFFF # ads131 max FS 24-bit code
    reading.channels[3].setSigned = 0x800000 # ads131 min FS 24-bit code

    echo "reading: ", repr(reading)

    let vreading: AdcReading[4, Volts] = calib.convert(reading)
    echo "vreading: ", repr(vreading)
    echo "vreading:float32:", $(vreading[0].float32)
    unittest.check abs(vreading[0].float32 - 0.0000476837158203125'f32) <= 1.0e-5
    unittest.check abs(vreading[1].float32 - 0.0002384185791015625'f32) <= 1.0e-5
    unittest.check abs(vreading[2].float32 - 4.0'f32) <= 1.0e-5
    unittest.check abs(vreading[3].float32 - -4.0'f32) <= 1.0e-5
