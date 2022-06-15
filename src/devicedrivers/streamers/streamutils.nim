import std/os, std/json, std/strformat
import std/[sequtils, strutils, locks]

include mcu_utils/threads
import mcu_utils/[basictypes, logging, timeutils, allocstats]

import nephyr/general
import nephyr/times
import nephyr/nets
import nephyr/zephyr/kernel/zk_time

export general, zk_time

# import mcu_utils/inetselectors
import mcu_utils/smlhelpers
export smlhelpers

import fastrpc/server/rpcdatatypes

import ../adcs/ads131

template threadRunner*[R, T](name: string, arg: ThreadArg[R, T], code: untyped) =
  logInfo "[stream-thread][$1]: options: $2" % [name, repr(arg.opt.data)]

  while true:
    logAllocStats(lvlDebug):
      try:
        var opts {.inject.} = arg.opt.data
        var queue {.inject.} = arg.queue
        code
      except Exception as err:
        logError "[stream-thread] exception: ", err.msg
        continue
      except Defect as err: 
        logError "[stream-thread] defect: ", err.msg
        continue

  logError "[stream-thread][$1] shouldn't reach here: failed!" % [name]

let
  MacAddressStr* =
    when defined(zephyr):
      getDefaultInterface().hwMacAddress().foldl(a & b.toHex(2) & ":", "").toLowerAscii[0..^2]
    else:
      "11:22:33:44:55:66"
  MacAddressArr* =
    block:
      var ss = SmlString()
      for i in 0..<MacAddressStr.len():
        ss.data[i] = MacAddressStr[i]
      ss.count = MacAddressStr.len().int8
      ss
      