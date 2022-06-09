import std/[sequtils, math]
from os import sleep

import mcu_utils/basics
import mcu_utils/timeutils
import mcu_utils/logging

import nephyr/zephyr/[zdevicetree, drivers/zspi]
import nephyr/[utils, drivers/gpio]

const
  SPI_DATA_BYTES = 64

  Vref = 4.0'f32
  Bitspace24: int = 2^23


type
  SampleRng = range[0..7]

  Ads131Driver* = ref object
    speed*: Hertz
    maxChannelCount*: int

    cs_ctrl: spi_cs_control
    spi_cfg: spi_config
    spi_dev: ptr device

    ndrdy:   Pin
    tx_buf:  array[SPI_DATA_BYTES, uint8]
    rx_buf:  array[SPI_DATA_BYTES, uint8]

    ndrdy_stats*: uint

  AdcReading* = object
    ts*: TimeSML
    channel_count*: int
    channels*: array[8, int32]

type
  CMD* {.pure.} = enum
    WAKEUP    = 0x02,
    STANDBY   = 0x04,
    RESET     = 0x06,
    START     = 0x08,
    STOP      = 0x0A,
    RDACTAC   = 0x10,
    SDATAC    = 0x11,
    RDATA     = 0x12,
    OFFSETCAL = 0x1A,
    RREG      = 0x20,
    WREG      = 0x40

type
  REG* {.pure.} = enum
    ID          = 0x00,
    CONFIG1     = 0x01,
    CONFIG2     = 0x02,
    CONFIG3     = 0x03,
    FAULT       = 0x04,
    CH1SET      = 0x05,
    CH2SET      = 0x06,
    CH3SET      = 0x07,
    CH4SET      = 0x08,
    CH5SET      = 0x09,
    CH6SET      = 0x0A,
    CH7SET      = 0x0B,
    CH8SET      = 0x0C,
    FAULT_STATP = 0x12,
    FAULT_STATN = 0x13,
    GPIO        = 0x14

proc spi_debug(self: Ads131Driver) =
  logDebug "ads131:", "cs_ctrl: ", repr(self.cs_ctrl)
  logDebug "ads131:", "spi_cfg: ", repr(self.spi_cfg)
  logDebug "ads131:", "spi_device: ", repr(self.spi_dev)

proc initSpi*(
    self: Ads131Driver,
    spi_freq: Hertz = 4_000_000.Hertz
) =
  ## initial the spi buses and ads131 driver

  self.spi_dev = DEVICE_DT_GET(tok"DT_PARENT(DT_NODELABEL(ads131_dev))")
  self.cs_ctrl = SPI_CS_CONTROL_PTR_DT(tok"DT_NODELABEL(ads131_dev)", tok`2`)[]

  self.spi_cfg = spi_config(
        frequency: spi_freq.uint32, #Fail on this spin of NRF52840, upclock to 20MHz for other MCU's
        operation: SPI_WORD_SET(8) or SPI_TRANSFER_MSB or SPI_OP_MODE_MASTER or SPI_MODE_CPHA,
        cs: addr self.cs_ctrl)
  
  self.ndrdy = initPin(alias"ads131_ndrdy",Pins.IN) #GPIO_DT_SPEC_GET(DT_NODELABEL(tok"ads131e08"), tok"int-gpios")
  spi_debug(self)
  
proc newAds131Driver*(
    speed: Hertz,
    maxChannelCount: int = 6
): Ads131Driver =
  result = Ads131Driver(
    speed: speed,
    maxChannelCount: maxChannelCount,
  )

proc execSpi(self: Ads131Driver, tx_data_len, rx_data_len: static[int]): seq[uint8] = 
  ## performs spi transaction for message. The total transmission length is
  ## the sum of the tx and rx length. 
  static:
    assert rx_data_len + tx_data_len <= SPI_DATA_BYTES

  var
    rx_bufs = @[spi_buf(buf: addr self.rx_buf[0], len: csize_t(sizeof(uint8) * (tx_data_len+rx_data_len))) ]
    rx_bset = spi_buf_set(buffers: addr(rx_bufs[0]), count: rx_bufs.len().csize_t)

  var
    tx_bufs = @[spi_buf(buf: addr self.tx_buf[0], len: csize_t(sizeof(uint8) * (tx_data_len+rx_data_len))) ]
    tx_bset = spi_buf_set(buffers: addr(tx_bufs[0]), count: tx_bufs.len().csize_t)
  check: spi_transceive(self.spi_dev, addr self.spi_cfg, addr tx_bset, addr rx_bset)
  result = self.rx_buf[tx_data_len..(tx_data_len+rx_data_len)].toSeq()

