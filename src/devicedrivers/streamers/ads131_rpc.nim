
## ============================================================ ##
## Fast RPC / Data Queue Support
## ============================================================ ##

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

proc adcSerializer*(queue: AdcDataQ): seq[AdcReading] {.rpcSerializer.} =
  ## called by the socket server every time there's data
  ## on the queue argument given the `rpcEventSubscriber`.
  ## 
  var batch: seq[AdcReading]
  if queue.tryRecv(batch):
    result = batch
    discard
    
proc adcSampler*(queue: AdcDataQ, opts: TaskOption[AdcOptions]) {.rpcThread, raises: [].} =
  ## Thread example that runs the as a time publisher. This is a reducer
  ## that gathers time samples and outputs arrays of timestamp samples.
  var config = opts.data
  var sample_count = 0'i32
  
  var ads: Ads131Driver = opts.data.ads
  let NC = ads.maxChannelCount

  while true:
    logAllocStats(lvlDebug):
      try:
        # var adc_batch = AdcReadingBatch(size: config.batch)
        var adc_batch = newSeq[AdcReading](config.batch)
        for i in 0..<config.batch:
          # take readings
          ads.readChannels(adc_batch[i].samples, NC)

          # reduce number of samples, decimation!
          if config.decimate_cnt >= 0:
              for j in 0 ..< config.decimate_cnt:
                ads.readChannels(adc_batch[i].samples, NC)

          adc_batch[i].ts = currTimeSenML()

          sample_count.inc()
          adc_batch[i].sample_count = sample_count

        var qvals = isolate adc_batch
        discard queue.trySend(qvals)
      except OSError:
        continue
      except IOSelectorsException: #Don't judge me.
        continue


proc streamThread*(arg: ThreadArg[seq[AdcReading], AdcOptions]) {.thread, nimcall.} = 
  logInfo "streamThread: ", repr(arg.opt.data)
  adcSampler(arg.queue, arg.opt)


proc initAds131Streamer*(
    router: var FastRpcRouter,
    thr: var RpcStreamThread[AdcReadingBatch, AdcOptions], 
    ads: Ads131Driver,
    batch = DEFAULT_BATCH_SIZE,
    decimateCnt = 0,
    queueSize = 2,
): RpcStreamThread[seq[AdcReading], AdcOptions] = 
  ## setup the ads131 data streamer, register it to the router, and start the thread.
  var
    adc1q = AdcDataQ.init(size=queueSize)
    adcOpt = AdcOptions(decimate_cnt: decimateCnt, batch: batch, ads: ads)

  var tchan: Chan[AdcOptions] = newChan[AdcOptions](1)
  var topt = TaskOption[AdcOptions](data: adcOpt, ch: tchan)
  var arg = ThreadArg[seq[AdcReading],AdcOptions](queue: adc1q, opt: topt)
  result.createThread(streamThread, move arg)

  router.registerDataStream(
    "adcstream",
    serializer = adcSerializer,
    reducer = adcSampler, 
    queue = adc1q,
    option = adcOpt,
    optionRpcs = adcOptionsRpcs,
  )

