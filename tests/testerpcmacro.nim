import unittest, json, chronicles, options
import ../json_rpc/rpcserver, ./helpers
import websock/websock

type
  # some nested types to check object parsing
  Test2 = object
    x: array[0..2, int]
    y: string

  Test = object
    a: array[0..1, int]
    b: Test2

  MyObject = object
    a: int
    b: Test
    c: float

  MyOptional = object
    maybeInt: Option[int]

  MyOptionalNotBuiltin = object
    val: Option[Test2]

let
  testObj = %*{
    "a": %1,
    "b": %*{
      "a": %[5, 0],
      "b": %*{
        "x": %[1, 2, 3],
        "y": %"test"
      }
    },
    "c": %1.23}

var s = newRpcWebSocketServer("127.0.0.1", 8888.Port(), exposed = true)

# RPC definitions
s.erpc("rpc.exposed"):
  let session = type(ws) is WSSession
  return %session

s.erpc("rpc.simplePath"):
  return %1

s.erpc("rpc.differentParams") do(a: int, b: string):
  return %[%a, %b]

s.erpc("rpc.arrayParam") do(arr: array[0..5, byte], b: string):
  var res = %arr
  res.add %b
  return %res

s.erpc("rpc.seqParam") do(a: string, s: seq[int]):
  var res = newJArray()
  res.add %a
  for item in s:
    res.add %int(item)
  return res

s.erpc("rpc.objParam") do(a: string, obj: MyObject):
  return %obj

s.erpc("rpc.returnTypeSimple") do(i: int) -> int:
  return i

s.erpc("rpc.returnTypeComplex") do(i: int) -> Test2:
  return Test2(x: [1, i, 3], y: "test")

s.erpc("rpc.testReturns") do() -> int:
  return 1234

s.erpc("rpc.multiVarsOfOneType") do(a, b: string) -> string:
  return a & " " & b

s.erpc("rpc.optional") do(obj: MyOptional) -> MyOptional:
  return obj

s.erpc("rpc.optionalArg") do(val: int, obj: Option[MyOptional]) -> MyOptional:
  return if obj.isSome():
    obj.get()
  else:
    MyOptional(maybeInt: some(val))

s.erpc("rpc.optionalArg2") do(a, b: string, c, d: Option[string]) -> string:
  var ret = a & b
  if c.isSome: ret.add c.get()
  if d.isSome: ret.add d.get()
  return ret

type
  OptionalFields = object
    a: int
    b: Option[int]
    c: string
    d: Option[int]
    e: Option[string]

s.erpc("rpc.mixedOptionalArg") do(a: int, b: Option[int], c: string,
  d: Option[int], e: Option[string]) -> OptionalFields:

  result.a = a
  result.b = b
  result.c = c
  result.d = d
  result.e = e

s.erpc("rpc.optionalArgNotBuiltin") do(obj: Option[MyOptionalNotBuiltin]) -> string:
  return if obj.isSome:
    let val = obj.get.val
    if val.isSome:
      obj.get.val.get.y
    else:
      "Empty2"
  else:
    "Empty1"

type
  MaybeOptions = object
    o1: Option[bool]
    o2: Option[bool]
    o3: Option[bool]

s.erpc("rpc.optInObj") do(data: string, options: Option[MaybeOptions]) -> int:
  if options.isSome:
    let o = options.get
    if o.o1.isSome: result += 1
    if o.o2.isSome: result += 2
    if o.o3.isSome: result += 4

