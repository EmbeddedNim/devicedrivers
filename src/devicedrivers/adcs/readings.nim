## ===================
## Calibrated Readings 
## ===================
## 

import std/[math, algorithm, sequtils, options]

import adcutils
import conversions

export conversions
export calibrations

type

  ReadingCode* = distinct uint16

  SomeReading* = object
    unit*: ReadingCode
    val*: float32


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
