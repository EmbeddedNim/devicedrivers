
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
import mcu_utils/inetqueues
import mcu_utils/smlhelpers

import ../adcs/ads131

export smlhelpers
export inetqueues


const
  DEFAULT_BATCH_SIZE = 10
  WAKE_COUNT = 400

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
  AdcDataQ* = InetEventQueue[AdcReading[Bits32]]

  AdcOptions* = ref object
    batch*: int
    ads*: Ads131Driver
    lock: Lock
    timerCond: Cond
    serializeCond: Cond

  AdcReadingBatch* = ref object
    size: int
    readings: array[DEFAULT_BATCH_SIZE, AdcReading[Bits32]]


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
  adcUdpQ*: AdcDataQ

var
  adcTimerOpts: AdcOptions

  adsDriver: Ads131Driver
  adsMaddr: InetClientHandle

  timeA, timeB: Micros
  readA, readB: Micros
  readsA: array[400, Micros]
  readsAidx = 0
  maxReadsA = 399
  ta, tb: Micros
  sa, saPrev: Micros
  sb, sbPrev: Micros
  serdeLastBatchCount = 0
  serdeLastByteCount = 0.BytesSz

  ## Globals for adc serialization
  lastReading = micros()
  batch  = newSeq[AdcReading[Bits32]](10)
  msgBuf: MsgBuffer
  smls = newSeqOfCap[SmlReadingI](2*batch.len())

var
  wakeStr = "" # preallocate string
  wakeCount = 0'u32 # uint so if we overflow it's fine

proc timingPrints() =
    # echo ""
    wakeStr.setLen(0)
    wakeStr &= "wake ts:" 
    wakeStr &= millis().repr()
    wakeStr &= " tdelta broadcasts:" 
    wakeStr &= repr(timeB - timeA)
    wakeStr &= " ser:" 
    wakeStr &= repr(tb - ta)
    wakeStr &= " adc:" 
    wakeStr &= repr(readB - readA)
    wakeStr &= " send:" 
    wakeStr &= repr(sb - sa)
    wakeStr &= " snd-dt:" 
    wakeStr &= repr(sa - saPrev)
    wakeStr &= " bcnt:" 
    wakeStr &= $serdeLastBatchCount 
    wakeStr &= " mpack:" 
    wakeStr &= $serdeLastByteCount.int

    var avgReadDt = 0
    let rcnt = min(readsA.len(), maxReadsA )
    for i in 1 .. rcnt:
      avgReadDt = avgReadDt + int(readsA[i] - readsA[i-1])
      readsA[i-1] = 0.Micros
    avgReadDt = avgReadDt.int div (rcnt-1)
    readsAidx = 0

    wakeStr &= " avgReadDt:" 
    wakeStr &= $avgReadDt.int
    logDebug wakeStr


## ========================================================================= ##
## Thread to take ADC Readings 
## ========================================================================= ##

proc adcSampler*(queue: AdcDataQ, ads: Ads131Driver) =
  ## Thread example that runs the as a time publisher. This is a reducer
  ## that gathers time samples and outputs arrays of timestamp samples.
  var reading: AdcReading[Bits32]

  # if wakeCount mod WAKE_COUNT == 0:
    # logInfo("[adcSampler]", "reading")
  ads.readChannels(reading, ads.maxChannelCount)

  # tag reading time and put in queue
  reading.ts = micros()
  var qvals = isolate reading
  discard queue.chan.trySend(qvals)


proc adcReaderThread*(p1, p2, p3: pointer) {.zkThread, cdecl.} = 
  ## very simple zephyr thread that ## waits on
  ## the k_timer to trigger the `timerCond` condition
  ## 
  logInfo "[adcReader] thread starting ... "
  withLock(adcTimerOpts.lock):
    while true:
      wait(adcTimerOpts.timerCond, adcTimerOpts.lock)
      timeA = micros() # for timing prints down below

      ## take adc reading
      readA = timeA
      if readsAidx <= maxReadsA:
        readsA[readsAidx] = timeA
        readsAidx.inc()
      adcSampler(adcUdpQ, adsDriver)
      readB = micros()

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

    let ts = micros()
    smls.setLen(0)
    smls.add SmlReadingI(kind: BaseNT, ts: ts.timeSenML(), name: MacAddressArr)
    lastReading = ts

    logExtraDebug("[adcSampler]", fmt"{batch.len()=}")
    
    var
      vName: SmlString
      vUnit: SmlString
      cName: SmlString
      cUnit: SmlString

    # brute force for now ;) 

    # v data
    vName.data[0..3] = ['c', '0', '.', 'v']
    vName.count = 4
    # v unit
    vUnit.data[0] = 'V'
    vUnit.count = 1

    # c data
    cName.data[0..3] = ['c', '0', '.', 'c']
    cName.count = 4
    # c unit
    cUnit.data[0] = 'A'
    cUnit.count = 1

    
    for reading in batch:
      for i in 0..<reading.channel_count:
        let tsr = timeSenML(reading.ts - ts)

        # voltage channels
        # vName.data[1] = char(i + ord('0'))
        # let vs = reading.channels[i].float32.toVoltage(gain=1, r1=0.0'f32, r2=1.0'f32)
        # smls.add SmlReadingI(kind: NormalNTVU, name: vName, unit: vUnit, ts: tsr, value: vs)

        # current channels
        cName.data[1] = char(i + ord('0'))
        let cs = reading.channels[i].float32.toCurrent(gain=1, senseR=110.0'f32)
        smls.add SmlReadingI(kind: NormalNTVU, name: cName, unit: cUnit, ts: tsr, value: cs)
        logExtraDebug("[adcSampler]", fmt"added reading {smls.len()=}")


    msgBuf.pack(smls)
    msgBuf.data.setLen(msgBuf.pos)

    serdeLastBatchCount = batch.len()
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
        timeB = micros()

      ta = micros()
      msgBuf.data.setLen(1400)
      msgBuf.setPosition(0)
      adcUdpQ.adcSerializer()
      tb = micros()
      logExtraDebug "[adcMCaster] t-dt: " & $(tb.int - ta.int)

      saPrev = sa
      sa.setTime()
      msgBuf.data.setLen(msgBuf.pos)
      logExtraDebug "[adcMCaster] msg size: " & $msgBuf.data.len()
      let res = sock.sendTo(adsMaddr[].host, adsMaddr[].port, msgBuf.data)
      if res == 0:
        logInfo "[adcMCaster] send result: " & $res
      sbPrev = sb
      sb.setTime()
      logExtraDebug "[adcMCaster] result: " & $res





## ========================================================================= ##
## Initializers
## ========================================================================= ##


proc adcTimerFunc*(timerid: TimerId) {.cdecl.} =
  ## well schucks, that won't work...
  wakeCount.inc()
  if wakeCount mod WAKE_COUNT == 0:
    timingPrints()
  broadcast(adcTimerOpts.timerCond)

  logExtraDebug "[adcTimerFunc] timer awake: " & micros().repr()
  
proc initMCastStreamer*(
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
    arg = ThreadArg[AdcReading[Bits32], AdcOptions](queue: adcUdpQ, opt: topt)

  adsMaddr = maddr
  adsDriver = ads 

  logInfo("ads131 mcast: ", adsDriver.repr)


