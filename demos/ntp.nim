#
# NTP client demo
# ---------------
# Makes a request to ntp server and shows information.
# All serialization/deserialization work is being performed by NESM.
#

import
  nativesockets,
  net,
  os,
  sequtils,
  strutils,
  times

import NESM


serializable:
  static:
  # Types are static, so their size after serialization
  # can be calculated at compile time
    type
      FixedPoint16dot16 = uint32

      NTPTimeStamp = object
        set: {endian: bigEndian}
        # The endian of following fields is set to bigEndian,
        # so following values will be swapped while serialization
        # and there is no necessity to use htonl/ntohl
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

const twoto32 = 4294967296.0
const packet_size = NTPPacket.size() # Compile-time type size calculation
const unix_time_delta = 2208988800.0 # 1900 to 1970 in seconds

proc toEpoch(ts: NTPTimeStamp): float64 =
  let
    sec = ts.seconds.float - unix_time_delta
    frac = ts.fraction.float / twoto32
  sec + frac

proc fromEpoch(epoch: float64): NTPTimeStamp =
  let secs = epoch.uint32
  NTPTimeStamp(seconds: secs,
               fraction: uint32((epoch - secs.float) * twoto32))

when isMainModule:
  if paramCount() != 1:
    echo "Usage $# <ipaddr>" % paramStr(0)
    quit(1)

  let target = paramStr(1)
  let b = NTPPacket(

  # example values
    leap_version_mode: 0x23,
    stratum: 0x03,
    polling_interval: 0x06,
    clock_precision: 0xfa,
    delay: 0x00010000,
    dispersion: 0x00010000,
    reference_id: 0xaabbcc,
    origin_ts: epochTime().fromEpoch,
  )

  let bytes = cast[string](b.serialize())

  var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, true)
  # client send time
  let sendtime = epochTime()
  doAssert socket.sendTo(target, Port(123), bytes) == packet_size

  let raw_resp = socket.recv(packet_size, timeout=1000)

  # client receive time
  let resptime = epochTime()

  assert raw_resp.len == packet_size
  let resp: NTPPacket = deserialize(NTPPacket, raw_resp)

  let recvtime =  resp.receive_ts.toEpoch
  let anstime = resp.transmit_ts.toEpoch

  # NTP delay / clock_offset calculation
  let delay = (resptime - sendtime) - (anstime - recvtime)
  let clock_offset = (recvtime - sendtime + anstime - resptime)/2

  echo " Request sent:     ", sendtime
  echo " Request received: ", recvtime
  echo " Answer sent:      ", anstime
  echo " Answer received:  ", resptime
  echo " Round-trip delay: ", delay * 1000, " ms"
  echo " Clock offset:     ", clock_offset * 1000, " ms"
