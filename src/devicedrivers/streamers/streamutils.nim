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

when defined(linux):
  type
    TimerId* = int
elif defined(zephyr):
  type
    TimerId* = ptr k_timer

type
  TimerFunc* = proc (timerid: TimerId) {.cdecl.}

when defined(linux):

  import stashtable

  var selector = newEventSelector()
  var callbacks = newStashTable[InetEvent, TimerFunc, 10]()

  proc timeEventsThread*() {.thread.} =
    {.cast(gcsafe).}:
      echo "\n===== running producer ===== "

      var events: Table[InetEvent, ReadyKey]
      var count = 0

      loop(selector, -1.Millis, events):
        inc count

        for event, key in events:
          callbacks.withValue(event):
            logDebug fmt"timer event: {event}"
            let cb: TimerFunc = value[]
            cb(event.timerfd.int)

  proc createTimer*(timeout: Millis, cb: TimerFunc) =
    ## linux hacks to emulate zephyr timers
    if cb != nil:
      let timer = selector.registerTimer(timeout.int, false)
      callbacks[timer] = cb

elif defined(zephyr):
  proc createTimer*(timer: var k_timer, cb: TimerFunc) =
    if cb != nil:
      k_timer_init(addr timer, cb, nil)
  
  
  proc start*(timer: var k_timer,
              duration = -1.Millis,
              period = -1.Millis) =
    let
      dts = if duration.int == -1: K_NO_WAIT else: K_MSEC(duration.int)
      pts = if period.int == -1: K_NO_WAIT else: K_MSEC(period.int)
    k_timer_start(addr timer, dts, pts)

  proc start*(timer: var k_timer,
              duration = -1.Micros,
              period = -1.Micros) =
    let
      dts = if duration.int == -1: K_NO_WAIT else: K_USEC(duration.int)
      pts = if period.int == -1: K_NO_WAIT else: K_USEC(period.int)
    k_timer_start(addr timer, dts, pts)
