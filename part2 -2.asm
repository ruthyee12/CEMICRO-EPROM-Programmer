; ====================================================================
; 27C64 EPROM Programmer (Combined Part I & Part II)
; HC11 (CT Lab) interface and sequential programming logic
; ====================================================================

; HC11 Register Addresses 
BASE_REG     EQU $1000      ; Base address for registers
PORTA        EQU $00        
PORTB        EQU $04        ; A0-A7 (Low Address Byte)
PORTC        EQU $03        ; D0-D7 (Data)
DDRC         EQU $07        ; Port C Direction Register

BAUD         EQU $2B        
SCCR2        EQU $2D        
SCSR         EQU $2E        
SCDR         EQU $2F        

HPRIO        EQU $3C        
STACK_TOP    EQU $00FF      

; PORTA CONTROL BIT MASK (A8-A12, CE, OE control)
INACT_CTRL   EQU $60        ; %01100000 -> PA5=1, PA6=1 (CE and OE HIGH - Inactive/Tri-state)
CE_LOW       EQU $D0        ; %11010000 -> PA5=0 (CE Low), PA6=1 (OE High) - For WRITE/PROGRAM
READ_MODE    EQU $9F        ; %10011111 -> PA5=0, PA6=0 (CE and OE LOW) - For READ/VERIFY

; DATA TO PROGRAM (25 Bytes: "Hello, 27C64 Programmer!")
PROGRAM_DATA:
             ORG $0050
             FCC 'Hello, 27C64 Programmer!' ; Total 25 bytes
END_DATA     EQU *
PROGRAM_COUNT EQU END_DATA - PROGRAM_DATA ; 25 ($19)

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
             LDAA #INACT_CTRL   ; Initialize CE/OE inactive and A8-A12 low
             STAA PORTA,X       

             ; Initialize SCI 
             LDAA #$30          ; Set Baud Rate
             STAA BAUD,X
             LDAA #$0C          ; TE and RE enable
             STAA SCCR2,X

             JSR DELAY_LONG     ; Wait for PC serial program to start/sync

             ; --- PROGRAMMER SEQUENCE ---

             JSR BLANK_CHECK    ; 1. Check if EPROM is blank ($FFh)
             BNE BLANK_ERROR    ; If not blank, report 'E' and halt

; !!! CRITICAL HARDWARE SWITCH POINT !!!
; The external Vcc/Vpp power supply must be switched to PROGRAMMING VOLTAGES
; (Vcc = +6.25V, Vpp = +12.75V) before the next instruction.
             JSR PROGRAM_EPROM  ; 2. Program the 25 bytes

; !!! CRITICAL HARDWARE SWITCH POINT !!!
; The external Vcc/Vpp power supply must be switched back to READ VOLTAGES
; (Vcc = +5V, Vpp = +5V) before the next instruction.
             JSR VERIFY_PROGRAM ; 3. Read back and verify

             BNE VERIFY_FAIL    ; If verification failed, report 'F'

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
; SUBROUTINE: BLANK_CHECK (Part I Read Logic - Checks for all $FFh)
; --------------------------------------------------------------------
BLANK_CHECK:
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA               ; Save registers A, B, CCR, D
             PSHB
             PSHC
             PSHD

BC_LOOP:
             STAA PORTB,X       ; Set Address A0-A7

             ; Activate EPROM (CE Low, OE Low) - READ_MODE
             PSHD               
             LDD PORTA,X
             ANDB #~READ_MODE    ; Set CE/OE bits Low (Read Mode)
             STAB PORTA,X
             PULD               

             NOP ; t_ACC delay
             NOP 

             LDAA PORTC,X       ; Read Data into A
             
             ; Deactivate EPROM (CE High, OE High)
             PSHD
             LDD PORTA,X
             ORB #INACT_CTRL    
             STAB PORTA,X
             PULD

             CMPA #$FF
             BNE BC_NOT_BLANK   ; If any byte is NOT $FF, exit fail

             INCA               ; Increment Address
             DECB               ; Decrement Counter
             BNE BC_LOOP

             PULD
             PULC
             PULB
             PULA
             RTS                ; Z-flag set (Success)

BC_NOT_BLANK:
             PULD
             PULC
             PULB
             PULA
             CLRB               
             RTS                ; Z-flag clear (Failure)

; --------------------------------------------------------------------
; SUBROUTINE: PROGRAM_EPROM (Part II Write Logic - Applies $100 \mu s$ pulse)
; --------------------------------------------------------------------
PROGRAM_EPROM:
             LDY #PROGRAM_DATA  ; Y points to data buffer
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA
             PSHB
             PSHX               

             ; 1. Set Port C Direction to Output (DDRC = $FF)
             LDX #BASE_REG
             LDAA #$FF
             STAA DDRC,X       
             
PE_LOOP:
             ; 2. Set Address (A0-A7)
             STAA PORTB,X       

             ; 3. Set Data
             LDAA 0,Y           
             STAA PORTC,X       ; Output Data to PORTC

             ; 4. Set Control Signals for Programming (CE Low, OE High)
             PSHD
             LDD PORTA,X
             ANDB #~CE_LOW      ; Set CE Low, OE High (Write Mode)
             STAB PORTA,X
             PULD

             ; 5. Apply Program Pulse (t_PW approx 100 us)
             JSR DELAY_100US    

             ; 6. Deactivate Program (CE High, OE High)
             PSHD
             LDD PORTA,X
             ORB #INACT_CTRL    
             STAB PORTA,X
             PULD
             
             ; 7. Loop Control
             INCA               
             INY                
             DECB               
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
; SUBROUTINE: VERIFY_PROGRAM (Part I Read Logic - Compares to Program Data)
; --------------------------------------------------------------------
VERIFY_PROGRAM:
             LDY #PROGRAM_DATA  ; Y points to data buffer
             CLRA               ; Address A = 00h
             LDAB #PROGRAM_COUNT ; Byte Counter B = 25
             PSHA
             PSHB
             PSHX               
             PSHY               

VP_LOOP:
             ; Read EPROM Byte (Address set by A)
             STAA PORTB,X     

             ; Activate EPROM (CE Low, OE Low) - READ_MODE
             PSHD             
             LDD PORTA,X      
             ANDB #~READ_MODE 
             STAB PORTA,X
             PULD             

             NOP ; t_ACC delay
             NOP

             LDAA PORTC,X     ; Read Data from EPROM into A
             
             ; Deactivate EPROM
             PSHD             
             LDD PORTA,X      
             ORB #INACT_CTRL  
             STAB PORTA,X
             PULD             

             ; Compare with Data Buffer
             CMPA 0,Y         
             BNE VP_FAIL      

             ; Loop Control
             INCA
             INY
             DECB
             BNE VP_LOOP

             PULY
             PULX
             PULB
             PULA
             RTS              ; Z-flag set (Success)

VP_FAIL:
             PULY
             PULX
             PULB
             PULA
             CLRB             
             RTS              ; Z-flag clear (Failure)


; --------------------------------------------------------------------
; GENERAL SUBROUTINES (Timing and SCI)
; --------------------------------------------------------------------

; Subroutine: Transmit Byte via Serial (Data is in Acc A)
TRANSMIT_BYTE:
WAIT_TX_DONE:
             BRCLR SCSR,X #$80 WAIT_TX_DONE 
             STAA SCDR,X                    
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
DELAY_100US:
             PSHA
             LDAA #50        ; 50 loops * 4 cycles/loop = 200 cycles
DL_100_LOOP:   
             DECA            
             NOP             
             NOP             
             BNE DL_100_LOOP 
             PULA
             RTS