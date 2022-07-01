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

