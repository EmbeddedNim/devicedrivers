import std/os, std/json, std/strformat
import std/[sequtils, strutils, locks]

include mcu_utils/threads
import mcu_utils/[basictypes, logging, timeutils, allocstats]

import nephyr/general
import nephyr/zephyr/kernel/zk_time

export general, zk_time

# import mcu_utils/inetselectors

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
