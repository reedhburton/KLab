#!/usr/bin/env python3
"""Prove native NetBSD/OpenBSD networking and key-authenticated SSH."""
import argparse, os, select, shlex, socket, subprocess, tempfile, time
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

def free_port():
    with socket.socket() as s: s.bind(('127.0.0.1',0)); return s.getsockname()[1]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--family',choices=('netbsd','openbsd','freebsd','dragonfly'),required=True); ap.add_argument('--arch',choices=('x86_64','i386','aarch64'),required=True)
    ap.add_argument('--disk',required=True,type=Path); ap.add_argument('--format',choices=('raw','qcow2'),required=True); ap.add_argument('--log',required=True,type=Path); ap.add_argument('--password',default='')
    ap.add_argument('--firmware',default='/usr/share/qemu-efi-aarch64/QEMU_EFI.fd',type=Path); ap.add_argument('--timeout',type=int,default=300)
    ap.add_argument('--netbsd-single-user',action='store_true',help='boot NetBSD aarch64 single-user for module validation')
    ap.add_argument('--cdrom',type=Path,help='attach a read-only ISO for guest validation inputs')
    ap.add_argument('--upload',action='append',default=[],metavar='LOCAL:REMOTE',help='copy a host file before the remote command')
    ap.add_argument('--remote-command',default='',help='additional root command to execute after SSH is ready')
    ap.add_argument('--expect',default='',help='marker required in the additional command output')
    args=ap.parse_args()
    args.log.parent.mkdir(parents=True,exist_ok=True); overlay=args.log.with_suffix('.ssh-overlay.qcow2'); overlay.unlink(missing_ok=True)
    subprocess.run(['qemu-img','create','-q','-f','qcow2','-F',args.format,'-b',str(args.disk.resolve()),str(overlay)],check=True)
    sockpath=str(Path(tempfile.gettempdir())/f'klab-bsd-ssh-{os.getpid()}.sock')
    try: os.unlink(sockpath)
    except FileNotFoundError: pass
    port=free_port(); qemu='qemu-system-aarch64' if args.arch=='aarch64' else ('qemu-system-i386' if args.arch=='i386' and args.family=='freebsd' else 'qemu-system-x86_64')
    if args.arch=='aarch64':
        smp='1' if args.family=='netbsd' else '2'
        cmd=[qemu,'-machine','virt','-cpu','cortex-a57','-m','1536M','-smp',smp,'-bios',str(args.firmware.resolve()),'-drive',f'file={overlay},format=qcow2,if=none,id=target','-device','virtio-blk-pci,drive=target']; iface='vio0' if args.family=='openbsd' else 'vioif0'; nic='virtio-net-pci'
    else:
        cmd=[qemu,'-enable-kvm','-cpu','host','-machine','pc','-m','1024M','-smp','2','-drive',f'file={overlay},format=qcow2,if=virtio','-boot','c']; iface='em0' if args.family in ('openbsd','freebsd','dragonfly') else 'wm0'; nic='e1000'
    if args.cdrom:
        if args.arch == 'aarch64':
            cmd += ['-drive',f'file={args.cdrom.resolve()},format=raw,if=none,id=klabsrc,readonly=on','-device','virtio-blk-pci,drive=klabsrc']
        else:
            cmd += ['-drive',f'file={args.cdrom.resolve()},media=cdrom,readonly=on']
    cmd += ['-nographic','-serial',f'unix:{sockpath},server=on,wait=off','-monitor','none','-netdev',f'user,id=klabnet,restrict=on,hostfwd=tcp:127.0.0.1:{port}-10.0.2.15:22','-device',f'{nic},netdev=klabnet','-no-reboot']
    keys=tempfile.TemporaryDirectory(prefix='klab-bsd-ssh-'); key=Path(keys.name)/'id_ed25519'; subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)],check=True); pub=key.with_suffix('.pub').read_text().strip()
    proc=subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE); serial=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    try:
        end=time.monotonic()+15
        while True:
            try: serial.connect(sockpath); break
            except OSError:
                if time.monotonic()>=end: raise
                time.sleep(.05)
        with args.log.open('wb') as log:
            single_user_ready=False
            if args.family=='netbsd' and args.arch=='aarch64' and args.netbsd_single_user:
                wait_for(serial,log,b'Press return to boot now',60); serial.sendall(b' ')
                wait_for(serial,log,b'> ',15); serial.sendall(b'boot netbsd -s\r')
                wait_for(serial,log,b'Enter pathname of shell or RETURN for /bin/sh:',args.timeout); serial.sendall(b'\r')
                wait_for(serial,log,b'# ',45); serial.sendall(b'/sbin/mount -u -w /; x=KLAB_; echo ${x}SINGLE_USER_OK\r')
                wait_for(serial,log,b'\r\nKLAB_SINGLE_USER_OK\r\n',30); single_user_ready=True
            elif args.family=='freebsd' and args.arch=='i386':
                wait_for(serial,log,b'Autoboot in',60); serial.sendall(b' 5')
                wait_for(serial,log,b'Serial primary',20); serial.sendall(b'\r')
            elif args.family=='dragonfly':
                wait_for(serial,log,b'Booting in 10 seconds',45); serial.sendall(b' ')
                wait_for(serial,log,b'Countdown halted',10); serial.sendall(b'9')
                wait_for(serial,log,b'OK ',10)
                for c in (b'set console=comconsole\r',b'boot\r'):
                    for b in c: serial.send(bytes((b,))); time.sleep(.02)
                    if c.startswith(b'set '): wait_for(serial,log,b'OK ',10)
            elif args.family=='netbsd' and args.arch=='x86_64':
                wait_for(serial,log,b'SPACE to stop countdown',30); serial.sendall(b' ')
                wait_for(serial,log,b'Option: [1]:',10); serial.sendall(b'3\r')
                wait_for(serial,log,b'> ',10); serial.sendall(b'consdev com0\r')
                wait_for(serial,log,b'> ',10); serial.sendall(b'boot\r')
            prompt=(b'root@:~ # ' if args.family=='dragonfly' else (b'root@freebsd' if args.family=='freebsd' else (b'klabarm# ' if args.family=='openbsd' and args.arch=='aarch64' else (b'klab# ' if args.family=='openbsd' else (b'netbsd# ' if args.arch=='x86_64' else b'# ')))))
            if not single_user_ready:
                wait_for(serial,log,b'login:',args.timeout); serial.sendall(b'root\r')
                if args.password:
                    wait_for(serial,log,b'Password:',20); serial.sendall(args.password.encode()+b'\r')
                wait_for(serial,log,prompt,45)
            quoted=shlex.quote(pub)
            if args.family=='openbsd': setup=f"ifconfig {iface} 10.0.2.15 netmask 255.255.255.0 up; route -n add default 10.0.2.2 >/dev/null 2>&1 || true; mkdir -p /root/.ssh; printf '%s\\n' {quoted} > /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; rcctl -f restart sshd"
            elif args.family in ('freebsd','dragonfly'): setup=f"ifconfig {iface} inet 10.0.2.15 netmask 255.255.255.0 up; route add default 10.0.2.2 >/dev/null 2>&1 || true; mkdir -p /root/.ssh; printf '%s\\n' {quoted} > /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; ssh-keygen -A >/dev/null 2>&1; service sshd onestop >/dev/null 2>&1 || true; /usr/sbin/sshd -D -e -o PermitRootLogin=yes -o PasswordAuthentication=no >/tmp/klab-sshd.log 2>&1 & true"
            else: setup=f"ifconfig {iface} inet 10.0.2.15 netmask 255.255.255.0 up; route add default 10.0.2.2 >/dev/null 2>&1 || true; mkdir -p /root/.ssh; printf '%s\\n' {quoted} > /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; ssh-keygen -A >/dev/null 2>&1; /etc/rc.d/sshd restart >/dev/null 2>&1 || /usr/sbin/sshd"
            setup_command=setup+"; x=KLAB_; echo ${x}SSH_SETUP_OK"
            if args.family=='dragonfly':
                setup_command='/bin/sh -c '+shlex.quote(setup_command)
            setup_bytes=(setup_command+"\r").encode()
            if args.family in ('freebsd','dragonfly'):
                for byte in setup_bytes:
                    serial.send(bytes((byte,))); time.sleep(.015)
            else:
                serial.sendall(setup_bytes)
            wait_for(serial,log,b'\r\nKLAB_SSH_SETUP_OK\r\n',90)
            ssh=['ssh','-i',str(key),'-p',str(port),'-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null','-o','ConnectTimeout=5','root@127.0.0.1','uname -s; printf KLAB_BSD_SSH_OK']; sshlog=args.log.with_suffix('.ssh-client.log'); success=False
            for _ in range(30):
                result=subprocess.run(ssh,stdout=subprocess.PIPE,stderr=subprocess.STDOUT); sshlog.write_bytes(result.stdout)
                if result.returncode==0 and b'KLAB_BSD_SSH_OK' in result.stdout: success=True; break
                time.sleep(2)
            if not success: raise RuntimeError(f'key-authenticated SSH failed; see {sshlog}')
            for spec in args.upload:
                local,sep,remote_path=spec.partition(':')
                if not sep or not local or not remote_path:
                    raise ValueError(f'invalid --upload value: {spec!r}')
                scp=['scp','-O','-q','-i',str(key),'-P',str(port),'-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null',local,f'root@127.0.0.1:{remote_path}']
                result=subprocess.run(scp,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
                if result.returncode != 0:
                    raise RuntimeError(f'upload failed for {spec}: {result.stdout.decode(errors="replace")}')
            if args.remote_command:
                remote=ssh[:-1]+[args.remote_command]
                remote_log=args.log.with_suffix('.remote.log')
                result=subprocess.run(remote,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
                remote_log.write_bytes(result.stdout)
                expected=args.expect.encode()
                if result.returncode != 0 or (expected and expected not in result.stdout):
                    raise RuntimeError(f'remote validation command failed; see {remote_log}')
                log.write(b'\nKLAB_BSD_REMOTE_COMMAND_OK\n'); log.flush()
            log.write(b'\nKLAB_BSD_SSH_OK\n'); log.flush()
        print('KLAB_BSD_SSH_OK')
    finally:
        serial.close(); proc.terminate()
        try: proc.wait(timeout=10)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
        err=proc.stderr.read() if proc.stderr else b''
        if err and args.log.exists():
            with args.log.open('ab') as log: log.write(b'\nQEMU_STDERR:\n'+err)
        keys.cleanup()
        try: os.unlink(sockpath)
        except FileNotFoundError: pass
if __name__=='__main__': main()
