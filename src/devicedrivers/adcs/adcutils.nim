## =============
## ADC Utilities
## =============
## 
## This module contains generic types and functions to 
## represent and work with readings from ADCs. It provides
## a core generic `AdcReading` type. The number of channels
## and the storage types can be configured to match an ADC.  
## 

import std/[sequtils, typetraits, math, times, monotimes]

import mcu_utils/basics
import mcu_utils/basictypes
import mcu_utils/timeutils
import mcu_utils/logging


type
  AdcReading*[N: static[int], T] = object
    ## Generic adc reading object 
    ## - `N` is the max readings for the ADC, must be a compile time int
    ## - `T` is the basic reading type, e.g. int32 or float32 
    ts*: MonoTime
    count*: int
    channels*: array[N, T]

proc `$`*(reading: AdcReading): string =
  var ts = Micros(convert(Nanoseconds, Microseconds, reading.ts.ticks))
  result &= "AdcReading("
  result &= "ts:" & repr(ts)
  result &= ", chans:["
  result &= reading.channels.mapIt(it.repr).join(", ")
  result &= "])"

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