# Tests
suite "Server types":
  test "On macro registration":
    check s.hasMethod("rpc.exposed")
    check s.hasMethod("rpc.simplePath")
    check s.hasMethod("rpc.differentParams")
    check s.hasMethod("rpc.arrayParam")
    check s.hasMethod("rpc.seqParam")
    check s.hasMethod("rpc.objParam")
    check s.hasMethod("rpc.returnTypeSimple")
    check s.hasMethod("rpc.returnTypeComplex")
    check s.hasMethod("rpc.testReturns")
    check s.hasMethod("rpc.multiVarsOfOneType")
    check s.hasMethod("rpc.optionalArg")
    check s.hasMethod("rpc.mixedOptionalArg")
    check s.hasMethod("rpc.optionalArgNotBuiltin")
    check s.hasMethod("rpc.optInObj")

  test "exposed session":
    let 
        session = WSSession()
        r = waitFor s.executeMethod("rpc.exposed", session, %[])
    check r == "true"

  test "Simple paths":
    let 
        session = WSSession()
        r = waitFor s.executeMethod("rpc.simplePath", session, %[])
    check r == "1"

  test "Different param types":
    let
      inp = %[%1, %"abc"]
      session = WSSession()
      r = waitFor s.executeMethod("rpc.differentParams", session, inp)
    check r == inp

  test "Array parameters":
    let 
        session = WSSession()
        r1 = waitfor s.executeMethod("rpc.arrayParam", session, %[%[1, 2, 3], %"hello"])
    var ckR1 = %[1, 2, 3, 0, 0, 0]
    ckR1.elems.add %"hello"
    check r1 == ckR1

  test "Seq parameters":
    let 
        session = WSSession()
        r2 = waitfor s.executeMethod("rpc.seqParam", session, %[%"abc", %[1, 2, 3, 4, 5]])
    var ckR2 = %["abc"]
    for i in 0..4: ckR2.add %(i + 1)
    check r2 == ckR2

  test "Object parameters":
    let 
        session = WSSession()
        r = waitfor s.executeMethod("rpc.objParam", session, %[%"abc", testObj])
    check r == testObj

  test "Simple return types":
    let
      session = WSSession()
      inp = %99
      r1 = waitfor s.executeMethod("rpc.returnTypeSimple", session, %[%inp])
    check r1 == inp

  test "Complex return types":
    let
      session = WSSession()
      inp = 99
      r1 = waitfor s.executeMethod("rpc.returnTypeComplex", session, %[%inp])
    check r1 == %*{"x": %[1, inp, 3], "y": "test"}

  test "Option types":
    let
      inp1 = MyOptional(maybeInt: some(75))
      inp2 = MyOptional()
      session = WSSession()
      r1 = waitfor s.executeMethod("rpc.optional", session, %[%inp1])
      r2 = waitfor s.executeMethod("rpc.optional", session, %[%inp2])
    check r1 == %inp1
    check r2 == %inp2

  test "Return statement":
    let 
        session = WSSession()
        r = waitFor s.executeMethod("rpc.testReturns", session, %[])
    check r == %1234

  test "Runtime errors":
    let session = WSSession()
    expect ValueError:
      # root param not array
      discard waitfor s.executeMethod("rpc.arrayParam", session, %"test")
    expect ValueError:
      # too big for array
      discard waitfor s.executeMethod("rpc.arrayParam", session, %[%[0, 1, 2, 3, 4, 5, 6], %"hello"])
    expect ValueError:
      # wrong sub parameter type
      discard waitfor s.executeMethod("rpc.arrayParam", session, %[%"test", %"hello"])
    expect ValueError:
      # wrong param type
      discard waitFor s.executeMethod("rpc.differentParams", session, %[%"abc", %1])

  test "Multiple variables of one type":
    let 
        session = WSSession()
        r = waitfor s.executeMethod("rpc.multiVarsOfOneType", session, %[%"hello", %"world"])
    check r == %"hello world"

  test "Optional arg":
    let
      int1 = MyOptional(maybeInt: some(75))
      int2 = MyOptional(maybeInt: some(117))
      session = WSSession()
      r1 = waitFor s.executeMethod("rpc.optionalArg", session, %[%117, %int1])
      r2 = waitFor s.executeMethod("rpc.optionalArg", session, %[%117])
      r3 = waitFor s.executeMethod("rpc.optionalArg", session, %[%117, newJNull()])
    check r1 == %int1
    check r2 == %int2
    check r3 == %int2

  test "Optional arg2":
    let 
        session = WSSession()
        r1 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B"])
    check r1 == %"AB"

    let r2 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", newJNull()])
    check r2 == %"AB"

    let r3 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", newJNull(), newJNull()])
    check r3 == %"AB"

    let r4 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", newJNull(), %"D"])
    check r4 == %"ABD"

    let r5 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", %"C", %"D"])
    check r5 == %"ABCD"

    let r6 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", %"C", newJNull()])
    check r6 == %"ABC"

    let r7 = waitFor s.executeMethod("rpc.optionalArg2", session, %[%"A", %"B", %"C"])
    check r7 == %"ABC"

  test "Mixed optional arg":
    let session = WSSession()
    var ax = waitFor s.executeMethod("rpc.mixedOptionalArg", session, %[%10, %11, %"hello", %12, %"world"])
    check ax == %OptionalFields(a: 10, b: some(11), c: "hello", d: some(12), e: some("world"))
    var bx = waitFor s.executeMethod("rpc.mixedOptionalArg", session, %[%10, newJNull(), %"hello"])
    check bx == %OptionalFields(a: 10, c: "hello")

  test "Non-built-in optional types":
    let
      session = WSSession()
      t2 = Test2(x: [1, 2, 3], y: "Hello")
      testOpts1 = MyOptionalNotBuiltin(val: some(t2))
      testOpts2 = MyOptionalNotBuiltin()
    var r = waitFor s.executeMethod("rpc.optionalArgNotBuiltin", session, %[%testOpts1])
    check r == %t2.y
    var r2 = waitFor s.executeMethod("rpc.optionalArgNotBuiltin", session, %[])
    check r2 == %"Empty1"
    var r3 = waitFor s.executeMethod("rpc.optionalArgNotBuiltin", session, %[%testOpts2])
    check r3 == %"Empty2"

  test "Manually set up JSON for optionals":
    # Check manual set up json with optionals
    let 
        session = WSSession()
        opts1 = parseJson("""{"o1": true}""")
    var r1 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts1])
    check r1 == %1
    let opts2 = parseJson("""{"o2": true}""")
    var r2 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts2])
    check r2 == %2
    let opts3 = parseJson("""{"o3": true}""")
    var r3 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts3])
    check r3 == %4
    # Combinations
    let opts4 = parseJson("""{"o1": true, "o3": true}""")
    var r4 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts4])
    check r4 == %5
    let opts5 = parseJson("""{"o2": true, "o3": true}""")
    var r5 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts5])
    check r5 == %6
    let opts6 = parseJson("""{"o1": true, "o2": true}""")
    var r6 = waitFor s.executeMethod("rpc.optInObj", session, %[%"0x31ded", opts6])
    check r6 == %3

s.stop()
waitFor s.closeWait()
