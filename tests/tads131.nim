import unittest
import strutils
import bitops
import print

import mcu_utils/basics


type
  ChGain = enum
    GX1 = 0x00
    GX2
    GX4
    GX6
    GX8
    GX12
  
  DataRate = enum
    Dr64k = 0b000
    Dr32k = 0b001
    Dr16k = 0b010
    Dr8k  = 0b011
    Dr4k  = 0b100
    Dr2k  = 0b101
    Dr1k  = 0b111
  
  Config1 = distinct uint8

proc `$`(cfg: Config1): string = "Config1(" & cfg.int.toBin(8) & ")"
proc daisyIn(b: Config1): bool = cast[bool](b.uint8.bitsliced(6..6))
proc clkEn(b: Config1): bool = cast[bool](b.uint8.bitsliced(5..5))
proc dataRate(b: Config1): DataRate  = cast[DataRate](b.uint8.bitsliced(0..2))
proc `daisyIn=`(b: var Config1, x: bool) = b.uint8.setBits(6..6, x)
proc `clkEn=`(b: var Config1, x: bool) = b.uint8.setBits(5..5, x)
proc `dataRate=`(b: var Config1, x: DataRate) = b.uint8.setBits(0..2, x)


suite "bit ops":

  setup:
    var regCfg1: Config1

  test "dr64k":
    regCfg1.dataRate = Dr64k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    check dr == Dr64k

  test "dr1k":
    regCfg1.dataRate = Dr1k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    check dr == Dr1k

  test "dr2k":
    regCfg1.dataRate = Dr2k
    print $regCfg1
    let dr = regCfg1.dataRate
    print dr
    check dr == Dr2k
