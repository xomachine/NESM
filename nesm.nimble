
version       = "0.1.0"
author        = "xomachine (Fomichev Dmitriy)"
description   = "NEST stands for Nim's Easy Serialization Tool. The macro allowing generation of serialization functions by one line of code!"
license       = "MIT"


requires "nim >= 0.14.2"

task tests, "Run autotests":
  let test_files = listFiles("tests")
  for file in test_files:
    exec("nim c --run -p:" & thisDir() & " " & file)

task docs, "Build documentation":
  exec("nim doc2 -p:" & thisDir() &
    " -o:index.html nesm.nim")
