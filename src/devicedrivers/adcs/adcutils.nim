import std/[typetraits, math]

import mcu_utils/basics
import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging

const
  Vref = 4.0'f32
  Bitspace24: int = 2^23


type
  AdcReading*[N: static[int], T] = object
    ts*: Micros
    count*: int
    channels*: array[N, T]

  ChConfig* = object
    gain*: float32

  Calib*[N: static[int], V: Volts] = object
    vref*: Volts
    bitspace*: int64
    factor*: float32
    signextend*: bool
    channels*: array[N, ChConfig]
  
  VoltsCalib*[N: static[int]] = Calib[N, Volts]

# ============================================ #
# AdcReading Procs
# ============================================ #

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

proc `clear`*[N, T](reading: var AdcReading[N, T]) =
  ## helper for setting adc channel count
  reading.count = 0


# ============================================ #
# AdcReading Calibration Utils
# ============================================ #

proc initVoltsCalib*[N: static[int]](
    vref: Volts,
    bits: range[0..64],
    bipolar: bool,
    gains: array[N, float32]
): VoltsCalib[N] =
  result.vref = vref
  result.bitspace = if bipolar: 2^(bits-1) - 1 else: 2^(bits) - 1
  result.factor = vref.float32 / result.bitspace.float32
  for i in 0 ..< N:
    result.channels[i].gain = gains[i]

import strformat

proc convert*[N, T, V](val: T, calib: Calib[N, V], ch: ChConfig): V =
  echo fmt"convert: {val.repr=} {calib.repr=} {ch.repr=}"
  result = Volts(val.float32 / ch.gain * calib.factor.float32)

proc convert*[N, T](reading: AdcReading[N, T], calib: VoltsCalib, idx: int): Volts =
  result = reading.channels[idx].convert(calib, calib.channels[idx])

proc toVolts*[N, T, C](
    reading: AdcReading[N, T],
    calib: C,
): AdcReading[N, Volts] =
  result.ts = reading.ts
  result.count = reading.count
  for i in 0 ..< reading.count:
    result.channels[i] = reading.convert(calib, i)


# ===============================
# TODO: move to a better spot
# 
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
