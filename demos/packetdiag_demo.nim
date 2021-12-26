#
# Packetdiag generator for NESM - NTP packet example
#
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under MIT License, see LICENSE file
#
# Requires packetdiag from the blockdiag suite
# http://blockdiag.com/en/nwdiag/packetdiag-examples.html
#

import NESM
import packetdiag

serializable:
  static:
    type
      nuint16 = distinct uint16
      nint16  = distinct int16
      nuint32 = distinct uint32
      nint32  = distinct int32
      nuint64 = distinct uint64
      nint64  = distinct int64

      FixedPoint16dot16 = uint32
      seconds = distinct nuint32
      fraction = distinct nuint32
      FixedPoint32dot32 = object
        seconds: uint32
        fraction: uint32

      NTPTimeStamp = object
        seconds: uint32
        fraction: uint32

      LeapVersionMode = uint8

      NTPPacket = object
        leap_version_mode: LeapVersionMode
        stratum: uint8
        polling_interval: int8
        clock_precision: uint8
        delay: FixedPoint16dot16
        dispersion: FixedPoint16dot16
        reference_id: uint32
        reference_ts: NTPTimeStamp
        origin_ts: NTPTimeStamp
        receive_ts: NTPTimeStamp
        transmit_ts: NTPTimeStamp

when isMainModule:
  var b = NTPPacket()
  # add numbered=true for field numbers
  b.generate_diagram(fname="packet.svg", width=32)
  echo "packet.svg generated."
