# HC11 EPROM Reader Bootloader
# Fully corrected version

import sys, getopt
import serial
import time

def main(argv):
    comport = ''
    s19file = ''
    loopback = False

    try:
        opts, arg = getopt.getopt(argv, "hlc:i:", ["port", "ifile="])
    except getopt.GetoptError:
        print('HC11_BL -c <COM_port> -i <s19_inputfile>')
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print('HC11_BL -c <COM_port> -i <s19_inputfile>')
            sys.exit()
        elif opt == '-l':
            loopback = True
        elif opt in ("-c", "--port"):
            comport = arg
        elif opt in ("-i", "--ifile"):
            s19file = arg

    print('HC11 Bootload Mode RAM Loader, fixed version')
    print('Using serial port:', comport)
    print('Parsing S19 file:', s19file)

    # ------------------------------------------------------------------
    # Open serial port
    # ------------------------------------------------------------------
    # Force disable all "Wait for Ready" checks (RTS/CTS and DSR/DTR)
    ser = serial.Serial(port=comport, baudrate=1200, timeout=6.5, rtscts=False, dsrdtr=False)

    # VERY IMPORTANT:
    # Clear input buffer BEFORE the HC11 begins executing the RAM program
    ser.reset_input_buffer()

    # ------------------------------------------------------------------
    # Prepare 256-byte RAM loader array
    # ------------------------------------------------------------------
    machine_code = bytearray(256)
    for i in range(256):
        machine_code[i] = 0

    # ------------------------------------------------------------------
    # Parse the S19 file
    # ------------------------------------------------------------------
    f = open(s19file)
    line = f.readline()

    while line:
        if line.startswith("S1"):
            bcount = int(line[2:4], 16)
            dcount = bcount - 3
            address = int(line[4:8], 16)

            print("@", hex(address), end=":")

            data_index = 8
            for k in range(dcount):
                machine_code[address] = int(line[data_index:data_index+2], 16)
                byte = machine_code[address]
                print(f"{byte:02X}", end=" ")
                address += 1
                data_index += 2
        line = f.readline()
        if line:
            print()
    f.close()

    print("\nS19 parsing complete.\n")

    # ------------------------------------------------------------------
    # Wait for user to reset HC11 board
    # ------------------------------------------------------------------
    print('Press RESET on the HC11 board now.')
    input('Press ENTER after resetting the HC11...')

    time.sleep(0.5)

    # ------------------------------------------------------------------
    # Send 0xFF sync and 256-byte RAM loader
    # ------------------------------------------------------------------
    print("Sending bootloader sync and machine code...")
    ser.write(b"\xFF")

    # Wait briefly for HC11 baud autodetect
    time.sleep(0.1)

    ser.write(machine_code)

    # Give HC11 time to start executing the uploaded code
    time.sleep(0.15)

    #ser.close()
    #ser.baudrate = 9600
    #ser.open()

    # ------------------------------------------------------------------
    # EPROM READ SECTION – Read 25 bytes from HC11
    # ------------------------------------------------------------------
    print("\nWaiting for EPROM data from HC11...")

    ser.timeout = 2.0
    EPROM_LIMIT = 25
    eprom_data = []

    for i in range(EPROM_LIMIT):
        data = ser.read(1)
        if data:
            eprom_data.append(data[0])
        else:
            print(f"\nERROR: Timeout at byte {i}, address {i:02X}")
            break

    # ------------------------------------------------------------------
    # Display Results
    # ------------------------------------------------------------------
    if len(eprom_data) == EPROM_LIMIT:
        print("\nEPROM Read Complete!\n")
        print("ADDR | HEX DATA (8 bytes)             | ASCII")
        print("-----|--------------------------------|---------")

        for base in range(0, EPROM_LIMIT, 8):
            chunk = eprom_data[base:base+8]
            hexpart = ' '.join(f'{b:02X}' for b in chunk).ljust(24)
            ascpart = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
            print(f"{base:04X} | {hexpart} | {ascpart}")

        print("\nTotal bytes read:", EPROM_LIMIT)
    else:
        print("\nERROR: EPROM data incomplete.")
        print(f"Bytes received: {len(eprom_data)}")

    ser.close()
    print("\nDone. HC11 program executed successfully.")


# Correct __main__ check
if __name__ == "__main__":
    main(sys.argv[1:])
