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

import std/[math, algorithm, sequtils]

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
  LinearConv(m: float32, n: float32)
  Poly3Conv(a, b, c: float32)
  LookupLowerBoundConv(llkeys: seq[float32], llvalues: seq[float32])
  # ClosureGenericConv(fn: proc (x: float32): float32) # maybe, escape hatch?


proc convert*[T, V](res: var V, val: T, conv: BasicConversion) =
  let x = val.float32
  match conv:
    IdentityConv:
      res = V(x)
    ScaleConv(f: factor):
      res = V(factor * x)
    LinearConv(slope, offset):
      res = V(slope*x + offset)
    Poly3Conv(a, b, c):
      res = V(a + b*x^1 + c*x^2)
    LookupLowerBoundConv(llkeys: keys, llvalues: values):
      let idx = keys.lowerBound(x)
      res = V(values[idx])

type

  ReadingCalibKind* {.pure.} = enum
    Single
    Composite
    Closure

type

  ReadingCode* = distinct uint16

  SomeReading* = object
    unit*: ReadingCode
    val*: float32

  ReadingCalib*[T] = object
    # code*: ReadingCode
    pre*: BasicConversion
    calib*: BasicConversion

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
  let conv = ScaleConv(f = factor / gain.float32)
  result = ReadingCalib[Volts](kind: Single, calib: conv)


proc init*(
    tp: typedesc[CurrentSenseCalib],
    resistor: Ohms,
): CurrentSenseCalib =
  ## initialize calibration for a shunt resistor based current sensor
  let conv = ScaleConv(f = 1.0'f32 / resistor.float32)
  result = ReadingCalib[Amps](calib: conv)


## Combined Calibrations (WIP)
## 

proc combine*[V](
    lhs: BasicConversion,
    rhs: BasicConversion,
): ReadingCalib[V] =
  # combine calibs??

  ## start from the most basic
  match lhs:
    IdentityConv:
      result.calib = rhs

    ScaleConv(f1):
      match rhs:
        IdentityConv:
          result.calib = lhs

        ScaleConv(f2):
          result.calib = ScaleConv(f = f1*f2)

        LinearConv(m2, n2):
          result.calib = LinearConv(m = f1*m2, n = n2)

        Poly3Conv(a2, b2, c2):
          result.calib = Poly3Conv(a = a2, b = f1*b2, c = f1^2*c2)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          var lk = lk2.mapIt(it / f1)
          result.calib = LookupLowerBoundConv(llkeys = lk, llvalues = lv2)

    LinearConv(m1, n1):
      match rhs:
        IdentityConv:
          result.calib = lhs

        ScaleConv(f2):
          result.calib = LinearConv(m = f2*m1, n = n1)

        LinearConv(m2, n2):
          result.calib = LinearConv(m = m1*m2, n = m2*n1 + n2)

        Poly3Conv(a2, b2, c2):
          # from sympy:
          #  a2 + b2*n1 + c2*m1**2*x**2 + c2*n1**2 + x*(b2*m1 + 2*c2*m1*n1)
          let a = a2 + b2*n1 + c2*n1^2
          let b = b2*m1 + 2*c2*m1*n1
          let c = c2*m1^2
          result.calib = Poly3Conv(a = a, b = b, c = c)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          # sympy: ' k1 > m1 * x + n1'
          # so: ' (k1 - n1) / m1 > x'
          var lk = lk2.mapIt( (it - n1) / m1 )
          result.calib = LookupLowerBoundConv(llkeys = lk, llvalues = lv2)

    Poly3Conv(a1, b1, c1):
      match rhs:
        IdentityConv:
          result.calib = lhs

        ScaleConv(f2):
          result.calib = Poly3Conv(a = a1*f2, b = b1*f2, c = c1*f2)

        LinearConv(m2, n2):
          # sympy: a1*m2 + b1*m2*x + c1*m2*x^2 + n2
          result.calib = Poly3Conv(a = a1+m2+n2, b = b1*m2, c = c1*m2)

        Poly3Conv(a2, b2, c2):
          # raise newException(KeyError, "cannot combine poly3 with poly3")
          result = ReadingCalib[V](pre: lhs, calib: rhs)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          # raise newException(KeyError, "cannot combine poly3 with lltable")
          result = ReadingCalib[V](pre: lhs, calib: rhs)

    LookupLowerBoundConv(lk1, lv1):
      match rhs:
        IdentityConv:
          result.calib = lhs
        
        ScaleConv(f2):
          var lv = lv1.mapIt(it * f2)
          result.calib = LookupLowerBoundConv(llkeys = lk1, llvalues = lv)

        LinearConv(m2, n2):
          # raise newException(KeyError, "cannot combine lltable with poly3")
          result = ReadingCalib[V](pre: lhs, calib: rhs)

        Poly3Conv(a2, b2, c2):
          # raise newException(KeyError, "cannot combine lltable with poly3")
          result = ReadingCalib[V](pre: lhs, calib: rhs)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          # raise newException(KeyError, "cannot combine lltable with lltable")
          result = ReadingCalib[V](pre: lhs, calib: rhs)


proc combine*[T, V](
    lhs: ReadingCalib[T],
    rhs: ReadingCalib[V],
): ReadingCalib[V] =
  match lhs:
    Single(calib: cal1):
      match rhs:
        Single(calib: cal2):
          result = combine[V](cal1, cal2)
        _:
          discard
    _:
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



when isMainModule:
  import strformat
  let vcalib = AdcVoltsCalib.init(vref=4.Volts,
                                  bits=24,
                                  bipolar=true,
                                  gain = 2.0.Gain)
  let mAcalib = CurrentSenseCalib.init(resistor = 110.Ohms) 

  # TODO: get this to work?
  let mAReadingCalib: ReadingCalib[Amps] = combine(vcalib, mAcalib)
  echo fmt"mAReadingCalib : {mAReadingCalib.repr()=}"
  echo fmt"mAReadingCalib : {$typeof(mAReadingCalib )=}"

