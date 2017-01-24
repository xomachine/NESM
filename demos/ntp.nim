#
# NTP client demo
#

import
  nativesockets,
  net,
  os,
  sequtils,
  strutils,
  times

import NESM

# 1900 to 1970 in seconds
const unix_time_delta = 2208988800.0

proc to_host(x: uint32): uint32 = ntohl(x)

proc to_net(x: uint32): uint32 =
  htonl(x)

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


proc ntp_ts_to_epoch(ts: NTPTimeStamp): float64 =
  const twoto32 = 4294967296.0
  let
    sec = ts.seconds.to_host.float - unix_time_delta
    frac = ts.fraction.to_host.float / twoto32
  sec + frac

proc epoch_to_ntp_ts(x: float): NTPTimeStamp =

  result = NTPTimeStamp(
    seconds: uint32(x).to_net()
  )

const packet_size = NTPPacket.size()
assert packet_size == 48

proc main() =
  if paramCount() != 1:
    echo "Usage $# <ipaddr>" % paramStr(0)
    quit(1)

  let target = paramStr(1)

  var b = NTPPacket()

  # example values
  b.leap_version_mode = 0x23
  b.stratum = 0x03
  b.polling_interval = 0x06
  b.clock_precision = 0xfa
  b.delay = 0x00010000
  b.dispersion = 0x00010000
  b.reference_id = 0xaabbcc
  b.origin_ts = epochTime().epoch_to_ntp_ts

  let bytes = cast[string](b.serialize())

  var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, true)
  # client send time
  let t1 = epochTime()
  doAssert socket.sendTo(target, Port(123), bytes) == packet_size

  let raw_resp = socket.recv(packet_size, timeout=1000)

  # client receive time
  let t4 = epochTime()

  assert raw_resp.len == packet_size
  let resp: NTPPacket = deserialize(NTPPacket, raw_resp)

  let t2 =  resp.receive_ts.ntp_ts_to_epoch
  let t3 = resp.transmit_ts.ntp_ts_to_epoch

  # NTP delay / clock_offset calculation
  let delay = (t4 - t1) - (t3 - t2)
  let clock_offset = (t2 - t1 + t3 - t4)/2

  echo "delay:       ", delay * 1000, " ms"
  echo "clock_offset ", clock_offset * 1000, " ms"


when isMainModule:
  main()
