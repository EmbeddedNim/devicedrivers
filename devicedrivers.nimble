# Package

version       = "0.1.0"
author        = "Jaremy J. Creechley"
description   = "Embedded Device Driver library"
license       = "Apache-2.0"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.0"
requires "print >= 1.0.2" # pretty colored print
requires "cdecl >= 0.5.4"

requires "https://github.com/EmbeddedNim/mcu_utils#head"
requires "https://github.com/EmbeddedNim/fastrpc#head"
