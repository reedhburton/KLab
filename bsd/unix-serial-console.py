#!/usr/bin/env python3
"""Minimal raw terminal bridge for a QEMU Unix serial socket."""
import os, select, socket, sys, termios, time, tty
path=sys.argv[1]
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
end=time.monotonic()+15
while True:
    try: s.connect(path); break
    except OSError:
        if time.monotonic()>=end: raise
        time.sleep(.05)
fd=sys.stdin.fileno(); old=termios.tcgetattr(fd); tty.setraw(fd)
try:
    while True:
        ready,_,_=select.select([fd,s],[],[])
        if fd in ready:
            data=os.read(fd,65536)
            if not data: break
            s.sendall(data)
        if s in ready:
            data=s.recv(65536)
            if not data: break
            os.write(sys.stdout.fileno(),data)
finally:
    termios.tcsetattr(fd,termios.TCSADRAIN,old); s.close()
