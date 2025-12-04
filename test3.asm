; ====================================================================
; 27C64 EPROM Reader - Alternative Implementation (Reads 000h to 018h)
; Uses PORTB for A0-A7, PORTC for Data (Input), PORTA for Control/A8-A12
; ====================================================================

; HC11 Register Addresses 
BASE_REG    EQU $1000      ; Base address for registers
PORTA       EQU $00        ; Port A - Used for A8-A12, CE, OE control
PORTB       EQU $04        ; Port B - Used for A0-A7 (Low Address Byte)
PORTC       EQU $03        ; Port C - Used for Data (D0-D7)
DDRC        EQU $07        ; Port C Direction Register

BAUD        EQU $2B        ; SCI Baud Rate Register
SCCR2       EQU $2D        ; SCI Control Register 2
SCSR        EQU $2E        ; SCI Status Register
SCDR        EQU $2F        ; SCI Data Register

HPRIO       EQU $3C        ; High Priority Interrupt Register (Mode Control)
STACK_TOP   EQU $00FF      ; Stack Pointer Initial Value

; PORTA CONTROL BIT MASK (Active Low Signals) 
CE_BIT      EQU $20        ; %00100000 -> PA5 for CE
OE_BIT      EQU $40        ; %01000000 -> PA6 for OE
INACT_CTRL  EQU $60        ; %01100000 -> CE and OE are HIGH (Inactive)

; START
            ORG $0000
START:
            LDS #STACK_TOP      ; Initialize Stack Pointer

            LDX #BASE_REG       ; X points to register base ($1000)

            ; Set Mode: Set to Normal Expanded Mode for Port I/O flexibility 
            LDAA #$C0           
            STAA HPRIO,X

            ; Configure I/O Ports
            CLRA                
            STAA DDRC,X        


            ; PORTA Setup: A8-A12 are LOW (0), CE/OE are HIGH (Inactive)
            LDAA #INACT_CTRL    ; %01100000 -> PA5=1 (CE High), PA6=1 (OE High), A8-A12 (PA3-PA7) are controlled
            STAA PORTA,X        ; Initialize CE/OE inactive and A8-A12 low

            ; Initialize SCI 
            LDAA #$30           ; Set Baud Rate (e.g., 9600 baud)
            STAA BAUD,X
            LDAA #$0C           ; $0C = TE (Transmit Enable) and RE (Receive Enable)
            STAA SCCR2,X

            ; Wait for PC Setup 
            JSR DELAY_LONG      ; Provide time for PC serial program to start/sync

            ; Initialize Loop Control 
            CLRA                
            LDAB #25           

READ_LOOP:
            ; --- 1. Set Address (A0-A7) ---
            STAA PORTB,X        ; Output A to PORTB (A0-A7)

            ; --- 2. Activate EPROM (CE/OE Low) ---
            PSHA                ; Save A (address counter)
            LDAA PORTA,X
            ANDA #~INACT_CTRL   ; Mask $60 (CE/OE bits) with 0 -> %10011111 (OE and CE go LOW)
            STAA PORTA,X        ; EPROM now enabled, data is put on D0-D7

            ; --- Wait for EPROM Access Time (t_ACC) ---
            NOP                 ; Simple delay for required timing
            NOP                 ; A better delay would ensure t_ACC is met

            ; --- 3. Read Data ---
            LDAA PORTC,X        ; Read Data from EPROM D0-D7 into A
            JSR TRANSMIT_BYTE   ; Send Data to PC via SCI

            ; --- 4. Deactivate EPROM (CE/OE High) ---
            LDAA PORTA,X
            ORAA #INACT_CTRL    ; Set CE and OE High (Inactive)
            STAA PORTA,X
            PULA                ; Restore A (address counter)

            ; --- 5. Loop Control ---
            INCA                ; Increment Address Counter (A)
            DECB                ; Decrement Byte Counter (B)
            BNE READ_LOOP       ; Loop until 25 bytes are read

            SWI                 ; End Program Execution


; Subroutine: Transmit Byte via Serial (Data is in Acc A)
TRANSMIT_BYTE:
WAIT_TX_DONE:
            BRCLR SCSR,X #$80 WAIT_TX_DONE ; Wait for TDRE (Transmit Data Register Empty)
            STAA SCDR,X                    ; Send data byte
            RTS


; Subroutine: Delay Loop
DELAY_LONG: ; Simple delay
            PSHX
            LDX #$FFFF
DL_LOOP:
            DEX
            BNE DL_LOOP
            PULX
            RTS