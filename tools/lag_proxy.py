#!/usr/bin/env python3
"""A UDP relay that makes a local connection behave like a real internet one.

Players connect to the relay instead of the host. Every packet, in both directions, is
delayed by `delay` ms plus random jitter and dropped with probability `loss`. ENet (which
Godot uses) runs over UDP, so this is a fair stand-in for home internet or rough Wi-Fi.

    python tools/lag_proxy.py --listen 7790 --host-port 7777 --delay 40 --jitter 10 --loss 0.02
"""
import argparse
import asyncio
import random


class Link(asyncio.DatagramProtocol):
    """One player's private socket to the host."""

    def __init__(self, relay, client_addr):
        self.relay = relay
        self.client_addr = client_addr
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        self.relay.later(lambda: self.relay.front.sendto(data, self.client_addr))


class Relay(asyncio.DatagramProtocol):
    def __init__(self, host_addr, delay, jitter, loss):
        self.host_addr = host_addr
        self.delay = delay / 1000.0
        self.jitter = jitter / 1000.0
        self.loss = loss
        self.links = {}
        self.front = None
        self.stats = {"forwarded": 0, "dropped": 0}

    def connection_made(self, transport):
        self.front = transport

    def later(self, send):
        if random.random() < self.loss:
            self.stats["dropped"] += 1
            return
        self.stats["forwarded"] += 1
        wait = max(0.0, self.delay + random.uniform(-self.jitter, self.jitter))
        asyncio.get_running_loop().call_later(wait, send)

    def datagram_received(self, data, addr):
        link = self.links.get(addr)
        if link is None:
            loop = asyncio.get_running_loop()
            link = Link(self, addr)
            self.links[addr] = link
            loop.create_task(loop.create_datagram_endpoint(lambda: link, remote_addr=self.host_addr))
        self.later(lambda: link.transport and link.transport.sendto(data))


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, default=7790)
    ap.add_argument("--host-port", type=int, default=7777)
    ap.add_argument("--delay", type=float, default=40.0, help="one-way delay in ms")
    ap.add_argument("--jitter", type=float, default=10.0, help="+/- ms")
    ap.add_argument("--loss", type=float, default=0.02, help="drop chance per packet, 0-1")
    ap.add_argument("--seconds", type=float, default=120.0)
    a = ap.parse_args()
    loop = asyncio.get_running_loop()
    relay = Relay(("127.0.0.1", a.host_port), a.delay, a.jitter, a.loss)
    await loop.create_datagram_endpoint(lambda: relay, local_addr=("127.0.0.1", a.listen))
    print(f"relay :{a.listen} -> :{a.host_port}  delay {a.delay}+-{a.jitter} ms each way, loss {a.loss:.0%}", flush=True)
    await asyncio.sleep(a.seconds)
    total = relay.stats["forwarded"] + relay.stats["dropped"]
    print(f"relay done: {total} packets, {relay.stats['dropped']} dropped ({relay.stats['dropped'] / max(total, 1):.1%})", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
