##
##   This is an Arduino library written for the TCA9548A/PCA9548A 8-bit multiplexer.
##   By Nathan Seidle @ SparkFun Electronics, May 16th, 2020
##
##   The TCA9548A/PCA9548A allows for up to 8 devices to be attached to a single
##   I2C bus. This is helpful for I2C devices that have a single I2C address.
##
##   https://github.com/sparkfun/SparkFun_I2C_Mux_Arduino_Library
##
##   SparkFun labored with love to create this code. Feel like supporting open
##   source? Buy a board from SparkFun!
##   https://www.sparkfun.com/products/14685
##


import nephyr/drivers/i2c


type
  QwiicMux* = object
    i2cDev: I2cDevice

proc isConnected*(mux: var QwiicMux): bool
proc disablePort*(mux: var QwiicMux, pn: uint8): bool
proc enablePort*(mux: var QwiicMux, pn: uint8): bool
proc getPortState*(mux: var QwiicMux): uint8
proc setPortState*(mux: var QwiicMux, portBits: uint8): bool
proc getPort*(mux: var QwiicMux, ): uint8
proc setPort*(mux: var QwiicMux, portNumber: uint8)

## Sets up the Mux for basic function
## Returns true if device responded correctly. All ports will be disabled.

proc initQwiicMux*(wirePort: var I2cDevice): QwiicMux =
  ## Get user's options
  result.i2cDev = wirePort

proc begin*(mux: var QwiicMux): bool =
  ## Get user's options
  return mux.isConnected()

proc isConnected*(mux: var QwiicMux): bool =
  ## Returns true if device is present
  ## Tests for device ack to I2C address
  ## Then tests if device behaves as we expect
  ## Leaves with all ports disabled

  # Nim nep1 format
  try:
    mux.i2cdev.doTransfer()

    discard mux.setPortState(0xA4)

    ## Set port register to a known value
    var response: uint8 = mux.getPortState()
    discard mux.setPortState(0x00)
    ## Disable all ports
    echo "response: ", repr response
    if response == 0xA4:
      return true

    return false

  except Exception:
    echo "isConnected excpt:", getCurrentExceptionMsg()
    return false

proc setPort*(mux: var QwiicMux, portNumber: uint8) =
  ## Enables one port. Disables all others.
  ## If port number if out of range, disable all ports
  var portValue: uint8 = 0
  if portNumber > 7:
    portValue = 0
  else:
    portValue = 1'u8 shl portNumber

  mux.i2cDev.doTransfer(
    write([portValue], STOP)
  )

proc getPort*(mux: var QwiicMux): uint8 =
  ## Read the current mux settings
  ## Returns the first port number bit that is set
  ## Returns 255 if no port is enabled
  ## 
  ## mux.i2cDev->beginTransmission(mux.deviceAddress); <- Don't do this!
  var data: Bytes[1]
  mux.i2cDev.doTransfer(
    read(data, STOP)
  )

  ## Search for the first set bit, then return its location
  var portBits: uint8 = data[0]

  var x: uint8 = 0
  while x < 8:
    if (portBits and (1'u8 shl x)) != 0:
      return x
    inc(x)

  return 255 ## Return no port set

## Writes a 8-bit value to mux
## Overwrites any other bits
## This allows us to enable/disable multiple ports at same time
proc setPortState*(mux: var QwiicMux, portBits: uint8): bool =

  try:
    mux.i2cDev.doTransfer(
      write([portBits], STOP)
    )
    return true
  except:
    echo "isConnected excpt:", getCurrentExceptionMsg()
    return false

## Gets the current port state
## Returns byte that may have multiple bits set

proc getPortState*(mux: var QwiicMux): uint8 =
  ## Read the current mux settings
  ## mux.i2cDev->beginTransmission(mux.deviceAddress); <- Don't do this!
  var data: Bytes[1]
  mux.i2cDev.doTransfer(
    read(data, STOP)
  )
  return data[0]

## Enables a specific port number
## This allows for multiple ports to be 'turned on' at the same time. Use with caution.

proc enablePort*(mux: var QwiicMux, pn: uint8): bool =
  var portNumber = min(pn, 7)

  ## Set the wanted bit to enable the port
  var settings = mux.getPortState()
  settings = settings or (1'u8 shl portNumber)
  return mux.setPortState(settings)

## Disables a specific port number

proc disablePort*(mux: var QwiicMux, pn: uint8): bool =
  var portNumber = min(pn, 7)

  var settings = mux.getPortState()
  ## Clear the wanted bit to disable the port
  settings = settings and not (1'u8 shl portNumber)
  return mux.setPortState(settings)

