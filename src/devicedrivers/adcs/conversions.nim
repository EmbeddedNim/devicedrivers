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

proc isIdentity*(conv: BasicConversion): bool =
  result = conv.kind == BasicConversionKind.IdentityConv

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



## Combined Calibrations (WIP)
## 

proc reduce*(
    lhs: BasicConversion,
    rhs: BasicConversion,
): BasicConversion =
  # combine calibs??

  ## start from the most basic
  match lhs:
    IdentityConv:
      result = rhs

    ScaleConv(f1):
      match rhs:
        IdentityConv:
          result = lhs

        ScaleConv(f2):
          result = ScaleConv(f = f1*f2)

        LinearConv(m2, n2):
          result = LinearConv(m = f1*m2, n = n2)

        Poly3Conv(a2, b2, c2):
          result = Poly3Conv(a = a2, b = f1*b2, c = f1^2*c2)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          var lk = lk2.mapIt(it / f1)
          result = LookupLowerBoundConv(llkeys = lk, llvalues = lv2)

    LinearConv(m1, n1):
      match rhs:
        IdentityConv:
          result = lhs

        ScaleConv(f2):
          result = LinearConv(m = f2*m1, n = n1)

        LinearConv(m2, n2):
          result = LinearConv(m = m1*m2, n = m2*n1 + n2)

        Poly3Conv(a2, b2, c2):
          # from sympy:
          #  a2 + b2*n1 + c2*m1**2*x**2 + c2*n1**2 + x*(b2*m1 + 2*c2*m1*n1)
          let a = a2 + b2*n1 + c2*n1^2
          let b = b2*m1 + 2*c2*m1*n1
          let c = c2*m1^2
          result = Poly3Conv(a = a, b = b, c = c)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          # sympy: ' k1 > m1 * x + n1'
          # so: ' (k1 - n1) / m1 > x'
          var lk = lk2.mapIt( (it - n1) / m1 )
          result = LookupLowerBoundConv(llkeys = lk, llvalues = lv2)

    Poly3Conv(a1, b1, c1):
      match rhs:
        IdentityConv:
          result = lhs

        ScaleConv(f2):
          result = Poly3Conv(a = a1*f2, b = b1*f2, c = c1*f2)

        LinearConv(m2, n2):
          # sympy: a1*m2 + b1*m2*x + c1*m2*x^2 + n2
          result = Poly3Conv(a = a1+m2+n2, b = b1*m2, c = c1*m2)

        Poly3Conv(a2, b2, c2):
          raise newException(KeyError, "cannot combine poly3 with poly3")
          # result = ReadingCalib[V](pre: lhs, calib: rhs)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          raise newException(KeyError, "cannot combine poly3 with lltable")
          # result = ReadingCalib[V](pre: lhs, calib: rhs)

    LookupLowerBoundConv(lk1, lv1):
      match rhs:
        IdentityConv:
          result = lhs
        
        ScaleConv(f2):
          var lv = lv1.mapIt(it * f2)
          result = LookupLowerBoundConv(llkeys = lk1, llvalues = lv)

        LinearConv(m2, n2):
          raise newException(KeyError, "cannot combine lltable with poly3")
          # result = ReadingCalib[V](pre: lhs, calib: rhs)

        Poly3Conv(a2, b2, c2):
          raise newException(KeyError, "cannot combine lltable with poly3")
          # result = ReadingCalib[V](pre: lhs, calib: rhs)

        LookupLowerBoundConv(llkeys: lk2, llvalues: lv2):
          raise newException(KeyError, "cannot combine lltable with lltable")
          # result = ReadingCalib[V](pre: lhs, calib: rhs)

