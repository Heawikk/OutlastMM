"""
OLTogether relay server — no external dependencies.
"""

import asyncio
import itertools
import re
import socket
import sys
from collections import deque
from datetime import datetime

HOST = "0.0.0.0"
PORT = 7777

clients: dict = {}
id_counter = itertools.count(1)
_log_lines: deque = deque(maxlen=15)

_RST = "\033[0m"
_BLD = "\033[1m"
_DIM = "\033[2m"
_RED = "\033[31m"
_GRN = "\033[32m"
_YLW = "\033[33m"
_CYN = "\033[36m"
_WHT = "\033[97m"
_BCY = "\033[96m"

_ANSI = re.compile(r'\033\[[0-9;]*m')
_W    = 60  # total box width including borders


def _vis(s: str) -> int:
    return len(_ANSI.sub('', s))


def _server_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


_IP = _server_ip()


def _row(content: str) -> str:
    pad = _W - 4 - _vis(content)
    return f"{_BCY}│{_RST} {content}{' ' * max(0, pad)} {_BCY}│{_RST}"


def _resolve_nick(player_id: int, desired: str) -> str:
    """Return desired nick, suffixing _2/_3/... if already taken by another player."""
    if not desired or not desired.strip():
        return f"Player {player_id}"
    desired = desired.strip()[:24]  # cap length

    used = {info["nick"] for w, info in clients.items() if info["id"] != player_id}
    if desired not in used:
        return desired

    n = 2
    while True:
        candidate = f"{desired}_{n}"
        if candidate not in used:
            return candidate
        n += 1


def _draw() -> None:
    inner = _W - 2
    out   = ["\033[H\033[J"]

    title = "OLTogether Relay"
    tpad  = (inner - len(title)) // 2
    out.append(f"{_BCY}╭{'─' * inner}╮{_RST}")
    out.append(f"{_BCY}│{_RST}{' ' * tpad}{_BLD}{_WHT}{title}{_RST}"
               f"{' ' * (inner - tpad - len(title))}{_BCY}│{_RST}")
    out.append(f"{_BCY}├{'─' * inner}┤{_RST}")

    out.append(_row(f"{_CYN}Server State{_RST}  {_GRN}{_BLD}● Running{_RST}"))
    out.append(_row(f"{_CYN}Players{_RST}       {_YLW}{_BLD}{len(clients)}{_RST}"))
    out.append(_row(f"{_CYN}IP{_RST}            {_WHT}{_IP}{_RST}"))
    out.append(_row(f"{_CYN}Port{_RST}          {_WHT}{PORT}{_RST}"))

    out.append(f"{_BCY}├{'─' * inner}┤{_RST}")
    out.append(_row(f"{_BLD}{'Nick':<18}{'Address':<22}Since{_RST}"))
    out.append(_row(f"{_DIM}{'─' * (inner - 4)}{_RST}"))

    if clients:
        for info in clients.values():
            nick = info.get("nick") or f"Player {info['id']}"
            line = (f"{_YLW}{nick:<18}{_RST}"
                    f"{_CYN}{info['addr']:<22}{_RST}"
                    f"{_DIM}{info['since']}{_RST}")
            out.append(_row(line))
    else:
        out.append(_row(f"{_DIM}— waiting for players…{_RST}"))

    out.append(f"{_BCY}╰{'─' * inner}╯{_RST}")
    out.append("")

    for entry in _log_lines:
        out.append(entry)

    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()


def _log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    _log_lines.append(f"{_DIM}[{ts}]{_RST} {msg}")


async def _display_loop() -> None:
    while True:
        _draw()
        await asyncio.sleep(1.0)


async def broadcast(sender, data: bytes) -> None:
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


async def broadcast_all(data: bytes) -> None:
    dead = []
    for writer in list(clients):
        try:
            writer.write(data)
            await writer.drain()
        except Exception:
            dead.append(writer)
    for w in dead:
        await _remove_client(w)


async def _remove_client(writer) -> None:
    info = clients.pop(writer, None)
    if info is None:
        return
    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass
    pid  = info["id"]
    nick = info.get("nick") or f"Player {pid}"
    _log(f"{_RED}[-]{_RST} {nick} disconnected  ({info['addr']})")
    await broadcast(writer, f"{pid},DISCONNECT\n".encode())


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peername  = writer.get_extra_info("peername")
    addr      = f"{peername[0]}:{peername[1]}" if peername else "unknown"
    player_id = next(id_counter)
    clients[writer] = {
        "id":    player_id,
        "addr":  addr,
        "since": datetime.now().strftime("%H:%M:%S"),
        "nick":  None,
    }
    _log(f"{_GRN}[+]{_RST} Player {player_id} connected from {addr}")

    try:
        writer.write(f"HELLO,{player_id}\n".encode())
        for w, info in list(clients.items()):
            if w is writer:
                continue
            if info.get("nick"):
                writer.write(f"{info['id']},NICK,{info['nick']}\n".encode())
        await writer.drain()
    except Exception:
        await _remove_client(writer)
        return

    try:
        while True:
            line = await reader.readline()
            if not line:
                break

            text = line.decode(errors="replace").rstrip("\r\n")

            if text.startswith("PING,"):
                writer.write(b"PONG," + line[5:])
                await writer.drain()

            elif text.startswith("NICK,"):
                desired  = text[5:]
                resolved = _resolve_nick(player_id, desired)
                clients[writer]["nick"] = resolved
                nick_line = f"{player_id},NICK,{resolved}\n".encode()
                await broadcast_all(nick_line)
                _log(f"{_CYN}[N]{_RST} Player {player_id} → {_YLW}{resolved}{_RST}")

            else:
                await broadcast(writer, f"{player_id},".encode() + line)

    except (asyncio.IncompleteReadError, ConnectionResetError):
        pass
    finally:
        await _remove_client(writer)


async def main() -> None:
    server = await asyncio.start_server(handle_client, HOST, PORT)
    asyncio.create_task(_display_loop())
    _log(f"{_BCY}Listening on {_IP}:{PORT}{_RST}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
