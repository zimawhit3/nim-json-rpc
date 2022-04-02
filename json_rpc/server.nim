import
  std/tables,
  chronos, websock/websock,
  ./router,
  ./jsonmarshal

export chronos, jsonmarshal, router

type
  RpcServer* = ref object of RootRef
    router*: RpcRouter

proc new(T: type RpcServer): T =
  T(router: RpcRouter.init())

proc newRpcServer*(): RpcServer {.deprecated.} = RpcServer.new()

template rpc*(server: RpcServer, path: string, body: untyped): untyped =
  server.router.rpc(path, body)
  
template erpc*(server: RpcServer, path: string, body: untyped): untyped =
  assert server.router.kind == RouterKind.WebSocket
  server.router.exposedRpc(path, body)

template hasMethod*(server: RpcServer, methodName: string): bool =
  server.router.hasMethod(methodName)

proc executeMethod*(server: RpcServer,
                    methodName: string,
                    args: JsonNode): Future[StringOfJson] =
  server.router.procs[methodName](args)

proc executeMethod*(server: RpcServer,
                    methodName: string,
                    session: WSSession,
                    args: JsonNode): Future[StringOfJson] =
  server.router.wsprocs[methodName](session, args)

# Wrapper for message processing

proc route*(server: RpcServer, line: string): Future[string] {.gcsafe.} =
  server.router.route(line)

proc route*(server: RpcServer, ws: WSSession, line: string): Future[string] {.gcsafe.} =
  server.router.route(ws, line)

# Server registration

proc register*(server: RpcServer, name: string, rpc: RpcProc) =
  ## Add a name/code pair to the RPC server.
  server.router.register(name, rpc)

proc register*(server: RpcServer, name: string, rpc: WsRpcProc) =
  ## Add a name/code pair to the RPC server.
  server.router.register(name, rpc)

proc unRegisterAll*(server: RpcServer) =
  # Remove all remote procedure calls from this server.
  server.router.clear
