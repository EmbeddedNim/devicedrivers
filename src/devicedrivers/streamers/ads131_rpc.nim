

## ============================================================ ##
## Fast RPC / Data Queue Support
## ============================================================ ##

import std/os, std/json, std/strformat

include mcu_utils/threads
import mcu_utils/[logging, timeutils, allocstats]

import fastrpc/server/[fastrpcserver, rpcmethods]

import ../adcs/ads131

const
  DEFAULT_BATCH_SIZE = 10


type
  AdcDataQ* = InetEventQueue[seq[AdcReading]]

  AdcOptions* {.rpcOption.} = object
    decimate_cnt*: int
    batch*: int
    ads*: Ads131Driver

  AdcReadingBatch* = ref object
    size: int
    readings: array[DEFAULT_BATCH_SIZE, AdcReading]

DefineRpcTaskOptions[AdcOptions](name=adcOptionsRpcs):
  discard ## do nothing for now, we still need it below

# TODO: move to mcu_utils
proc `-`*(a, b: TimeSML): TimeSML {.borrow.}
proc `%`*(a: TimeSML): JsonNode {.borrow.}


proc adcSerializer*(queue: AdcDataQ): FastRpcParamsBuffer {.rpcSerializer.} =
  ## called by the socket server every time there's data
  ## on the queue argument given the `rpcEventSubscriber`.
  ## 
  logExtraDebug "[adcSerialier] trigger "
  var batch: seq[AdcReading]
  if queue.tryRecv(batch):
    let ts = currTimeSenML()
    var res = %* [
      {"bn": "ads131raw", "bt": ts.float64, "bu": "v"},
    ]

    for reading in batch:
      for i in 0..<reading.channel_count:
        let tsr = ts - timeSenML(reading.ts)
        let vs = reading.channels[i].float32.toVoltage(gain=1, r1=0.0'f32, r2=1.0'f32)
        let cs = reading.channels[i].float32.toCurrent(gain=1, senseR=110.0'f32)
        res.add(%* {"n": fmt"ch{i}-voltage", "u": "V", "t": tsr, "v": vs})
        res.add(%* {"n": fmt"ch{i}-current", "u": "A", "t": tsr, "v": cs})

    result = rpcPack(res)
    logExtraDebug "[adcSerialier] serde: ", $result.buf.data.len()
    
proc adcSampler*(queue: AdcDataQ, opts: TaskOption[AdcOptions]) {.rpcThread, raises: [].} =
  ## Thread example that runs the as a time publisher. This is a reducer
  ## that gathers time samples and outputs arrays of timestamp samples.
  var config = opts.data
  var sample_count = 0'u32
  
  var ads: Ads131Driver = opts.data.ads
  let chCount = ads.maxChannelCount

  while true:
    logAllocStats(lvlDebug):
      try:
        if sample_count mod 300 == 0:
          logDebug "[adcSample] adc read ", $sample_count
          logExtraDebug "[adcSample] queue: ", " ptr: ", queue.chan.unsafeAddr.pointer.repr
        # var adc_batch = AdcReadingBatch(size: config.batch)
        var adc_batch = newSeq[AdcReading](config.batch)
        for i in 0..<config.batch:
          # take readings
          ads.readChannels(adc_batch[i], chCount)

          # reduce number of samples, decimation!
          if config.decimate_cnt >= 0:
              for j in 0 ..< config.decimate_cnt:
                ads.readChannels(adc_batch[i], chCount)

          adc_batch[i].ts = micros()

          sample_count.inc()
          adc_batch[i].channel_count = chCount

        var qvals = isolate adc_batch
        discard queue.trySend(qvals)
        os.sleep(14)
      except OSError:
        continue
      except IOSelectorsException: #Don't judge me.
        continue


proc streamThread*(arg: ThreadArg[seq[AdcReading], AdcOptions]) {.thread, nimcall.} = 
  os.sleep(1_000)
  logInfo "adc-stream thread:", repr(arg.opt.data)
  adcSampler(arg.queue, arg.opt)


proc initAds131Streamer*(
    router: var FastRpcRouter,
    thr: var RpcStreamThread[seq[AdcReading], AdcOptions],
    ads: Ads131Driver,
    batch = DEFAULT_BATCH_SIZE,
    decimateCnt = 0,
    queueSize = 2,
) = 
  ## setup the ads131 data streamer, register it to the router, and start the thread.
  var
    adc1q = AdcDataQ.init(size=queueSize)
    adcOpt = AdcOptions(decimate_cnt: decimateCnt, batch: batch, ads: ads)

  var tchan: Chan[AdcOptions] = newChan[AdcOptions](1)
  var topt = TaskOption[AdcOptions](data: adcOpt, ch: tchan)
  var arg = ThreadArg[seq[AdcReading],AdcOptions](queue: adc1q, opt: topt)
  thr.createThread(streamThread, move arg)

  logInfo "registerDataStream: ", "adc:queue:ptr: ", adc1q.chan.unsafeAddr.pointer.repr()
  router.registerDataStream(
    "adcstream",
    serializer = adcSerializer,
    reducer = adcSampler, 
    queue = adc1q,
    option = adcOpt,
    optionRpcs = adcOptionsRpcs,
  )

