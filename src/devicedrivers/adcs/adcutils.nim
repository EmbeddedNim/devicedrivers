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
    bits*: int
    channels*: array[N, ChConfig]
  
  VoltsCalib*[N: static[int]] = Calib[N, Volts]

proc initVoltsCalib*[N: static[int]](
    vref: Volts,
    gains: array[N, float32]
): VoltsCalib[N] =
  result.vref = vref
  for i in 0 ..< N:
    result.channels[i].gain = gains[i]

proc convert*[N, T, V](val: T, calib: Calib[N, V], ch: ChConfig): V =
  when distinctBase(T) is SomeSignedInt:
    result = Volts( calib.vref.float32 / ch.gain / float32(2^(calib.bits-1)) )
  else:
    result = Volts( calib.vref.float32 / ch.gain / 2^(calib.bits) )

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
