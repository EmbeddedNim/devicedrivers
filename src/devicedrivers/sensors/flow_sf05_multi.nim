import sequtils
import json
import options
import tables

import nephyr/utils

import nephyr/drivers/i2c
import nephyr/net/json_rpc/router

import hal_buses
import qwiic_mux
import hal_sf05


const
  QWIIC_MUX_DEFAULT_ADDRESS = I2cAddr 0x70

var
  mux*: QwiicMux
  flowMeters*: TableRef[Sf05Ident, int]

proc multi_sf05_scan_port*(): TableRef[Sf05Ident, int]

proc multi_sf05_setup*() =
  let devptr = i2cBusDefault()
  when not defined(Sf05SinglePortOverride):
    var i2cDev = initI2cDevice(devptr, QWIIC_MUX_DEFAULT_ADDRESS)
    mux = initQwiicMux(i2cDev)
    echo "setup qwiic mux"
  flowMeters = multi_sf05_scan_port()

proc multi_sf05_dbg*() =
  echo "mux: ", repr mux
  echo "flowMeters: ", $flowMeters

proc multi_sf05_is_connected*() =
  echo "mux: ", repr mux

proc multi_sf05_read_port*(port: int, retries=2): float32 =
  when not defined(Sf05SinglePortOverride):
    mux.setPort(uint8 port)
  return sf05_read()

proc multi_sf05_scan_port*(): TableRef[Sf05Ident, int] =
  result = newTable[Sf05Ident, int](4)
  for port in 0..0:
    when not defined(Sf05SinglePortOverride):
      mux.setPort(uint8 port)
    let res = sf05_get_serial()
    echo "scan mux port: ", repr port, " result: ", repr res
    if res.isSome():
      result[res.get()] = port

proc multi_sf05_available*(): TableRef[Sf05Ident, int] =
  result = flowMeters

proc multi_sf05_read_all*(retries=2): TableRef[Sf05Ident, float] =
  result = newTable[Sf05Ident, float](4)
  for fmid, pn in flowMeters.pairs():
    result[fmid] = multi_sf05_read_port(pn)


proc addMultiSf05Methods*(rt: var RpcRouter) =

  rpc(rt, "qwiik-mux-dbg") do() -> int:
    multi_sf05_dbg()
    result = 0

  rpc(rt, "qwiik-is-conn") do() -> JsonNode:
    return %* mux.isConnected()

  rpc(rt, "qwiik-set-port") do(port: int) -> JsonNode:
    mux.setPort(uint8 port)
    return %* "ok"

  rpc(rt, "qwiik-get-port") do() -> JsonNode:
    let pn = int mux.getPort()
    return %* {"port": pn}

  rpc(rt, "qwiik-scan-ports") do() -> JsonNode:
    let found = multi_sf05_scan_port()
    return %* {"active_ports": found}


