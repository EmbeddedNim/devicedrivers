import options
import strutils

import nephyr/utils
import nephyr/drivers/i2c

import hal_buses

type
  Sf05Ident* = string

var
  dev: I2cDevice
  errCount: int

const
  SF05_ADDR*: I2cAddr = I2cAddr(0x40)
  CMD_READ_CONTINUOUS*: I2cRegister = I2cReg16(0x1000)
  CMD_READ_SERIAL_HIGH*: I2cRegister = I2cReg16(0x31AE)
  CMD_READ_SERIAL_LOW*: I2cRegister = I2cReg16(0x31AF)
  CMD_SOFT_RESET*: I2cRegister = I2cReg16(0x2000)

  SCALE_FLOW* = 140'f32   #// scale factor flow
  OFFSET_FLOW* = 32_000'f32   #// offset flow

  POLYNOMIAL* = 0x131'u16    #// P(x) = x^8 + x^5 + x^4 + 1 = 100110001

proc sf05_setup*() =
  let devptr = i2cBusDefault()
  dev = initI2cDevice(devptr, SF05_ADDR)

proc sf05_dbg*(): tuple[errCount: int] =
  echo "sf05:i2c:dbg: ", repr(dev)
  return (errCount: errCount)

proc sf05_check_crc*(data: openArray[uint8]; checksum: uint8) =
  ## ==============================================================================
  var bit: uint8 ##  bit mask
  var crc: uint8 = 0 ##  calculated checksum
  var byteCtr: uint8 ##  byte counter

  ##  calculates 8-Bit checksum with given polynomial
  byteCtr = 0'u8

  while byteCtr < data.clen():
    crc = crc xor (data[byteCtr])
    bit = 8
    while bit > 0:
      if (crc and 0x80) != 0'u8:
        crc = uint8( (crc shl 1) xor POLYNOMIAL) ## TODO: this is rounded?
      else:
        crc = (crc shl 1)
      dec(bit)
    inc(byteCtr)
  ##  verify checksum
  if crc != checksum:
    # echo "sfm3000 checksum failure"
    raise newException(OSError, "sfm3000 checksum failure")

proc sf05_get_serial*(): Option[Sf05Ident] =
  try:
    var data: Bytes[4]
    dev.doTransfer(
      regWrite(CMD_READ_SERIAL_LOW, STOP),
      read(data, STOP)
    )

    let
      num = joinBytes32[int](data, 4)
      strnum = num.toHex()
    result = some(strnum)
  except Exception:
    result = Sf05Ident.none()


proc sf05_read_raw*(): int =
  var data: Bytes[3]
  dev.doTransfer(
    regWrite(CMD_READ_CONTINUOUS, STOP),
    read(data, STOP)
  )

  # echo "sf05: read: ", $data
  sf05_check_crc(data[0..1], data[2])
  result = joinBytes32[int](data, 2)

proc sf05_read*(retries=2): float32 =
  try:
    let val = sf05_read_raw().toFloat()
    result = (val - OFFSET_FLOW) / SCALE_FLOW;
  except Exception:
    # echo "raise error, retry"
    inc errCount
    if retries > 0:
      return sf05_read(retries=retries-1)
    return NaN


