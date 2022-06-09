
## ============================================================ ##
## Fast RPC / Data Queue Support
## ============================================================ ##

import streamutils

import std/os, std/json, std/strformat
import std/[sequtils, strutils, locks]
import std/net

import nephyr/[nets, times]

include mcu_utils/threads
import mcu_utils/[logging, timeutils, allocstats]

import fastrpc/server/[fastrpcserver, rpcmethods, protocol]

import mcu_utils/msgbuffer
import mcu_utils/smlhelpers

import ../adcs/ads131

export smlhelpers

const
  DEFAULT_BATCH_SIZE = 10

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
      

type
  AdcDataQ* = InetEventQueue[AdcReading]

  AdcOptions* = ref object
    batch*: int
    ads*: Ads131Driver
    lock: Lock
    timerCond: Cond
    serializeCond: Cond

  AdcReadingBatch* = ref object
    size: int
    readings: array[DEFAULT_BATCH_SIZE, AdcReading]


proc newAdcOptions*(batch: int, ads: Ads131Driver): AdcOptions =
  ## initialize a new adc option type, including locks 
  result = AdcOptions(batch: batch, ads: ads)
  initLock(result.lock)
  initCond(result.timerCond)
  initCond(result.serializeCond)


## ========================================================================= ##
## Adc Streamer Globals
## ========================================================================= ##

var
  adcTimerOpts: AdcOptions

  adsDriver: Ads131Driver
  adsMaddr: InetClientHandle

  adcUdpQ = AdcDataQ.init(size=20)

  timeA, timeB: Millis
  ta, tb: Micros
  sa, sb: Micros
  serdeLastByteCount = 0.BytesSz

  ## Globals for adc serialization
  lastReading = currTimeSenML()
  batch  = newSeq[AdcReading](10)
  msgBuf: MsgBuffer
  smls = newSeqOfCap[SmlReadingI](2*batch.len())

var
  wakeStr = "" # preallocate string
  wakeCount = 0'u32 # uint so if we overflow it's fine

const 
  WAKE_COUNT = 1

## ========================================================================= ##
## Thread to take ADC Readings 
## ========================================================================= ##

proc adcSampler*(queue: AdcDataQ, ads: Ads131Driver) =
  ## Thread example that runs the as a time publisher. This is a reducer
  ## that gathers time samples and outputs arrays of timestamp samples.
  var reading: AdcReading

  if wakeCount mod WAKE_COUNT == 0:
    logInfo("[adcSampler]", fmt"{ads.maxChannelCount=}")
  ads.readChannels(reading, ads.maxChannelCount)

  # tag reading time and put in queue
  reading.ts = currTimeSenML()
  var qvals = isolate reading
  discard queue.chan.trySend(qvals)


proc adcReaderThread*(p1, p2, p3: pointer) {.zkThread, cdecl.} = 
  ## very simple zephyr thread that ## waits on
  ## the k_timer to trigger the `timerCond` condition
  ## 
  echo "[adcReader] thread starting ... "
  withLock(adcTimerOpts.lock):
    while true:
      wait(adcTimerOpts.timerCond, adcTimerOpts.lock)
      timeA = millis() # for timing prints down below

      ## take adc reading
      adcSampler(adcUdpQ, adsDriver)

## ========================================================================= ##
## Adc Streamer Multicast UDP socket and serializer
## ========================================================================= ##

