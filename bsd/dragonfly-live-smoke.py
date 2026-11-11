#!/usr/bin/env python3
"""Boot an official DragonFly live image and prove serial userspace."""
import argparse, os, select, socket, subprocess, time
from pathlib import Path

def wait_for(sock, log, needle, timeout):
    end=time.monotonic()+timeout; buf=bytearray()
    while time.monotonic()<end:
        ready,_,_=select.select([sock],[],[],min(1,end-time.monotonic()))
        if not ready: continue
        chunk=sock.recv(65536)
        if not chunk: raise RuntimeError(f"serial closed waiting for {needle!r}")
        log.write(chunk); log.flush(); buf.extend(chunk)
        if needle in buf: return
        if len(buf)>2_000_000: del buf[:-1_000_000]
    raise TimeoutError(f"timed out waiting for {needle!r}")

def send_slow(sock, data, delay=.02):
    for byte in data:
        sock.send(bytes((byte,)))
        time.sleep(delay)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--image',required=True,type=Path); ap.add_argument('--log',required=True,type=Path)
    ap.add_argument('--overlay',required=True,type=Path); ap.add_argument('--qemu',default='qemu-system-x86_64')
    args=ap.parse_args(); args.log.parent.mkdir(parents=True,exist_ok=True); args.overlay.unlink(missing_ok=True)
    subprocess.run(['qemu-img','create','-q','-f','qcow2','-F','raw','-b',str(args.image.resolve()),str(args.overlay)],check=True)
    sockpath=str(args.overlay.with_suffix('.serial.sock'))
    try: os.unlink(sockpath)
    except FileNotFoundError: pass
    cmd=[args.qemu,'-enable-kvm','-cpu','host','-machine','pc','-m','1024M','-smp','2',
         '-drive',f'file={args.overlay},format=qcow2,if=ide','-boot','c','-nographic',
         '-serial',f'unix:{sockpath},server=on,wait=off','-monitor','none','-net','none','-no-reboot']
    proc=subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    serial=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    try:
        end=time.monotonic()+15
        while True:
            try: serial.connect(sockpath); break
            except OSError:
                if time.monotonic()>=end: raise
                time.sleep(.05)
        with args.log.open('wb') as log:
            wait_for(serial,log,b'Booting in 10 seconds',45); serial.sendall(b' ')
            wait_for(serial,log,b'Countdown halted',10); serial.sendall(b'9')
            wait_for(serial,log,b'OK ',10); send_slow(serial,b'set console=comconsole\r')
            wait_for(serial,log,b'OK ',10); send_slow(serial,b'boot\r')
            wait_for(serial,log,b'login: ',180); serial.sendall(b'root\r')
            wait_for(serial,log,b'root@:~ # ',30)
            serial.sendall(b"uname -a; uname -m; printf '\\113\\114\\101\\102_DRAGONFLY_USERSPACE_OK\\n'\r")
            wait_for(serial,log,b'\r\nKLAB_DRAGONFLY_USERSPACE_OK\r\n',30)
            wait_for(serial,log,b'root@:~ # ',10)
        print('KLAB_DRAGONFLY_USERSPACE_OK')
    finally:
        serial.close(); proc.terminate()
        try: proc.wait(timeout=10)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
        err=proc.stderr.read() if proc.stderr else b''
        if err and args.log.exists():
            with args.log.open('ab') as log: log.write(b'\nQEMU_STDERR:\n'+err)
        try: os.unlink(sockpath)
        except FileNotFoundError: pass
if __name__=='__main__': main()
