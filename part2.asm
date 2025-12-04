; ====================================================================
; 27C64 EPROM Programmer (Combined Part I & Part II)
; HC11 (CT Lab) interface
; ====================================================================

; HC11 Register Addresses 
BASE_REG     EQU $1000      ; Base address for registers
PORTA        EQU $00        ; Port A - Used for A8-A12, CE, OE control
PORTB        EQU $04        ; Port B - Used for A0-A7 (Low Address Byte)
PORTC        EQU $03        ; Port C - Used for Data (D0-D7)
DDRC         EQU $07        ; Port C Direction Register

BAUD         EQU $2B        ; SCI Baud Rate Register
SCCR2        EQU $2D        ; SCI Control Register 2
SCSR         EQU $2E        ; SCI Status Register
SCDR         EQU $2F        ; SCI Data Register

HPRIO        EQU $3C        ; High Priority Interrupt Register (Mode Control)
STACK_TOP    EQU $00FF      ; Stack Pointer Initial Value

; PORTA CONTROL BIT MASK (Active Low Signals) 
INACT_CTRL   EQU $60        ; %01100000 -> PA5=1, PA6=1 (CE and OE HIGH - Inactive/Tri-state)
CE_LOW       EQU $D0        ; %11010000 -> PA5=0 (CE Low), PA6=1 (OE High) - For WRITE/PROGRAM
READ_MODE    EQU $9F        ; %10011111 -> PA5=0, PA6=0 (CE and OE LOW) - For READ/VERIFY

; DATA TO PROGRAM (25 Bytes: "Hello, 27C64 Programmer!")
PROGRAM_DATA:
             ORG $0050
             FCC 'Hello, 27C64 Programmer!' ; Total 25 bytes
END_DATA     EQU *
PROGRAM_COUNT EQU END_DATA - PROGRAM_DATA ; Should be 25 ($19)

; --------------------------------------------------------------------
; START OF MAIN PROGRAM EXECUTION
; --------------------------------------------------------------------
             ORG $0000
START:
             LDS #STACK_TOP     ; Initialize Stack Pointer
             LDX #BASE_REG      ; X points to register base ($1000)

             ; Set Mode: Normal Expanded Mode
             LDAA #$C0          
             STAA HPRIO,X

             ; Configure I/O Ports
             CLRA               
             STAA DDRC,X        ; DDRC=0 (Input) for initial Blank Check

             ; PORTA Setup: Initialize CE/OE inactive and A8-A12 low
             LDAA #INACT_CTRL   ; %01100000
             STAA PORTA,X       

             ; Initialize SCI 
             LDAA #$30          ; Set Baud Rate
             STAA BAUD,X
             LDAA #$0C          ; TE and RE enable
             STAA SCCR2,X

             JSR DELAY_LONG     ; Provide time for PC serial program to start/sync

             ; --- PROGRAMMER SEQUENCE ---

             JSR BLANK_CHECK    ; 1. Check if EPROM is blank ($FFh)
             BNE BLANK_ERROR    ; If not blank (Z=0), jump to error

             ; !!! NOTE: External VCC/VPP must be switched here !!!

             JSR PROGRAM_EPROM  ; 2. Program the 25 bytes
             
             ; !!! NOTE: External VCC/VPP must be switched back to 5V here !!!

             JSR VERIFY_PROGRAM ; 3. Read back and verify

             BNE VERIFY_FAIL    ; If verification failed (Z=0), jump to error

             LDAA #'S'          ; Send 'S' for Success
             JSR TRANSMIT_BYTE
             JMP FINISH         

BLANK_ERROR:
             LDAA #'E'          ; Send 'E' for Error/Not Blank
             JSR TRANSMIT_BYTE
             JMP FINISH

VERIFY_FAIL:
             LDAA #'F'          ; Send 'F' for Verification Failed
             JSR TRANSMIT_BYTE
             JMP FINISH

FINISH:
             SWI                ; End Program Execution

; --------------------------------------------------------------------
; SUBROUTINE: BLANK_CHECK (Reads 25 bytes and verifies all are $FFh)
; Returns: Z-flag set (Z=1) if blank, Z-flag clear (Z=0) if not blank
; --------------------------------------------------------------------
BLANK_CHECK:
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA               ; Save A, B, CCR
             PSHB
             PSHC
             PSHD

BC_LOOP:
             STAA PORTB,X       ; Set Address A0-A7

             ; Activate EPROM (CE Low, OE Low) - READ_MODE
             PSHD               ; Save D
             LDD PORTA,X
             ANDB #~READ_MODE    ; Mask to set CE/OE bits Low
             STAB PORTA,X
             PULD               ; Restore D

             ; Wait for t_ACC
             NOP
             NOP

             ; Read Data
             LDAA PORTC,X       ; Read Data into A
             
             ; Deactivate EPROM
             PSHD
             LDD PORTA,X
             ORB #INACT_CTRL    ; Set CE and OE High (Inactive)
             STAB PORTA,X
             PULD

             ; Check for $FFh
             CMPA #$FF
             BNE BC_NOT_BLANK   ; If any byte is NOT $FF, exit fail

             ; Loop Control
             INCA
             DECB
             BNE BC_LOOP

             ; Blank Check Success
             PULD
             PULC
             PULB
             PULA
             RTS                ; Z-flag set (due to final DECB)

