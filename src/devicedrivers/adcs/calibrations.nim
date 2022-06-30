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
import persistent_enums

import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging

import adcutils


## Calibration Basics
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

variantp BasicConversion:
  # creates a Nim variant types
  # Note: uses `patty` library to simplify variant types
  IdentityConv
  ScaleConv(f: float32)
  LinearConv(m: float32, b: float32)
  Poly3Conv(a0, a1, a2: float32)
  LookupLowerBoundConv(llkeys: seq[float32], llvalues: seq[float32])
  # ClosureGenericConv(fn: proc (x: float32): float32) # maybe, escape hatch?


proc convert*[T, V](res: var V, val: T, conv: BasicConversion) =
  let x = val.float32
  match conv:
    IdentityConv:
      res = V(x)
    ScaleConv(f: factor):
      res = V(factor * x)
    LinearConv(m: slope, b: offset):
      res = V(slope*x + offset)
    Poly3Conv(a0: a0, a1: a1, a2: a2):
      res = V(a0 + a1*x^1 + a2*x^2)
    LookupLowerBoundConv(llkeys: keys, llvalues: values):
      let idx = keys.lowerBound(x)
      res = V(values[idx])


type

  ReadingCode* = distinct uint16

  SomeReading* = object
    unit*: ReadingCode
    val*: float32


  ReadingCalib*[T] = object
    conv*: BasicConversion

  ReadingIdCalib* = object
    kind*: ReadingCode
    conv*: BasicConversion


type

  ReadingCodes* {.persistent.} = enum
    ## table of reading codes "persistent" enum 
    rdAdcRawVolts
    rdVolts
    rdAmps
    rdPressure
    rdFlowKPa
    rdDeltaFlowKPa

  ## table of reading codes "persistent" enum 
  RdAdcRawVolts* = distinct ReadingCode
  RdVolts* = distinct ReadingCode
  Rd420mAmps* = distinct Amps
  RdPressure* = distinct ReadingCode
  RdFlowKPa* = distinct ReadingCode
  RdDeltaFlowKPa* = distinct ReadingCode
  # ... etc


type
  AdcVoltsCalib* = ReadingCalib[Volts]
  CurrentSenseCalib* = ReadingCalib[Amps]

proc init*(
    tp: typedesc[AdcVoltsCalib],
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gain: Gain,
): AdcVoltsCalib =
  ## initalize a calibration for adc-bits to voltage conversion
  let bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  let factor = vref.float32 / bitspace.float32
  result.conv = ScaleConv(f = factor / gain.float32)


proc init*(
    tp: typedesc[CurrentSenseCalib],
    resistor: Ohms,
): CurrentSenseCalib =
  ## initialize calibration for a shunt resistor based current sensor
  result.conv = ScaleConv(f = 1.0'f32 / resistor.float32)


## Combined Calibrations (WIP)
## 

proc transpose*[T, V](
    a: ReadingCalib[T],
    b: ReadingCalib[V],
): ReadingCalib[V] =
  # combine calibs??
  discard

type
  CombinedCalibs*[T] = object
    pre*: BasicConversion
    post*: BasicConversion

proc transpose*[T, V](
    a: CombinedCalibs[T],
    b: CombinedCalibs[V],
): CombinedCalibs[V] =
  # combine calibs??
  discard


## Array of BasicConv for single layer 'static' conversions
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## 

type
  ChannelsCalibs*[N: static[int], V] = array[N, BasicConversion]


proc convert*[N: static[int], T, V](
    calibration: ChannelsCalibs[N, V],
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

type

  VoltsCalibs*[N: static[int]] = ChannelsCalibs[N, Volts]


proc initAdcVoltsCalib*[N: static[int]](
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gains: array[N, float32],
): VoltsCalibs[N] =
  ## initalize a calibration for adc-bits to voltage conversion
  let bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  let factor = vref.float32 / bitspace.float32
  for i in 0 ..< N:
    result[i] = ScaleConv(f = factor / gains[i])


type
  CurrentSenseCalibs*[N: static[int]] = ChannelsCalibs[N, Amps]


proc initCurrentSenseCalib*[N: static[int]](
    resistors: array[N, float32],
): CurrentSenseCalibs[N] =
  ## initialize calibration for a shunt resistor based current sensor
  for i in 0 ..< N:
    result[i] = ScaleConv(f = 1.0'f32 / resistors[i])
