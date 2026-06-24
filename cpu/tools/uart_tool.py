#!/usr/bin/env python3
"""UART communication tool for MineCPU.
Simulation mode: reads from/writes to files (for Icarus testbench).
Hardware mode: uses pyserial for real UART communication.

Usage:
  Simulation send:    python3 uart_tool.py sim send prog.bin
  Simulation receive: python3 uart_tool.py sim recv
  Hardware send:      python3 uart_tool.py hw send prog.bin -p COM3 -b 115200
  Hardware receive:   python3 uart_tool.py hw recv -p COM3 -b 115200
  Auto-detect baud:   python3 uart_tool.py hw detect -p COM3
"""
import sys, argparse, struct, time, os

# ── Simulation mode (file-based) ──────────────────────────────

def sim_send(bin_path, rx_file="uart_rx.dat"):
    """Write binary to a file that the testbench reads for UART RX injection."""
    with open(bin_path, 'rb') as f:
        data = f.read()
    with open(rx_file, 'wb') as f:
        f.write(data)
    print(f"SIM: {len(data)} bytes written to {rx_file}")


def sim_recv(tx_file="uart_tx.dat", timeout=10):
    """Read UART TX output from file (written by testbench $fwrite)."""
    if not os.path.exists(tx_file):
        print(f"SIM: waiting for {tx_file}...")
        t0 = time.time()
        while not os.path.exists(tx_file):
            if time.time() - t0 > timeout:
                print("SIM: timeout — no TX data received")
                return
            time.sleep(0.1)
    with open(tx_file, 'rb') as f:
        data = f.read()
    text = data.decode('utf-8', errors='replace')
    print(text, end='')


# ── Hardware mode (serial) ────────────────────────────────────

def hw_connect(port, baud):
    try:
        import serial
        return serial.Serial(port, baud, timeout=5)
    except ImportError:
        print("ERROR: pyserial not installed. Run: pip install pyserial")
        sys.exit(1)


def hw_send(bin_path, port, baud):
    ser = hw_connect(port, baud)
    with open(bin_path, 'rb') as f:
        data = f.read()
    print(f"HW: sending {len(data)} bytes on {port} @ {baud}...")
    ser.write(data)
    ser.close()
    print("HW: done")


def hw_recv(port, baud):
    ser = hw_connect(port, baud)
    print(f"HW: listening on {port} @ {baud}... (Ctrl+C to stop)")
    try:
        while True:
            b = ser.read(1)
            if b:
                sys.stdout.write(b.decode('utf-8', errors='replace'))
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\nHW: stopped")
    ser.close()


def hw_detect(port):
    """Try common baud rates and see which one gets a valid response."""
    rates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    try:
        import serial
    except ImportError:
        print("ERROR: pyserial not installed")
        sys.exit(1)

    print(f"Auto-detecting baud rate on {port}...")
    for rate in rates:
        try:
            ser = serial.Serial(port, rate, timeout=0.5)
            # Send a test byte, expect echo or response
            ser.write(b'\r')
            time.sleep(0.2)
            resp = ser.read(10)
            if resp:
                print(f"  {rate:>8} baud — got response: {resp[:20]}")
                ser.close()
                return rate
            ser.close()
        except Exception as e:
            print(f"  {rate:>8} baud — error: {e}")
    print("No response at any baud rate.")
    return None


# ── CLI ───────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description='MineCPU UART tool')
    sp = p.add_subparsers(dest='mode')

    # Simulation
    sp_sim = sp.add_parser('sim', help='Simulation mode (file-based)')
    sp_sim_sub = sp_sim.add_subparsers(dest='action')
    sp_sim_send = sp_sim_sub.add_parser('send', help='Write binary to testbench input file')
    sp_sim_send.add_argument('file', help='Binary file to send')
    sp_sim_recv = sp_sim_sub.add_parser('recv', help='Read testbench output file')

    # Hardware
    sp_hw = sp.add_parser('hw', help='Hardware mode (serial port)')
    sp_hw.add_argument('-p', '--port', default='COM3', help='Serial port')
    sp_hw.add_argument('-b', '--baud', type=int, default=115200, help='Baud rate')
    sp_hw_sub = sp_hw.add_subparsers(dest='action')
    sp_hw_send = sp_hw_sub.add_parser('send')
    sp_hw_send.add_argument('file', help='Binary file to send')
    sp_hw_recv = sp_hw_sub.add_parser('recv')
    sp_hw_detect = sp_hw_sub.add_parser('detect')

    a = p.parse_args()

    if a.mode == 'sim':
        if a.action == 'send':
            sim_send(a.file)
        elif a.action == 'recv':
            sim_recv()
    elif a.mode == 'hw':
        if a.action == 'send':
            hw_send(a.file, a.port, a.baud)
        elif a.action == 'recv':
            hw_recv(a.port, a.baud)
        elif a.action == 'detect':
            hw_detect(a.port)

if __name__ == '__main__':
    main()
