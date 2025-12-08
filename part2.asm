; EPROM Programmer - CEMICRO Project

BASE_REG    EQU $1000
PORTA       EQU $00
PORTC       EQU $03
PORTB       EQU $04
DDRC        EQU $07

SCSR        EQU $2E
SCDR        EQU $2F

OE_BIT      EQU $10        ; PA4 = Pin 22 
PGM_BIT     EQU $20        ; PA5 = Pin 27
CE_BIT      EQU $40        ; PA6 = Pin 20 
SAFE_MODE   EQU $70        

            ORG $0000
START:
            LDS #$00FF         
            LDX #BASE_REG      

            LDAA #SAFE_MODE
            STAA PORTA,X

            
            ; Write Data
            LDY #PATTERN       ; Y -> Data
            CLRA               ; A -> Address Offset (0-24)

NEXT_BYTE_LOOP:
            STAA PORTB,X       
            
            LDAB 0,Y
            STAB CURRENT_VAL
            
            CLR RETRY_COUNT   

PULSE_LOOP:
            INC RETRY_COUNT    ; ++n
            LDAB RETRY_COUNT
            CMPB #26           
            BEQ FAILURE_EXIT

            ; 1ms Program Pulse
            LDAA #$FF
            STAA DDRC,X        
            LDAA CURRENT_VAL
            STAA PORTC,X       

            ; Write Mode (CE=0, OE=1, PGM=1)
            LDAA PORTA,X
            ANDA #~CE_BIT
            ORAA #OE_BIT | PGM_BIT
            STAA PORTA,X

            ; Pulse PGM Low
            BCLR PORTA,X PGM_BIT
            JSR DELAY_1MS
            BSET PORTA,X PGM_BIT

            ; Verification
            CLR DDRC,X        
            
            ; Read Mode (CE=0, OE=0)
            BCLR PORTA,X (CE_BIT|OE_BIT)
            NOP
            LDAB PORTC,X      
            BSET PORTA,X (CE_BIT|OE_BIT) 

            CMPB CURRENT_VAL
            BEQ WRITE_SUCCESS
            BRA PULSE_LOOP     

WRITE_SUCCESS:
            ; 3ms * n
            LDAA #$FF         
            STAA DDRC,X
            LDAA CURRENT_VAL
            STAA PORTC,X

            ; Enable Write
            LDAA PORTA,X
            ANDA #~CE_BIT
            ORAA #OE_BIT | PGM_BIT
            STAA PORTA,X

            ; Start Pulse
            BCLR PORTA,X PGM_BIT

            ; Delay Loop (3ms x RetryCount)
            LDAB RETRY_COUNT
OP_LOOP:
            JSR DELAY_1MS
            JSR DELAY_1MS
            JSR DELAY_1MS
            DECB
            BNE OP_LOOP

            ; End Pulse
            BSET PORTA,X PGM_BIT
            CLR DDRC,X         

            ; Next Address
            INY
            LDAA PORTB,X     
            INCA
            CMPA TOTAL_BYTES
            BNE NEXT_BYTE_LOOP


            JSR DELAY_LONG     
            JSR SERIAL_DUMP
            SWI

FAILURE_EXIT:
            LDAA #'F'
            JSR TX_BYTE
            SWI

; Subroutines

SERIAL_DUMP:
            CLRA              
DUMP_LOOP:  STAA PORTB,X
            BCLR PORTA,X (CE_BIT|OE_BIT) 
            NOP
            LDAB PORTC,X
            BSET PORTA,X (CE_BIT|OE_BIT) 
            STAB SCDR,X       
WAIT_TX:    BRCLR SCSR,X #$80 WAIT_TX
            INCA
            CMPA TOTAL_BYTES
            BNE DUMP_LOOP
            RTS

TX_BYTE:    STAA SCDR,X
WAIT_TX2:   BRCLR SCSR,X #$80 WAIT_TX2
            RTS

DELAY_1MS:  PSHX
            LDX #666           
D1:         DEX
            BNE D1
            PULX
            RTS

DELAY_LONG: LDX #$FFFF        
DL:         DEX
            BNE DL
            RTS


            ORG $00D0
CURRENT_VAL RMB 1
RETRY_COUNT RMB 1
TOTAL_BYTES FCB $19           

PATTERN:    FCB $CA, $0C, $A0, $CA, $0C, $A0, $CA, $0C, $A0, $CA
            FCB $0C, $A0, $CA, $0C, $A0, $CA, $0C, $A0, $CA, $0C
            FCB $A0, $CA, $0C, $A0, $CA