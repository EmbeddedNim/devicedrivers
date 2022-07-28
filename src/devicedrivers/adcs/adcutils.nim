import std/[typetraits, math, monotimes]

import mcu_utils/basics
import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging

# AdcReading
# ~~~~~~~~~~~~~~~~ 
# 
# this section makes `AdcReading` behave like a container. 
# so you can directly do `reading[1]` and `reading.setLen(3)`
# 


type
  AdcReading*[N: static[int], T] = object
    # generic adc reading object 
    # - `N` is the max readings for the ADC 
    # - `T` is the basic reading type, e.g. int32 or float32 
    ts*: MonoTime
    count*: int
    channels*: array[N, T]

proc `[]=`*[N, T](reading: var AdcReading[N, T], idx: int, val: T) =
  ## helper for setting adc channel readings
  reading.channels[idx] = val

proc `[]`*[N, T](reading: var AdcReading[N, T], idx: int): var T =
  ## helper for setting adc channel readings
  result = reading.channels[idx]
proc `[]`*[N, T](reading: AdcReading[N, T], idx: int): T =
  ## helper for setting adc channel readings
  result = reading.channels[idx]


proc `setLen`*[N, T](reading: var AdcReading[N, T], idx: int) =
  ## helper for setting adc channel count
  reading.count = idx

proc `setTimestamp`*[N, T](reading: var AdcReading[N, T]) =
  ## helper for setting adc channel count
  reading.ts = getMonoTime()

proc `clear`*[N, T](reading: var AdcReading[N, T]) =
  ## helper for setting adc channel count
  reading.count = 0


# AdcReading Calibration Utils
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
# this section is the initial *volts calibration* for an adc
#
# Generic Type Name Conventions:
# - `N` number of channels (must be static[int] for compile time)
# - `T` actual reading type and implies incoming type
# - `V` actual reading type but implies outgoing type
# - `G` calibration factors array

type
  OneFactorConv* = object
    # per channel config for a calibration setup
    calFactor*: float32

  TwoFactorConv* = object
    # per channel config for a calibration setup
    calFactor*: float32
    calOffset*: float32


  Calibs*[N: static[int], G, V] = array[N, G]


proc convert*[T, V](res: var V, val: T, ch: OneFactorConv) =
  # convert to volts
  res = V(val.float32 * ch.calFactor)

proc convert*[T, V](res: var V, val: T, ch: TwoFactorConv) =
  # convert to volts
  res = V(val.float32 * ch.calFactor + ch.calOffset)

proc convert*[N, T, G, V](
    calib: Calibs[N, G, V],
    reading: AdcReading[N, T],
): AdcReading[N, V] =
  # returns a new AdcReading converted to volts. The reading type is `Volts`
  # which are a float32.
  result.ts = reading.ts
  result.count = reading.count
  for i in 0 ..< reading.count:
    result[i].convert(reading[i], calib[i])

proc combine*[N, T, G1, G2, V](
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
  VoltsCalib*[N: static[int]] = Calibs[N, OneFactorConv, Volts]

    # an Adc-to-Volts calibration for an AdcReading of N channels

proc initVoltsCalib*[N: static[int]](
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

# ===============================
# TODO: remove or refactor
# ===============================

const
  Vref = 4.0'f32
  Bitspace24: int = 2^23

template toVoltageDivider*[T](chval: T,
                     gain: static[float32],
                     r1: static[float32] = 99.8,
                     r2: static[float32]): float32 =
  const coef: float32 = Vref/(Bitspace24.toFloat()*gain)/(r2/(r1+r2))
  chval * coef
template toCurrent*[T](chval: T,
                     gain: static[int],
                     senseR: static[float32],
                     ): float32 =
  const coef: float32 = Vref/(Bitspace24.toFloat()*gain)/senseR
  chval * coef

proc average*[N: static[int], T](readings: openArray[AdcReading[N, T]]): AdcReading[N, T] =
  logDebug("taking averaged ads131 readings", "avgCount:", avgCount)

  # average adc readings
  result = AdcReading[N, T]
  let cnt = T(readings.len())
  for rd in readings:
    for i in 0 ..< N:
      when distinctBase(T) is SomeInteger:
        result[i] += rd.channels[i] div cnt 
      elif distinctBase(T) is SomeFloat:
        result[i] += rd.channels[i] / cnt
