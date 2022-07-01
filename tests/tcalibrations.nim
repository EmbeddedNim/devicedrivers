import unittest except check
import strutils
import bitops
import print
import typetraits
import std/[bitops, strutils, strformat]

import mcu_utils/basics
import mcu_utils/basictypes

import devicedrivers/adcs/adcutils
import devicedrivers/adcs/calibrations


suite "calibrations ":

  test "test basic convert":
    var calibs: ChannelsCalibs[3, Volts]
    calibs[0] = ScaleConv(f = 1.0e-1)
    calibs[1] = ScaleConv(f = 1.0e-2)
    calibs[2] = ScaleConv(f = 1.0e-3)

    var reading: AdcReading[3, Bits24]
    reading.count = 4
    reading[0] = 100.Bits24
    reading[1] = 200.Bits24
    reading[2] = 300.Bits24

    let vreading = calibs.convert(reading)
    echo "vreading: ", $(vreading)
    unittest.check abs(vreading[0].float32 - 100 * 1.0e-1) <= 1.0e-5
    unittest.check abs(vreading[1].float32 - 200 * 1.0e-2) <= 1.0e-5
    unittest.check abs(vreading[2].float32 - 300 * 1.0e-3) <= 1.0e-5

  test "test multi convs":
    var vcalib = initAdcVoltsCalib[2](
      vref = 4.Volts,
      bits = 24,
      bipolar = true,
      gains = [1.0'f32, 1.0]
    )

    let acalib = initCurrentSenseCalib(
      resistors = [110.0'f32, 110.0'f32]
    )

    var reading: AdcReading[2, Bits24]
    reading[0] = 4_610_000.Bits24
    reading[1] = 923_000.Bits24

    let
      vreading = vcalib.convert(reading)
      areading = acalib.convert(vreading)

    echo "vreading: ", $(vreading)
    echo "areading: ", $(areading)

    assertNear vreading[0], 2.1982195613.Volts
    assertNear vreading[1], 0.4401207494.Volts

    assertNear areading[0], 20.0e-3.Amps, 1.0e-4
    assertNear areading[1], 4.0e-3.Amps, 1.0e-4

  test "test toVolts":
    var calib = initAdcVoltsCalib[4](
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

    echo "reading: ", $(reading)

    let vreading: AdcReading[4, Volts] = calib.convert(reading)
    echo "vreading: ", $(vreading)
    unittest.check vreading[0].float32 ~= 0.0000476837158203125'f32
    unittest.check vreading[1].float32 ~= 0.0002384185791015625'f32
    unittest.check vreading[2].float32 ~= 4.0'f32
    unittest.check vreading[3].float32 ~= -4.0'f32

  test "test basic calib convert":
    let vcalib = AdcVoltsCalib.init(vref=4.Volts,
                                    bits=24,
                                    bipolar=true,
                                    gain = 2.0.Gain)

    # TODO: get this to work?
    var reading: Volts

    reading = vcalib.convert(Bits24.signed(0x7FFFFF))
    assertNear reading, 2.0.Volts
    reading = vcalib.convert(Bits24.signed(0x800000))
    assertNear reading, -2.0.Volts

  test "test calib convert":
    let vcalib = AdcVoltsCalib.init(vref=4.Volts,
                                    bits=24,
                                    bipolar=true,
                                    gain = 2.0.Gain)
    let mAcalib = CurrentSenseCalib.init(resistor = 110.Ohms) 

    # TODO: get this to work?
    let mAReadingCalib: ReadingCalib[Amps] = reduce(vcalib, mAcalib)
    echo fmt"mAReadingCalib : {mAReadingCalib.repr()=}"
    echo fmt"mAReadingCalib : {$typeof(mAReadingCalib )=}"

    var reading: Amps

    reading = mAReadingCalib.convert(0x7FFFFF.Bits24)
    echo fmt"reading : {repr reading=}"


  # test "test generic kinds":

  #   var calib = initGenericReadingCalibs[3](
  #     conversions = [
  #       GenericConv(kind: OneFactor, onefact: OneFactorConv(calFactor: 3.14)),
  #       GenericConv(kind: OneFactor, onefact: OneFactorConv(calFactor: 3.14)),
  #       GenericConv(kind: OneFactor, onefact: OneFactorConv(calFactor: 3.14)),
  #     ]
  #   )
