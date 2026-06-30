"""
OLTogether relay server.
- Sends HELLO,<id> to each client when they connect so they know their own ID.
- Broadcasts each client's LOC packets to all others as <id>,LOC,...
- Broadcasts DISCONNECT,<id> when a client leaves.
"""

import asyncio
import itertools

HOST = "0.0.0.0"
PORT = 7777

clients: dict[asyncio.StreamWriter, int] = {}
id_counter = itertools.count(1)


async def broadcast(sender: asyncio.StreamWriter, data: bytes) -> None:
    dead = []
    for writer in list(clients):
        if writer is sender:
            continue
        try:
            writer.write(data)
            await writer.drain()
        except Exception:
            dead.append(writer)
    for w in dead:
        await _remove_client(w)


async def _remove_client(writer: asyncio.StreamWriter) -> None:
    player_id = clients.pop(writer, None)
    if player_id is None:
        return
    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass
    print(f"[-] Player {player_id} removed")
    await broadcast(writer, f"{player_id},DISCONNECT\n".encode())


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    addr      = writer.get_extra_info("peername")
    player_id = next(id_counter)
    clients[writer] = player_id
    print(f"[+] Player {player_id} connected from {addr}")

    # Tell this client their own ID immediately
    try:
        writer.write(f"HELLO,{player_id}\n".encode())
        await writer.drain()
    except Exception:
        await _remove_client(writer)
        return

    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            if line.startswith(b'PING,'):
                writer.write(b'PONG,' + line[5:])
                await writer.drain()
            else:
                # Forward as: SenderID,LOC,x,y,...
                await broadcast(writer, f"{player_id},".encode() + line)
    except (asyncio.IncompleteReadError, ConnectionResetError):
        pass
    finally:
        await _remove_client(writer)


async def main() -> None:
    server = await asyncio.start_server(handle_client, HOST, PORT)
    print(f"[server] OLTogether relay listening on {HOST}:{PORT}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