BC_NOT_BLANK:
             ; Blank Check Failed
             PULD
             PULC
             PULB
             PULA
             CLRB               ; Clear B to ensure Z=0
             RTS

; --------------------------------------------------------------------
; SUBROUTINE: PROGRAM_EPROM (Writes PROGRAM_COUNT bytes)
; --------------------------------------------------------------------
PROGRAM_EPROM:
             LDY #PROGRAM_DATA  ; Y points to data buffer
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA
             PSHB
             PSHX               ; Save X (Base Reg)

             ; 1. Set Port C Direction to Output (DDRC = $FF)
             LDX #BASE_REG
             LDAA #$FF
             STAA DDRC,X       
             
PE_LOOP:
             ; 2. Set Address (A0-A7)
             STAA PORTB,X       ; Output A to PORTB (A0-A7)

             ; 3. Set Data
             LDAA 0,Y           ; Load data byte from buffer
             STAA PORTC,X       ; Output Data to PORTC (D0-D7)

             ; 4. Set Control Signals for Programming (CE Low, OE High, A8-A12 Low)
             PSHD
             LDD PORTA,X
             ANDB #~CE_LOW      ; PA5 Low (CE), PA6 High (OE)
             STAB PORTA,X
             PULD

             ; 5. Apply Program Pulse (t_PW approx 100 us)
             JSR DELAY_100US    ; Custom delay routine for t_PW

             ; 6. Deactivate Program (CE High, OE High)
             PSHD
             LDD PORTA,X
             ORB #INACT_CTRL    ; Set CE and OE High (Inactive)
             STAB PORTA,X
             PULD
             
             ; 7. Loop Control
             INCA               ; Increment Address Counter (A)
             INY                ; Increment Data Pointer (Y)
             DECB               ; Decrement Byte Counter (B)
             BNE PE_LOOP

             ; Restore Port C Direction to Input (DDRC = $00)
             LDX #BASE_REG
             CLRA
             STAA DDRC,X
             
             PULX
             PULB
             PULA
             RTS

; --------------------------------------------------------------------
; SUBROUTINE: VERIFY_PROGRAM (Reads back 25 bytes and compares to data)
; Returns: Z-flag set (Z=1) if verified, Z-flag clear (Z=0) if failed
; --------------------------------------------------------------------
VERIFY_PROGRAM:
             LDY #PROGRAM_DATA  ; Y points to data buffer
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA
             PSHB
             PSHX               ; Save X (Base Reg)
             PSHY               ; Save Y (Data Pointer)

VP_LOOP:
             ; Read EPROM Byte (Address set by A)
             STAA PORTB,X     ; Set Address A0-A7

             ; Activate EPROM (CE Low, OE Low) - READ_MODE
             PSHD             
             LDD PORTA,X      
             ANDB #~READ_MODE 
             STAB PORTA,X
             PULD             

             ; Wait for t_ACC
             NOP
             NOP

             ; Read Data
             LDAA PORTC,X     ; Read Data from EPROM into A
             
             ; Deactivate EPROM
             PSHD             
             LDD PORTA,X      
             ORB #INACT_CTRL  
             STAB PORTA,X
             PULD             

             ; Compare with Data Buffer
             CMPA 0,Y         ; Compare read data (A) with programmed data (Y)
             BNE VP_FAIL      ; If not equal, exit fail

             ; Loop Control
             INCA
             INY
             DECB
             BNE VP_LOOP

             ; Verification Success
             PULY
             PULX
             PULB
             PULA
             RTS              ; Z-flag set

VP_FAIL:
             ; Verification Failed
             PULY
             PULX
             PULB
             PULA
             CLRB             ; Clear B to ensure Z=0
             RTS


; --------------------------------------------------------------------
; GENERAL SUBROUTINES
; --------------------------------------------------------------------

; Subroutine: Transmit Byte via Serial (Data is in Acc A)
TRANSMIT_BYTE:
WAIT_TX_DONE:
             BRCLR SCSR,X #$80 WAIT_TX_DONE ; Wait for TDRE (Transmit Data Register Empty)
             STAA SCDR,X                    ; Send data byte
             RTS


; Subroutine: Delay Loop (Long)
DELAY_LONG: 
             PSHX
             LDX #$FFFF
DL_LOOP:
             DEX
             BNE DL_LOOP
             PULX
             RTS

; Subroutine: DELAY_100US (Approx 100 $\mu s$ for $t_{PW}$)
; Assuming E clock is 2 MHz (0.5 $\mu s$ per cycle).
DELAY_100US:
             PSHA
             LDAA #50        ; 50 loops * 4 cycles/loop = 200 cycles
DL_100_LOOP:   
             DECA            ; 1 cycle
             NOP             ; 1 cycle
             NOP             ; 1 cycle
             BNE DL_100_LOOP ; 1 cycle (3 cycles if jump not taken)
             PULA
             RTS