#
# Packetdiag generator for NESM
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under MIT License, see LICENSE file
#
# Requires packetdiag from the blockdiag suite
# http://blockdiag.com/en/nwdiag/packetdiag-examples.html

import osproc,
  streams,
  strutils,
  typeinfo

const
  packetdiag_bin_path = "/usr/bin/packetdiag"
  packetdiag_cmd = "/usr/bin/packetdiag"
  dot_fname = "packet.dot"

proc write_dot_file(dot: seq[string]) =
  ## Write out .dot file
  let pkt = dot.join("\n")
  writeFile(dot_fname, pkt)

proc render_file(fname: string) =
  ## Generate image file
  let
    format = fname.rsplit('.', 1)[1]
    cmd = "$# -a $# -o $# -T $#" % [packetdiag_bin_path, dot_fname, fname, format]
  doAssert execCmd(cmd) == 0

proc gen_dot_diagram(a: Any, width: int, fname: string, numbered=false) =
  ## Generate .dot packet diagram
  var dot = @[
    "{",
    "  colwidth = $#" % $width,
    """  default_node_color = "#fffaf0"""",
    ""
  ]
  var byte_cnt = 0

  case a.kind
  of akNone: assert false
  of akObject, akTuple:
    var i = 0
    var nodenum = 0
    for raw_key, val in fields(a):
      nodenum.inc
      let key = raw_key.capitalize()
      let s = size(val) * 8
      var byte_end = 0
      var entry = ""
      if s == 1:
        byte_end = byte_cnt
        entry = "  $#: $# [rotate = 89]" % [$byte_cnt, key]
      else:
        byte_end = byte_cnt + s - 1
        if s > width and (s mod width) == 0:
          let colheight = s div width
          let column_end = byte_cnt + width - 1
          if numbered:
            entry = """  $#-$#: $# [colheight = $#, color = "#fff0e0", numbered = $#]""" % [
              $byte_cnt, $column_end, key, $colheight, $nodenum
            ]

          else:
            entry = """  $#-$#: $# [colheight = $#, color = "#fff0e0"]""" % [
              $byte_cnt, $column_end, key, $colheight
            ]

        else:
          entry = """  $#-$#: $#""" % [$byte_cnt, $byte_end, key]
          if numbered:
            entry.add "[numbered = $#]" % $nodenum

      dot.add entry
      byte_cnt = byte_end + 1

  else:
    discard

  dot.add("}")

  write_dot_file(dot)

proc generate_diagram*[T](a: var T, width = 64, fname = "packet.png", numbered = false) =
  ## Genrate .dot diagram and render it as an image
  gen_dot_diagram(a.toAny(), width, fname, numbered=numbered)
  render_file(fname)
