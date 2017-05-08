
version       = "0.3.0"
author        = "xomachine (Fomichev Dmitriy)"
description   = "NESM stands for Nim's Easy Serialization Macro. The macro allowing generation of serialization functions by one line of code!"
license       = "MIT"
skipDirs      = @["tests"]

requires "nim >= 0.14.2"

task tests, "Run autotests":
  let test_files = listFiles("tests")
  for file in test_files:
    exec("nim c --run -d:debug -o:tmpfile -p:" & thisDir() & " " & file)
    rmFile("tmpfile")

task docs, "Build documentation":
  exec("nim doc2 -p:" & thisDir() &
    " -o:index.html nesm.nim")
