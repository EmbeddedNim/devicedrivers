import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging
import adcutils


# Voltage to End Units conversion
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# takes volts and converts them on different transfer functions
#

type

  UnitKind* = distinct uint16

  UnitsCalib*[N: static[int]] = Calib[N, Volts] #\
    # an Adc-to-Volts calibration for an AdcReading of N channels

proc initUnitsCalib*[N: static[int]](
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gains: array[N, float32]
): VoltsCalib[N] =
  ## properly create a volts calibration
  result.vref = vref
  result.bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  result.factor = vref.float32 / result.bitspace.float32
  for i in 0 ..< N:
    result.channels[i].calFactor = result.factor / gains[i]

proc toVolts*[V: Volts, N, T](
    calib: Calib[N, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  # returns a new AdcReading converted to volts. The reading type is `Volts`
  # which are a float32.
  result.ts = reading.ts
  result.count = reading.count
  for i in 0 ..< reading.count:
    result.channels[i] = reading.convert(calib, i)

