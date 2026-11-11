#!/usr/bin/env python3
import argparse, os, socket, subprocess, threading

def copy(source, destination):
    try:
        source_fd = source.fileno()
        destination_fd = destination.fileno()
        while True:
            data = os.read(source_fd, 65536)
            if not data: break
            offset = 0
            while offset < len(data):
                offset += os.write(destination_fd, data[offset:])
    except (BrokenPipeError, ConnectionError, OSError):
        pass
    finally:
        try: destination.close()
        except OSError: pass

def serve(client, container, target_host, target_port):
    command = f'exec 3<>/dev/tcp/{target_host}/{target_port}; cat <&3 & reader=$!; cat >&3; wait $reader'
    process = subprocess.Popen(['docker','exec','-i',container,'/bin/bash','-lc',command], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    threading.Thread(target=copy,args=(client,process.stdin),daemon=True).start()
    threading.Thread(target=copy,args=(process.stdout,client),daemon=True).start()
    process.wait()
    try: client.close()
    except OSError: pass

def running(container):
    result=subprocess.run(['docker','inspect','-f','{{.State.Running}}',container],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    return result.returncode == 0 and result.stdout.strip() == 'true'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--container',required=True)
    parser.add_argument('--listen-host',required=True)
    parser.add_argument('--listen-port',required=True,type=int)
    parser.add_argument('--target-host',default='127.0.0.1')
    parser.add_argument('--target-port',required=True,type=int)
    args=parser.parse_args()
    listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    listener.bind((args.listen_host,args.listen_port)); listener.listen(16); listener.settimeout(1)
    while running(args.container):
        try: client,_=listener.accept()
        except socket.timeout: continue
        threading.Thread(target=serve,args=(client,args.container,args.target_host,args.target_port),daemon=True).start()
    listener.close()
if __name__ == '__main__': main()
