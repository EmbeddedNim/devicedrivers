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

import std/[math, algorithm, sequtils, options]

import patty
import persistent_enums

import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging

import adcutils
import conversions

export conversions

type

  ReadingCode* = distinct uint16

  SomeReading* = object
    unit*: ReadingCode
    val*: float32

  ReadingCalib*[T] = object
    # code*: ReadingCode
    calib*: BasicConversion

  CompositeReadingCalib*[T] = object
    # code*: ReadingCode
    pre*: BasicConversion
    post*: BasicConversion


## Combined Calibrations (WIP)
## 

proc reduce*[T, V](
    lhs: ReadingCalib[T],
    rhs: ReadingCalib[V],
): ReadingCalib[V] =
  result.calib = reduce[V](lhs.calib, rhs.calib)

proc combine*[T, V](
    lhs: ReadingCalib[T],
    rhs: ReadingCalib[V],
): CompositeReadingCalib[V] =
  try:
    result.pre = IdentityConv()
    result.post = reduce[V](lhs.calib, rhs.calib)
  except KeyError:
    result.pre = lhs.calib
    result.post = rhs.calib

proc combine*[T, V](
    lhs: ReadingCalib[T],
    rhs: CompositeReadingCalib[V],
): CompositeReadingCalib[V] =
  try:
    let res = combine[V](lhs.calib, rhs.pre)
    result.pre = res
  except KeyError:
    raise newException(KeyError, fmt"cannot combine {lhs.calib.kind} with {rhs.pre.kind} to make a ")


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
  let conv = ScaleConv(f = factor / gain.float32)
  result = ReadingCalib[Volts](calib: conv)


type
  CurrentSenseCalib* = ReadingCalib[Amps]

proc init*(
    tp: typedesc[CurrentSenseCalib],
    resistor: Ohms,
): CurrentSenseCalib =
  ## initialize calibration for a shunt resistor based current sensor
  let conv = ScaleConv(f = 1.0'f32 / resistor.float32)
  result = ReadingCalib[Amps](calib: conv)


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



when isMainModule:
  import strformat
  let vcalib = AdcVoltsCalib.init(vref=4.Volts,
                                  bits=24,
                                  bipolar=true,
                                  gain = 2.0.Gain)
  let mAcalib = CurrentSenseCalib.init(resistor = 110.Ohms) 

  let mAReadingCalib: ReadingCalib[Amps] = reduce(vcalib, mAcalib)
  echo fmt"mAReadingCalib : {mAReadingCalib.repr()=}"
  echo fmt"mAReadingCalib : {$typeof(mAReadingCalib )=}"

