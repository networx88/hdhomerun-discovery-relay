#!/usr/bin/python3
"""Relay validated HDHomeRun discovery only; video never passes here."""
import argparse
import concurrent.futures
import ipaddress
import logging
import socket
import struct
import threading
import zlib


def valid_packet(data, kind):
    return (8 <= len(data) <= 4096
            and struct.unpack('!HH', data[:4]) == (kind, len(data) - 8)
            and zlib.crc32(data[:-4]) == struct.unpack('<I', data[-4:])[0])


def checksum(data):
    if len(data) % 2:
        data += b'\0'
    total = sum(struct.unpack('!%dH' % (len(data) // 2), data))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return (~total) & 65535


def response_packet(payload, tuner, client, port):
    source, destination = socket.inet_aton(tuner), socket.inet_aton(client)
    udp = struct.pack('!HHHH', 65001, port, 8 + len(payload), 0) + payload
    pseudo = source + destination + struct.pack('!BBH', 0, 17, len(udp))
    udp_sum = checksum(pseudo + udp) or 65535
    udp = udp[:6] + struct.pack('!H', udp_sum) + udp[8:]
    header = struct.pack('!BBHHHBBH4s4s', 69, 0, 20 + len(udp), 0, 0, 64, 17, 0, source, destination)
    header = header[:10] + struct.pack('!H', checksum(header)) + header[12:]
    return header + udp


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--interface', required=True)
    parser.add_argument('--network', required=True)
    parser.add_argument('--gateway', required=True)
    parser.add_argument('--tuner', required=True)
    parser.add_argument('--upstream', default=None)
    args = parser.parse_args()
    network = ipaddress.IPv4Network(args.network)
    gateway = str(ipaddress.IPv4Address(args.gateway))
    tuner = str(ipaddress.IPv4Address(args.tuner))
    upstream_source = str(ipaddress.IPv4Address(args.upstream or gateway))
    if ipaddress.IPv4Address(gateway) not in network:
        parser.error('gateway must belong to source network')
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, args.interface.encode() + b'\0')
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    listener.bind(('0.0.0.0', 65001))
    raw = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
    raw.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, args.interface.encode() + b'\0')
    slots = threading.BoundedSemaphore(16)

    def relay(data, client):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as upstream:
                upstream.bind((upstream_source, 0))
                upstream.settimeout(2)
                upstream.sendto(data, (tuner, 65001))
                response, peer = upstream.recvfrom(4096)
                if peer != (tuner, 65001) or not valid_packet(response, 3):
                    logging.warning('Rejected invalid tuner reply')
                    return
                raw.sendto(response_packet(response, tuner, client[0], client[1]), (client[0], 0))
                logging.info('Discovery reply tuner=%s client=%s:%s bytes=%s', tuner, *client, len(response))
        except (OSError, TimeoutError) as error:
            logging.warning('Discovery failed client=%s:%s error=%s', *client, error)
        finally:
            slots.release()

    logging.info('Listening interface=%s source=%s tuner=%s', args.interface, network, tuner)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
        while True:
            data, client = listener.recvfrom(4096)
            address = ipaddress.IPv4Address(client[0])
            if address not in network or client[0] == gateway or address in (network.network_address, network.broadcast_address):
                continue
            if valid_packet(data, 2) and slots.acquire(blocking=False):
                workers.submit(relay, data, client)


if __name__ == '__main__':
    main()