proc adcSerializer*(queue: AdcDataQ) =
  ## called by the socket thraed every time there's data to write
  ## 

  logAllocStats(lvlDebug):
    var idx = 0
    batch.setLen(10)
    while queue.tryRecv(batch[idx]):
      inc idx
    batch.setLen(idx)
    # echo "serde:msgBuf: " & $msgBuf.pos

    let ts = currTimeSenML()
    smls.setLen(0)
    smls.add SmlReadingI(kind: BaseNT, ts: ts, name: MacAddressArr)
    lastReading = ts

    logExtraDebug("[adcSampler]", fmt"{batch.len()=}")
    
    var
      vName: SmlString
      vUnit: SmlString
      cName: SmlString
      cUnit: SmlString

    # brute force for now ;) 
    vUnit.data[0] = 'V'
    vUnit.count = 1
    cUnit.data[0] = 'A'
    vUnit.count = 1

    for reading in batch:
      for i in 0..<reading.channel_count:
        let tsr = reading.ts - ts
        vName.data[0..3] = ['c', '0', '.', 'v']
        vName.count = 4
        cName.data[0..3] = ['c', '0', '.', 'c']
        cName.count = 4

        let vs = reading.channels[i].float32.toVoltage(gain=1, r1=0.0'f32, r2=1.0'f32)
        let cs = reading.channels[i].float32.toCurrent(gain=1, senseR=110.0'f32)
        smls.add SmlReadingI(kind: NormalNVU, name: vName, unit: vUnit, ts: tsr, value: vs)
        smls.add SmlReadingI(kind: NormalNVU, name: cName, unit: cUnit, ts: tsr, value: cs)
        logExtraDebug("[adcSampler]", fmt"added reading {smls.len()=}")


    msgBuf.pack(smls)
    serdeLastByteCount = msgBuf.data.len().BytesSz
    logExtraDebug("[adcSampler]", fmt"{msgBuf.data.len()=}")

proc adcMCasterThread*(p1, p2, p3: pointer) {.zkThread, cdecl.} = 
  ## zephyr thread that handles sending UDP multicast whenever if gets a wake signal 
  ## 
  logInfo "[adcMCaster] starting ... "
  var sock = newSocket(
    domain=Domain.AF_INET6,
    sockType=SockType.SOCK_DGRAM,
    protocol=Protocol.IPPROTO_UDP,
    buffered = false
  )

  logDebug "[adcMCaster]::", "socket:", "fd:", sock.getFd().int
  msgBuf = MsgBuffer.init(1500)

  ## Main thread loop
  withLock(adcTimerOpts.lock):
    while true:
      for i in 0..<adcTimerOpts.batch:
        # we wait for batch count timer wakeups 
        # then we read all adc data from queue
        # so batch size becomes how many adc readings we're batching up
        wait(adcTimerOpts.timerCond, adcTimerOpts.lock)

      timeB = millis()
      ta = micros()
      msgBuf.data.setLen(1400)
      msgBuf.setPosition(0)
      adcUdpQ.adcSerializer()
      tb = micros()
      logExtraDebug "[adcMCaster] t-dt: " & $(tb.int - ta.int)

      sa = micros()
      msgBuf.data.setLen(msgBuf.pos)
      logExtraDebug "[adcMCaster] msg size: " & $msgBuf.data.len()
      let res = sock.sendTo(adsMaddr[].host, adsMaddr[].port, msgBuf.data)
      sb = micros()
      logExtraDebug "[adcMCaster] result: " & $res



## ========================================================================= ##
## Initializers
## ========================================================================= ##

proc adcTimerFunc*(timerid: TimerId) {.cdecl.} =
  ## well schucks, that won't work...
  wakeCount.inc()
  if wakeCount mod WAKE_COUNT == 0:
    wakeStr.setLen(0)
    wakeStr &= "ts:" & millis().repr()
    wakeStr &= " timer wk:" 
    wakeStr &= repr(timeA - timeB)
    wakeStr &= " serd:" 
    wakeStr &= repr(tb - ta)
    wakeStr &= " send:" 
    wakeStr &= repr(sb - sa)
    echo wakeStr

  broadcast(adcTimerOpts.timerCond)

  logExtraDebug "[adcTimerFunc] timer awake: " & micros().repr()
  
proc startMcastStreamerThreads*(
    maddr: InetClientHandle,
    ads: Ads131Driver,
    batch = DEFAULT_BATCH_SIZE,
    decimateCnt = 0,
    queueSize = 2,
) = 
  ## setup the ads131 data streamer, register it to the router, and start the thread.
  adcTimerOpts = newAdcOptions(batch=batch, ads=ads)
  adcTimerOpts.lock.initLock()
  adcTimerOpts.timerCond.initCond()
  adcTimerOpts.serializeCond.initCond()

  var
    topt = TaskOption[AdcOptions](data: adcTimerOpts)
    arg = ThreadArg[AdcReading, AdcOptions](queue: adcUdpQ, opt: topt)

  adsMaddr = maddr
  adsDriver = ads 

  logInfo("ads131 mcast: ", adsDriver.repr)


