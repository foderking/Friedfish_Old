import strutils
import ../util

func expectMsg*(error: string, got: string, expect: string): string=
  ## Formats message to be printed to terminal after an error
  ## `error`: The error message formatted for the terminal
  ## `got`:   The incorrect result that was gotten
  ## `expect`: The correct result
  return """$#
$#: $#
$#: $#
""" % [errorMsg(error.capitalizeAscii), infoMsg("Got     "),
       got, infoMsg("Expected"), expect]

proc startTest*(msg: string)=
  echo ""
  #echo repeat('=',40)
  echo msg.toUpper
  echo repeat('=',20)

template assertVal*(value, expected, error: untyped, d: bool): untyped=
  ## helper function to help write testcases
  if d: echo infoMsg("Testing "&astToStr(value))
  let ans = value
  doAssert ans==expected, expectMsg(error, $(ans), $expected)

template assertBitboard*(value, expected, error: untyped, d: bool): untyped=
  ## helper function to help write testcases
  if d: echo infoMsg("\rTesting "&astToStr(value))
  let ans = value
  doAssert ans==expected, expectMsg(error&"\n"&value.prettyBitboard&"\n\n"&expected.prettyBitboard,
                                    ans.toHex, expected.toHex)


template doTest*(msg: string, test: untyped): untyped=
  echo testMsg("TESTING "&msg)
  #echo testMsg(repeat('=', 10))
  test
  echo passMsg()

template doTest*(test: untyped, msg: string): untyped=
  echo testMsg("TESTING "&msg)
  #echo testMsg(repeat('=', 10))
  test
  echo passMsg()


#export util
