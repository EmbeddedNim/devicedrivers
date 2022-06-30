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

  ReadingCode* = distinct uint16

  SomeReading* = object
    unit*: ReadingCode
    val*: float32


variantp BasicConversion:
  # creates a Nim variant types
  # Note: uses `patty` library to simplify variant types
  IdentityConv
  ScaleConv(scale: float32)
  LinearConv(slope: float32, offset: float32)
  Poly3Conv(a0, a1, a2: float32)
  LookupLowerBoundConv(keys: seq[float32], values: seq[float32])
  # ClosureGenericConv(fn: proc (x: float32): float32) # maybe, escape hatch?


proc convert*[T, V](res: var V, val: T, conv: BasicConversion) =
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
  BasicCalibs*[N: static[int], V] = array[N, BasicConversion]

proc convert*[N: static[int], T, V](
    calibration: BasicCalibs[N, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  ## Creates a new AdcReading with channels converted using the calibration. 
  ## 
  runnableExamples:
    var calibration: BasicCalibs[1, ScaleConv, Volts]
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

## AdcReading Voltage Calibration
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## 

type
  VoltsConv* = object
  VoltsCalib*[N: static[int]] = BasicCalibs[N, Volts]


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

type
  CurrentSenseCalib*[N: static[int]] = BasicCalibs[N, Amps]


proc initCurrentSenseCalib*[N: static[int]](
    resistors: array[N, float32],
): CurrentSenseCalib[N] =
  ## initialize calibration for a shunt resistor based current sensor
  for i in 0 ..< N:
    result[i].scale = 1.0'f32 / resistors[i]

## Multiple Calibrations (WIP)
## 

type
  ReadingCalib* = object
    kind*: ReadingCode
    conv*: BasicConversion

  CombinedCalibs* = object
    pre*: BasicConversion
    post*: BasicConversion

proc transpose*[T, V](
    a: BasicCalibs[N, T],
    b: BasicCalibs[N, V],
): BasicCalibs[N, V] =
  # combine calibs??

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
