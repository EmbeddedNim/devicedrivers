## ======================
## Adc Calibration Module
## ======================
## 
## The calibration module implements a system for calibrating readings
## taken from an ADC. 
## 
## TODO - WIP api is unstable
## 
## Configuration
## -------------
## TODO - once API is stabalized
## 
## 
## Calibration Utils
## ~~~~~~~~~~~~~~~~~
## 
## this section is the initial *volts calibration* for an adc
##
## Generic Type Name Conventions:
## - `N` number of channels (must be static[int] for compile time)
## - `T` actual reading type and implies incoming type
## - `V` actual reading type but implies outgoing type
## - `G` calibration factors array
## 

import std/[math, algorithm]

import patty

import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging

import adcutils


## Calibration Basics
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type

  ReadingKind* = distinct uint16

  SomeReading* = object
    unit*: ReadingKind
    val*: float32


variant Conversion:
  # creates a Nim variant types
  # Note: uses `patty` library to simplify variant types
  ScaleConv(scale: float32)
  LinearConv(slope: float32, offset: float32)
  Poly3Conv(a0, a1, a2: float32)
  LookupLowerBoundConv(keys: seq[float32], values: seq[float32])


proc convert*[T, V](res: var V, val: T, conv: Conversion) =
  let x = val.float32
  match conv:
    ScaleConv(scale: scale):
      res = V(scale * x)
    LinearConv(slope: a, offset: b):
      res = V(a * x + b)
    Poly3Conv(a0: a0, a1: a1, a2: a2):
      res = V(a0 + a1*x^1 + a2*x^2)
    LookupLowerBoundConv(keys: keys, values: values):
      let idx = keys.lowerBound(x)
      res = V(values[idx])


## AdcReading Single Type Calibration
## ~~~~~~~~~~~~~~~~~~~~~~
## 
type
  Calibs*[N: static[int], G, V] = array[N, G]

proc convert*[N: static[int], T, G, V](
    calibration: Calibs[N, G, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  ## Creates a new AdcReading with channels converted using the calibration. 
  ## 
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

## AdcReading Voltage Calibration
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## 
## helpers for AdcReading's 
##

type
  VoltsConv* = object
  VoltsCalib*[N: static[int]] = Calibs[N, ScaleConv, Volts]


proc initAdcVoltsCalib*[N: static[int]](
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gains: array[N, float32],
): VoltsCalib[N] =
  ## initalize a calibration for adc-bits to voltage conversion
  let bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  let factor = vref.float32 / bitspace.float32
  for i in 0 ..< N:
    result[i].scale = factor / gains[i]


## AdcReading Current Calibration
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## 
## helpers for AdcReading's 
##

type
  CurrentSenseCalib*[N: static[int]] = Calibs[N, ScaleConv, Amps]


proc initCurrentSenseCalib*[N: static[int]](
    resistors: array[N, float32],
): CurrentSenseCalib[N] =
  ## initialize calibration for a shunt resistor based current sensor
  for i in 0 ..< N:
    result[i].scale = 1.0'f32 / resistors[i]


## Experimental Configurable Calibrations
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## 
## WIP
##


type
  ConverterKinds* {.pure.} = enum
    Scale
    Linear
    Poly3
    Lookup

  GenericConv* = object
    case kind*: ConverterKinds
    of Scale:
      onefact*: ScaleConv
    of Linear:
      twofact*: LinearConv
    of Poly3:
      threefact*: Poly3Conv
    of Lookup:
      lookup*: LookupConv

  GenericUnitsCalib*[N: static[int]] = Calibs[N, GenericConv, SomeReading]


proc initGenericReadingCalibs*[N: static[int]](
  conversions: array[N, GenericConv]
): GenericUnitsCalib[N] =
  for i in 0 ..< N:
    result[i] = conversions[i]

type
  ResistorDividerConv* = distinct ScaleConv

# proc convert*[T, V](res: var V, val: T, ch: ScaleConv) =
#   # convert to volts
#   res = V(val.float32 * ch.calFactor)
