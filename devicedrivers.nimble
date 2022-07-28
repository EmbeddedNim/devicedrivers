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

requires "mcu_utils >= 0.3.3"
requires "fastrpc >= 0.2.0"
requires "nephyr >= 0.3.2"