proc readReg*(self: Ads131Driver, reg: REG): uint8 =
  self.rx_buf[2] = 0x00
  self.tx_buf[0] = cast[uint8](RREG) or cast[uint8](reg)
  self.tx_buf[1] = 0x00
  self.tx_buf[2] = 0x00

  var spi_ret = self.execSpi(2, 1)
  result = spi_ret[0]

proc writeReg*(self: Ads131Driver, reg: REG, value: uint8) = 
  self.tx_buf[0] = WREG.uint8 or reg.uint8
  self.tx_buf[1] = 0x00
  self.tx_buf[2] = value
  discard self.execSpi(3,0)

proc sendCmd*(self: Ads131Driver, cmd: CMD) =
  self.tx_buf[0] = cast[uint8](cmd)
  discard self.execSpi(1, 0)

proc reset*(self: Ads131Driver) = 
  ## resets the ADC to initial state
  self.sendCmd(RESET)

proc configure*(self: Ads131Driver) =
  ## configures the ads module
  self.reset()
  self.sendCMD(SDATAC)
  self.sendCMD(STOP)
  self.writeReg(CONFIG1, 0x96) #1kHz
  #adsWriteReg(CH1SET,0x60) #Gain 12 on CH1
  self.sendCMD(START)
  self.sendCMD(OFFSETCAL)
  

proc readChannelsRaw*(self: Ads131Driver, data: var openArray[int32], sampleCnt: SampleRng) {.raises: [OSError].} = 
  # read all channels from ads131
  logDebug("readChannels: wait nrdyd ")
  var nready = 1
  while nready == 1: # Spin until you can read, active low
    nready = self.ndrdy.level()
  if nready > 1:
    self.ndrdy_stats.inc()
  # if nready > 4:
    # logWarn("readChannels: spin wait on nrdyd ", nready)

  logDebug("readChannels: ready done ")
  self.tx_buf[0] = RDATA.uint8
  var spi_ret = self.execSpi(1,27)
  for i in countup(0, sampleCnt):
    var reading: int32
    reading = joinBytes32[int32](spi_ret[(i+1)*3..(i+1)*3+2],count=3)
    reading = (reading shl 8) shr 8 # Sign extension
    data[i] = reading

proc readChannelsRaw*(self: Ads131Driver, count: SampleRng): seq[int32] {.raises: [OSError].} = 
  result = newSeq[int32](count)
  self.readChannelsRaw(result, count)

proc readChannelsRaw*(self: Ads131Driver): seq[int32] {.raises: [OSError].} = 
  result = newSeq[int32](self.maxChannelCount)
  self.readChannelsRaw(result, self.maxChannelCount)

proc readChannels*(self: Ads131Driver, reading: var AdcReading, channelCount: int) {.raises: [OSError].} = 
  ## primary api for reading from adc
  self.readChannelsRaw(reading.channels, channelCount)
  reading.channel_count = channelCount

proc readChannels*(self: Ads131Driver, reading: var AdcReading) {.raises: [OSError].} = 
  ## primary api for reading from adc
  self.readChannelsRaw(reading.channels, self.maxChannelCount)
  reading.channel_count = self.maxChannelCount

template toCurrent*[T](chval: T,
                     gain: static[int],
                     senseR: static[float32],
                     ): float32 =
  const coef: float32 = Vref/(Bitspace24.toFloat()*gain)/senseR
  chval * coef

template toVoltage*[T](chval: T,
                     gain: static[float32],
                     r1: static[float32] = 99.8,
                     r2: static[float32]): float32 =
  const coef: float32 = Vref/(Bitspace24.toFloat()*gain)/(r2/(r1+r2))
  chval * coef

proc avgReading*(self: Ads131Driver, avgCount: int): seq[float] =
  logDebug("taking averaged ads131 readings", "avgCount:", avgCount)

  # take readings
  var readings = newSeq[AdcReading](avgCount)
  for idx in 0 ..< avgCount:
    readings[idx].ts = currTimeSenML()
    self.readChannels(readings[idx])
  
  # average adc readings
  result = newSeq[float](self.maxChannelCount)
  for rd in readings:
    for i in 0 ..< self.maxChannelCount:
      result[i] += rd.channels[i].toFloat() / avgCount.float
