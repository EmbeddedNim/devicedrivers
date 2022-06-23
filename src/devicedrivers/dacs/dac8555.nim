## License: Apache-2.0
## 

## ================
## DAC 8555 Driver
## ================
##
## TODO: This needs to be ported to Zephyr

import strutils, json, sequtils

import nesper
import nesper/consts, nesper/general, nesper/gpios, nesper/spis, nesper/timers
import hal_settings, hal_pins, hal_buses

import nesper/servers/rpc/router

const
  DAC_CMD_WRITE             = 0x00'u8

# Note: DAC8555 Broadcast left unimplemented

proc dac_calib_get(): tuple[gain: int32, zero: int32] =
  return (gain: SETTINGS.dac_calib_gain_chc, zero: SETTINGS.dac_calib_zero_chc)

# calibration offset, and tweak valuec
proc dac_value(val: int16): seq[byte] =
  let
    calib = dac_calib_get()
    calib_zero = int16(calib.zero)

  var
    val_adj: uint16 = calib_zero.uint16 + (val.uint16 - 0x7FFF'u16)
    val_bytes = splitBytes(val_adj, 2, top=true)

  return val_bytes

proc dac_value( uv: uV): int16 =
  {.cast(gcsafe).}: 
    let
      calib = dac_calib_get()
    return int16(uv.int32 div calib.gain)

proc dac_write_cmd(cmd: byte, val: seq[byte]): SpiTrans =
  DAC_SPI.writeTrans(cmd=cmd, data=val)

proc dac_write_cmd(cmd: byte, val: int16): SpiTrans =
  let
    val = dac_value(val)
  dac_write_cmd(DAC_CMD_WRITE, val)

proc dac_write*(val: int16) = 
  {.cast(gcsafe).}: 
    var trn = dac_write_cmd(DAC_CMD_WRITE, val)
    trn.poll()

proc dac_write*(uv: uV) =
  {.cast(gcsafe).}: 
    dac_write(dac_value(uv))

proc dac_axe_set*(uv: uV) =
  {.cast(gcsafe).}: 
    dac_write(uv)

proc cfg_dac*() =
  dac_write(0.mV)

proc addDacMethods*(rt: var RpcRouter) =

  rpc(rt, "dac-write-raw") do(value: int) -> int:
    dac_write(value.int16)
    return ESP_OK

  rpc(rt, "dac-write") do(value: int) -> int:
    dac_write(value.mV)
    return ESP_OK

  rpc(rt, "dac-write-arr-f1") do(ch: string, delay_us: int, repeat: int, values: seq[int]) -> int:
    let
      vals = values.mapIt(dac_value(it.mV))

    for i in 0..<repeat:
      for v in vals:
        dac_write(v)
        delay(delay_us.Micros)

    return ESP_OK




