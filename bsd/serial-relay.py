#!/usr/bin/env python3
"""Keep one QEMU serial connection while serving reconnecting local clients."""
import os, select, socket, sys, time
upath, ppath = sys.argv[1:]
def upstream():
    while True:
        s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        try: s.connect(upath); s.setblocking(False); return s
        except OSError: s.close(); time.sleep(.05)
try: os.unlink(ppath)
except FileNotFoundError: pass
listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); listener.bind(ppath); listener.listen(4); listener.setblocking(False)
up=upstream(); client=None
try:
    while True:
        reads=[listener,up]+([client] if client else [])
        ready,_,_=select.select(reads,[],[],1)
        if listener in ready:
            new,_=listener.accept(); new.setblocking(False)
            if client: client.close()
            client=new
        if up in ready:
            data=up.recv(65536)
            if not data: up.close(); up=upstream()
            elif client:
                try: client.sendall(data)
                except OSError: client.close(); client=None
        if client and client in ready:
            try: data=client.recv(65536)
            except OSError: data=b''
            if not data: client.close(); client=None
            else: up.sendall(data)
finally:
    if client: client.close()
    up.close(); listener.close()
    try: os.unlink(ppath)
    except FileNotFoundError: pass
