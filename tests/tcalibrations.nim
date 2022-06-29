import unittest except check
import strutils
import bitops
import print
import typetraits
import std/[bitops, strutils]

import mcu_utils/basics
import mcu_utils/basictypes

import devicedrivers/adcs/adcutils
import devicedrivers/adcs/calibrations


suite "calibrations ":

  test "test convert":
    var calibs: Calibs[3, OneFactorConv, Volts]
    calibs[0].calFactor = 1.0e-1
    calibs[1].calFactor = 1.0e-2
    calibs[2].calFactor = 1.0e-3

    var reading: AdcReading[3, Bits24]
    reading.count = 4
    reading[0] = 100.Bits24
    reading[1] = 200.Bits24
    reading[2] = 300.Bits24

    let vreading = calibs.convert(reading)
    echo "vreading: ", repr(vreading)
    unittest.check abs(vreading[0].float32 - 100 * 1.0e-1) <= 1.0e-5
    unittest.check abs(vreading[1].float32 - 200 * 1.0e-2) <= 1.0e-5
    unittest.check abs(vreading[2].float32 - 300 * 1.0e-3) <= 1.0e-5

  test "test multi convs":
    var voltCals: Calibs[2, OneFactorConv, Volts]
    voltCals[0].calFactor = 1.0e-1
    voltCals[1].calFactor = 1.0e-2

    var currCals: Calibs[2, TwoFactorConv, Volts]
    currCals[0] = TwoFactorConv(calFactor: 1.0e-3, calOffset: -0.004)
    currCals[1] = TwoFactorConv(calFactor: 1.0e-3, calOffset: -0.004)

    var reading: AdcReading[2, Bits24]
    reading[0] = 100.Bits24
    reading[1] = 200.Bits24

    let
      vreading = voltCals.convert(reading)
      areading = currCals.convert(vreading)

    echo "vreading: ", $(vreading)
    echo "areading: ", $(areading)

    unittest.check vreading[0].float32 ~= 10.0
    unittest.check vreading[1].float32 ~= 2.0

    unittest.check areading[0].float32 ~= 100 * 1.0e-1
    unittest.check areading[1].float32 ~= 200 * 1.0e-2

  test "test toVolts":
    var calib = initVoltsCalib[4](
      vref = 4.Volts,
      bits = 24,
      bipolar = true,
      gains = [1.0'f32, 1.0, 1.0, 1.0]
    )

    var reading: AdcReading[4, Bits24]
    reading.count = 4
    reading[0] = 100.Bits24
    reading[1] = 500.Bits24
    reading[2].setSigned = 0x7FFFFF # ads131 max FS 24-bit code
    reading[3].setSigned = 0x800000 # ads131 min FS 24-bit code

    echo "reading: ", repr(reading)

    let vreading: AdcReading[4, Volts] = calib.convert(reading)
    echo "vreading: ", repr(vreading)
    unittest.check vreading[0].float32 ~= 0.0000476837158203125'f32
    unittest.check vreading[1].float32 ~= 0.0002384185791015625'f32
    unittest.check vreading[2].float32 ~= 4.0'f32
    unittest.check vreading[3].float32 ~= -4.0'f32
