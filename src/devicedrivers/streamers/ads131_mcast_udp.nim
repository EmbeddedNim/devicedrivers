
## ============================================================ ##
## Fast RPC / Data Queue Support
## ============================================================ ##

import streamutils

import std/os, std/json, std/strformat
import std/[sequtils, strutils, locks]
import std/net

import nephyr/[nets]

include mcu_utils/threads
import mcu_utils/[logging, timeutils, allocstats]

import fastrpc/server/[fastrpcserver, rpcmethods, protocol]

import mcu_utils/msgbuffer
import mcu_utils/smlhelpers

import ../adcs/ads131

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

  ## adc timer
  adcTimer: k_timer

  ## adc kthreads
  adcThrReader {.exportc.}: k_thread
  adcThrMCast {.exportc.}: k_thread

  adsDriver: Ads131Driver
  adsMaddr: InetClientHandle

  adcUdpQ = AdcDataQ.init(size=20)

  timeA, timeB: Micros
  ta, tb: Micros
  sa, sb: Micros

  ## Globals for adc serialization
  lastReading = currTimeSenML()
  batch  = newSeq[AdcReading](10)
  msgBuf: MsgBuffer
  smls = newSeqOfCap[SmlReadingI](2*batch.len())

## ========================================================================= ##
## Adc Streamer Multicast UDP socket and serializer
## ========================================================================= ##

proc adcSerializer*(queue: AdcDataQ) =
  ## called by the socket server every time there's data
  ## on the queue argument given the `rpcEventSubscriber`.
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
    smls.add SmlReadingI(kind: BaseNT, ts: ts - lastReading, name: MacAddressArr)
    lastReading = ts
    for reading in batch:
      for i in 0..<reading.samples:
        let tsr = ts - reading.ts
        var vName: SmlString
        var cName: SmlString
        cName.data[0..3] = ['c', '0', '.', 'v']
        cName.count = 4
        vName.data[0..3] = ['c', '0', '.', 'v']
        cName.count = 4

        let vs = reading.samples[i].float32.toVoltage(gain=1, r1=0.0'f32, r2=1.0'f32)
        let cs = reading.samples[i].float32.toCurrent(gain=1, senseR=110.0'f32)
        smls.add SmlReadingI(kind: NormalNVU, name: vName, unit: 'V', ts: tsr, value: vs)
        smls.add SmlReadingI(kind: NormalNVU, name: cName, unit: 'A', ts: tsr, value: cs)

    msgBuf.pack(smls)

proc adcMCaster*(p1, p2, p3: pointer) {.zkThread.} = 
  echo "[adcMCaster] starting ... "
  var sock = newSocket(
    domain=Domain.AF_INET6,
    sockType=SockType.SOCK_DGRAM,
    protocol=Protocol.IPPROTO_UDP,
    buffered = false
  )

  logDebug "[SocketServer]::", "started:", "fd:", sock.getFd().int
  msgBuf = MsgBuffer.init(1500)
  withLock(adcTimerOpts.lock):
    while true:
      # for i in 0..<1:
      wait(adcTimerOpts.serializeCond, adcTimerOpts.lock)
      timeB = micros()
      ta = micros()
      msgBuf.data.setLen(1400)
      msgBuf.setPosition(0)
      adcUdpQ.adcSerializer()
      tb = micros()
      logExtraDebug "[udpThreadB] t-dt: " & $(tb.int - ta.int)

        sa = micros()
        msgBuf.data.setLen(msgBuf.pos)
        logExtraDebug "[udpThreadB] msg size: " & $msgBuf.data.len()
        let res = sock.sendTo(adsMaddr[].host, adsMaddr[].port, msgBuf.data)
        sb = micros()
        logExtraDebug "[udpThreadB] result: " & $res


proc adcSampler*(queue: AdcDataQ, ads: Ads131Driver) =
  ## Thread example that runs the as a time publisher. This is a reducer
  ## that gathers time samples and outputs arrays of timestamp samples.
  var reading: AdcReading
  ads.readChannels(reading.samples, ads.maxChannelCount)
  reading.ts = currTimeSenML()

  var qvals = isolate reading
  discard queue.chan.trySend(qvals)

## ========================================================================= ##
## Multicast (UDP) adc streamer
## ========================================================================= ##

proc adcReader*(p1, p2, p3: pointer) {.zkThread.} = 
  echo "[adcReader] starting ... "
  withLock(adcTimerOpts.lock):
    while true:
      wait(adcTimerOpts.timerCond, adcTimerOpts.lock)
      timeA = micros()
      adcSampler(adcUdpQ, adsDriver)
      broadcast(adcTimerOpts.serializeCond)


var
  wakeStr = ""
  wakeCount = 0'u32

proc adcTimerFunc(timerid: TimerId) {.cdecl.} =
  ## well schucks, that won't work...
  wakeCount.inc()
  if wakeCount mod 100 == 0:
    wakeStr.setLen(0)
    wakeStr &= "ts:" & millis().repr()
    wakeStr &= " wk:" & $(timeA.int - timeB.int) & "u" 
    wakeStr &= " serd:" & $(tb.int - ta.int) & "u" 
    wakeStr &= " send:" & $(sb.int - sa.int) & "u"
    echo wakeStr
  broadcast(adcTimerOpts.timerCond)
  # echo "[adcTimerFunc] timer awake: " & micros().repr()
  
proc initAds131Streamer*(
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
  adcPThr.createThread(udpThreadA, move arg)
  adcPThrB.createThread(udpThreadB, move arg)

  adcTimer.createTimer(adcTimerFunc)
  adcTimer.start(duration=2000.Millis, period=1.Millis)

