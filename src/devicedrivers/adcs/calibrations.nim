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
  Converter* = object of RootObj

  OneFactorConv* = object
    # per channel config for a calibration setup
    calFactor*: float32

  TwoFactorConv* = object
    # per channel config for a calibration setup
    calFactor*: float32
    calOffset*: float32


proc convert*[T, V](res: var V, val: T, ch: OneFactorConv) =
  # convert to volts
  res = V(val.float32 * ch.calFactor)

proc convert*[T, V](res: var V, val: T, ch: TwoFactorConv) =
  # convert to volts
  res = V(val.float32 * ch.calFactor + ch.calOffset)


# AdcReading Single Type Calibration
# ~~~~~~~~~~~~~~~~~~~~~~
# 
type
  Calibs*[N: static[int], G, V] = array[N, G]

proc convert*[N: static[int], T, G, V](
    calibration: Calibs[N, G, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  # Creates a new AdcReading with channels converted using the calibration. 
  # 
  runnableExamples:
    var calibration: Calibs[1, OneFactorConv, Volts]
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
  VoltsConv* = object
  VoltsCalib*[N: static[int]] = Calibs[N, OneFactorConv, Volts]

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
    result[i].calFactor = factor / gains[i]


# AdcReading Current Calibration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# helpers for AdcReading's 
#

type
  CurrentSenseCalib*[N: static[int]] = Calibs[N, OneFactorConv, Amps]

    # an Adc-to-Volts calibration for an AdcReading of N channels

proc initCurrentSenseCalib*[N: static[int]](
    resistors: array[N, float32],
): CurrentSenseCalib[N] =
  ## properly create a volts calibration
  for i in 0 ..< N:
    result[i].calFactor = 1.0'f32 / resistors[i]


# Voltage to End Units conversion
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# takes volts and converts them on different transfer functions
#

type

  ReadingKind* = distinct uint16

  SomeReading* = object
    val*: float32
    unit*: ReadingKind

  ClosureConverter = proc (val: float32): float32 {.closure.}

type
  ConverterKinds* {.pure.} = enum
    OneFactor
    TwoFactor
    PolyThreeFactor
    ClosureConv

  GenericConv* = object
    case kind*: ConverterKinds
    of OneFactor:
      onefact*: OneFactorConv
    of TwoFactor:
      twofact*: TwoFactorConv
    of PolyThreeFactor:
      threefact*: TwoFactorConv
    of ClosureConv:
      fnconv*: ClosureConverter

  GenericUnitsCalib*[N: static[int]] = Calibs[N, GenericConv, SomeReading]


proc initGenericReadingCalibs*[N: static[int]](
  conversions: array[N, GenericConv]
): GenericUnitsCalib[N] =
  ## properly create a volts calibration
  for i in 0 ..< N:
    result[i] = conversions[i]

type
  ResistorDividerConv* = distinct TwoFactorConv

# proc convert*[T, V](res: var V, val: T, ch: OneFactorConv) =
#   # convert to volts
#   res = V(val.float32 * ch.calFactor)
