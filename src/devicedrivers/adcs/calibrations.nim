import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging
import adcutils
import patty

import math
import adcutils

# Calibration Utils
# ~~~~~~~~~~~~~~~~~
# 
# this section is the initial *volts calibration* for an adc
#
# Generic Type Name Conventions:
# - `N` number of channels (must be static[int] for compile time)
# - `T` actual reading type and implies incoming type
# - `V` actual reading type but implies outgoing type
# - `G` calibration factors array


# Calibration Basics
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
type
  ScaleConv* = object
    # per channel config for a calibration setup
    scale*: float32

  LinearConv* = object
    # per channel config for a calibration setup
    slope*: float32
    offset*: float32

  Poly3Conv* = object
    # per channel config for a calibration setup
    a0*: float32
    a1*: float32
    a2*: float32


proc convert*[T, V](res: var V, val: T, ch: ScaleConv) =
  # convert to volts
  res = V(val.float32 * ch.scale)

proc convert*[T, V](res: var V, val: T, ch: LinearConv) =
  # convert to volts
  res = V(val.float32 * ch.scale + ch.offset)

proc convert*[T, V](res: var V, val: T, ch: Poly3Conv) =
  # convert to volts
  let v = val.float32
  res = V(ch.a0 + ch.a1*v^1 + ch.a2*v^2)


# AdcReading Single Type Calibration
# ~~~~~~~~~~~~~~~~~~~~~~
# 
type
  Calibs*[N: static[int], G, V] = array[N, G]

  CalibTuple*[N: static[int], G: tuple] = G

proc convert*[N: static[int], T, G, V](
    calibration: Calibs[N, G, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  # Creates a new AdcReading with channels converted using the calibration. 
  # 
  runnableExamples:
    var calibration: Calibs[1, ScaleConv, Volts]
    calibration[0].calFactor = 1.0e-1

    var reading: AdcReading[1, Bits24]
    reading[0] = 100.Bits24

    let vreading = calibs.convert(reading)
    echo "vreading: ", repr(vreading)
    assert abs(10'f32 - vreading[0].float32) <= 1.0e-5

  result.ts = reading.ts
  result.count = reading.count
  for i in 0 ..< N:
    result[i].convert(reading[i], calibration[i])

proc convert*[N: static[int], T, G, V](
    calibration: CalibTuple[N, G],
    reading: AdcReadingTuple[G],
): AdcReading[N, V] =
  # Creates a new AdcReading with channels converted using the calibration. 
  # 

  runnableExamples:
    var calibration: Calibs[1, ScaleConv, Volts]
    calibration[0].calFactor = 1.0e-1

    var reading: AdcReading[1, Bits24]
    reading[0] = 100.Bits24

    let vreading = calibs.convert(reading)
    echo "vreading: ", repr(vreading)
    assert abs(10'f32 - vreading[0].float32) <= 1.0e-5

  result.ts = reading.ts
  result.count = reading.count
  for i in 0 ..< N:
    result[i].convert(reading[i], calibration[i])

proc transpose*[N, T, G1, G2, V](
    a: Calibs[N, G1, T],
    b: Calibs[N, G2, V],
    idx: int
): Calibs[N, G2, V] =
  # combine calibs??
  discard

# AdcReading Voltage Calibration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# helpers for AdcReading's 
#

type
  AdcVoltsConv* = ScaleConv

  VoltsCalib*[N: static[int]] = Calibs[N, AdcVoltsConv, Volts]

    # an Adc-to-Volts calibration for an AdcReading of N channels

proc initAdcVoltsCalib*[N: static[int]](
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gains: array[N, float32],
): VoltsCalib[N] =
  ## properly create a volts calibration
  let bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  let factor = vref.float32 / bitspace.float32
  for i in 0 ..< N:
    result[i].scale = factor / gains[i]


# AdcReading Current Calibration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# helpers for AdcReading's 
#

type
  CurrentSenseCalib*[N: static[int]] = Calibs[N, ScaleConv, Amps]

    # an Adc-to-Volts calibration for an AdcReading of N channels

proc initCurrentSenseCalib*[N: static[int]](
    resistors: array[N, float32],
): CurrentSenseCalib[N] =
  ## properly create a volts calibration
  for i in 0 ..< N:
    result[i].scale = 1.0'f32 / resistors[i]


# Voltage to End Units conversion
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# takes volts and converts them on different transfer functions
#

type

  ReadingKind* = distinct uint16

  SomeReading* = object
    unit*: ReadingKind
    val*: float32


type
  ConverterKinds* {.pure.} = enum
    Scale
    Linear
    Poly3

  GenericConv* = object
    case kind*: ConverterKinds
    of Scale:
      onefact*: ScaleConv
    of Linear:
      twofact*: LinearConv
    of Poly3:
      threefact*: Poly3Conv

  GenericUnitsCalib*[N: static[int]] = Calibs[N, GenericConv, SomeReading]


proc initGenericReadingCalibs*[N: static[int]](
  conversions: array[N, GenericConv]
): GenericUnitsCalib[N] =
  ## properly create a volts calibration
  for i in 0 ..< N:
    result[i] = conversions[i]

type
  ResistorDividerConv* = distinct ScaleConv

# proc convert*[T, V](res: var V, val: T, ch: ScaleConv) =
#   # convert to volts
#   res = V(val.float32 * ch.calFactor)
