.globl _start

@ error code values
@ you can easily load these like: mov r0,#ERR_OP_UNDEFINED
.equ ERR_NONE, 0x00000000
.equ ERR_OP_OVERFLOW, 0x00000002
.equ ERR_OP_DIV_BY_ZERO, 0x00000003

@ constants for keeping track of calculator state
.equ STATE_INPUT_1, 0x0
.equ STATE_INPUT_2_OPERATION, 0x1	@ input 1 must have been a 								   number
.equ STATE_INPUT_2_OPERAND, 0x2		@ input 1 must have been an 							  operation
.equ STATE_INPUT_3, 0x3

@ uart constants
.equ ADDR_UART0, 0x101f1000
.equ RXFE, 0x10
.equ TXFF, 0x20
.equ OFFSET_UARTLCR_H, 0x02c
.equ OFFSET_FR, 0x018


_start:
	ldr	r0, =ADDR_UART0		@ r0 := 0x 101f 1000
	mov	sp, #0x12000		@ set up stack
	ldr	r1, =string_start	@ r1 = address of string_start
	bl	print_string		@ print string_start
	mov	r6, #STATE_INPUT_1	@ store our state in r6

main_loop:				@ determines state, loads string for input type
	ldr	r0, =ADDR_UART0		@ r0 := 0x 101f 1000
	cmp	r6, #STATE_INPUT_1	@ load string based on state
	ldreq	r1, =string_input_either
	beq	go			
	cmp	r6, #STATE_INPUT_2_OPERATION
	ldreq	r1, =string_input_operation
	beq	go
	cmp	r6, #STATE_INPUT_2_OPERAND
	ldreq	r1, =string_input_operand
	beq	go
	cmp	r6, #STATE_INPUT_3
	ldreq	r1, =string_input_operand

go:	bl	print_string		@ print what type of input we're 						  looking for
	ldr	r4, =buf		@ needed for input
	ldr	r5, =buf_end	@ needed for checking bounds of input
@ read, wait, 
ready:	ldr	r2,[r0,#OFFSET_FR]	@ load flag register
	and	r3,r2,#RXFE		@ mask non receive fifo empty bits
	cmp	r3, #0			@ r3 == 0?
	bne	ready			@ wait until ready
	ldr	r1,[r0]			@ r1 = value entered
wait:	ldr	r2,[r0,#OFFSET_FR]	@ r2 = UART flags reg
	and	r3,r2,#TXFF		@ mask non transmit fifo full bits
	cmp	r3,#0			@ r3 == 0?
	bne	wait			@ wait until finished transmitting
	
	str	r1,[r0]		@ echo typed character to screen

	cmp	r4, r5		@ at end of buffer?
	beq	line_done
	cmp	r1, #'\r'		@ r1 == '\r'? newline entered?
	bne	cont
	ldr	r2, =last		@ r2 = address of last
	ldr	r2, [r2]		@ r2 = mem[last]
	cmp	r2, #'q'		@ last char entered a q?
	beq	quit
	b	line_done

cont:	strb	r1, [r4]		@ store typed char at next pos in buffer
	add	r4, r4, #1		@ increment pointer to next byte in buffer
	ldr	r2, =last		@ save last typed character
	str	r1, [r2]		@ mem[last] = r1
	b	ready			@ keep going

line_done:	
	ldr	r0, =ADDR_UART0		
	bl	newline			@ print newline
	mov	r1, #0			@ r1 = 0
	strb	r1, [r4]		@ ensure null termination
	ldr	r0, =buf		@ r0 = address of buf
	bl	isNumber		@ see if what was entered was a number
	cmp	r0, #1			@ r0 == 1?
	bne	not_number		@ handle if not number

	@ Otherwise, it is a number
	cmp	r6, #STATE_INPUT_1	@ check our state
	moveq	r6, #STATE_INPUT_2_OPERATION	@ change it to the next state, we are now expecting operation
	ldreq	r0, =buf		@ r0 = address of buf
	bleq	toInt			@ convert to integer
	ldreq	r1, =_operandA		@ r1 = address of _operandA
	streq	r0, [r1]		@ store operand in _operandA
	beq	main_loop		@ get next input
	cmp	r6, #STATE_INPUT_2_OPERATION 	@ check our state
	bne	next				@ if ne check next state
	bl	handleUndefined		@ if this happens then operation 						  @is undefined
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop			@ start again

next:	cmp	r6, #STATE_INPUT_2_OPERAND	@ check if we're expecting an operand
	bne	next_s				@ if ne check next state
	ldreq	r0, =buf			@ if eq r0 = address of buf
	bleq	toInt				@ convert to int
	ldreq	r1, =_operandB		@ store operand in _operandB
	streq	r0, [r1]		@ store operand in _operandB
	moveq	r0, #0			@ r0 = 0
	ldreq	r1, =_operandA		@ r1 = address of _operandA
	streq	r0, [r1]		@ store 0 in _operandA
	bl	execute_input		@ execute unary operation
	mov	r6, #STATE_INPUT_1	@ Start again
	b	main_loop		@ start again

next_s:	cmp	r6, #STATE_INPUT_3	@ check if we're expecting an operand
	ldreq	r0, =buf		@ if eq r0 = addres of buf
	bleq	toInt			@ convert to int
	ldreq	r1, =_operandB		@ store operand in _operandB
	streq	r0, [r1]		@ store operand in _operandB
	bl	execute_input		@ execute binary operation
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop		@ start again

not_number:				@ if input was not a number
	ldr	r0, =buf		@ r0 = address of buf
	cmp	r6, #STATE_INPUT_1	@ check our state
	beq	nn_state_1		@ handle not a number for state 1
	cmp	r6, #STATE_INPUT_2_OPERATION	@ check our state
	beq	nn_state_2_operation		@ handle not a number for state 2 expecting operation
	cmp	r6, #STATE_INPUT_2_OPERAND	@ check our state
	beq	nn_state_2_operand		@ handle not a number for state 2 expecting operand
	b	nn_state_3			@ handle not a number for state 3

nn_state_1:
	bl	isNegate		@ check if the input is the operation negate
	cmp	r0, #1			@ r0 == 1?
	moveq	r6, #STATE_INPUT_2_OPERAND	@ if the input is a negate then we should expect an operand next
	ldreq	r1, =_operation		@ r1 = address of _operation
	moveq	r2, #'-'		@ if eq r2 = '-'
	streqb	r2, [r1]		@ store '-' in _operation
	beq	main_loop		@ if eq get next input
	bl	handleUndefined		@ undefined if this happens
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop		@ start again

nn_state_2_operation:			@ we're looking for an operation
	bl	isOperation		@ if is operation
	cmp	r0, #1			@ r0 == 1?
	moveq	r6, #STATE_INPUT_3	@ if eq change state to state 3
	ldreq	r1, =_operation		@ store operation in _operation
	ldreq	r2, =buf		@ if eq r2 = address of buf
	ldreqb	r2, [r2]		@ r2 = mem[r2]
	streqb	r2, [r1]		@ store operation in _operation
	beq	main_loop		@ get next input
	bl	handleUndefined		@ undefined if this happens
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop		@ start again

nn_state_2_operand:
	bl	handleUndefined		@ undefined if this happens
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop		@ start again

nn_state_3:
	bl	handleUndefined		@ if not a number then operation is undefined
	mov	r6, #STATE_INPUT_1	@ start again
	b	main_loop		@ start again

quit:	ldr	r0, =ADDR_UART0		@ r0 = UART address
	bl	newline			@ print newline
	ldr	r1, =string_quit	@ r1 = address of string_quit
	bl	print_string		@ print quit string
	b	iloop			@ quit

iloop:	b iloop			@ leave this infinite loop at the end of your program (needed for grading)

@ assumes r0 contains uart data register address
@ r1 should contain first character of string to display
print_string:
	push {r1,r2,lr}	@ save r1,r2,lr on stack
str_out:
	ldr r2,[r1]
	cmp r2,#0x00	@ '\0' = 0x00: null character?
	beq str_done	@ if yes, quit
	str r2,[r0]	@ otherwise, write character string
	add r1,r1,#1	@ go to next character
	b str_out	@ repeat
str_done:
	pop {r1,r2,lr}	@ restore r1,r2,lr
	bx lr		@ branch to value in lr

newline:
	mov r2, #'\n'	@ r2 = '\n'
	str r2,[r0]	@ write value in r2 to UART
	mov r2, #'\r'	@ r2 = '\r'
	str r2,[r0]	@ write value in r2 to UART
	bx lr		@ branch to value in lr

execute_input:
	push 	{ r0-r8, lr }	@ save r0-r8, lr on stack
	mov	r8, #0		@ r8 is a flag if error occurs
	ldr	r2, =_operation	@ r2 = address of _operation
	ldrb	r2, [r2]	@ r2 = mem[r2]
	ldr	r0, =_operandA	@ r0 = address of _operandA
	ldr	r0, [r0]	@ r0 = mem[r0]
	ldr	r1, =_operandB	@ r1 = address of _operandB
	ldr	r1, [r1]	@ r1 = mem[r1]
	cmp	r2, #'+'	@ cmp operation to '+'
	bne	ei_n		@ if ne check next type
	bleq	executeAdd	@ if eq execute add
	b	ei_d		@ done after executing add
ei_n:	cmp	r2, #'-'	@ cmp operation to '-'
	bne	ei_n_1		@ if ne check next type
	bleq	executeSubtract	@ negate is the same as 0 - _operandB 
	b	ei_d		@ done after executing sub
ei_n_1:	cmp	r2, #'*'	@ cmp operation to '*'
	bne	ei_n_2		@ if ne check next type
	bleq	executeMultiply	@ if eq execute multiply
	b	ei_d		@ done after executing mult
ei_n_2:	bl	executeDivide	@ otherwise it's divide
	b	ei_d		@ done after executing divide
ei_d:	cmp	r8, #1		@ check if an error occured
	beq	ei_end		@ if eq go to end
	bl	toStr		@ otherwise get string of result
	mov	r4, r0		@ r4 = r0
	ldr	r0, =ADDR_UART0	@ r0 = addr of UART
	@ldr	r1, =string_result	@ r1 = address of string_result
	@bl	print_string		@ print string_result
	mov	r1, r4			@ r1 = r4
	bl	print_string		@ print result
	bl	newline			@ print newline
ei_end:	pop	{ r0-r8, lr }		@ restore r0-r8, lr
	bx	lr			@ branch to value in lr


@ write your code for the following functions

@ assumes r0 the address of the first byte of string
@ returns with r0 == 1 if it was the negate operation ('-'), else 0
isNegate:
	push	{r1-r2, lr}
	mov	r1, r0
	ldrb 	r2, [r1]

	cmp 	r2, #0x2D
	beq	endIsNegate

	mov 	r0, #0
	pop	{r1-r2, lr}
	bx lr
endIsNegate:
	mov 	r0, #1
	pop	{r1-r2, lr}
	bx lr

@ assumes r0 the address of the first byte of string
@ returns with r0 == 1 if it was a valid operation ('+', '-', '*', '/'), else 0
isOperation:
	push	{r1-r3, lr}
	mov	r1, r0
	ldrb 	r2, [r1]

	cmp	r2, #0x2B
	ldreqb 	r2, [r1, #1]
	cmpeq 	r2, #0x00
	beq 	endIsOperation

	cmp 	r2, #0x2D
	ldreqb 	r2, [r1, #1]
	cmpeq	r2, #0x00
	beq	endIsOperation

	cmp	r2, #0x2A
	ldreqb 	r2, [r1, #1]
	cmpeq	r2, #0x00
	beq	endIsOperation

	cmp 	r2, #0x2F
	ldreqb 	r2, [r1, #1]
	cmpeq	r2, #0x00
	beq	endIsOperation

	mov 	r0, #0
	pop	{r1-r3, lr}
	bx lr
endIsOperation:
	mov 	r0, #1
	pop	{r1-r3, lr}
	bx lr

@ assumes r0 the address of first byte of string
@ returns with r0 == 1 if it was a number (e.g., in ascii), else 0
isNumber:
	push	{r1-r8, lr}
	mov	r1, r0
	ldrb	r2, [r1]
	cmp	r2, #0x30
	blt	endIsNumber
	cmp	r2, #0x39
	bgt	endIsNumber
	mov	r0, #1
	pop	{r1-r8, lr}
	bx lr
endIsNumber:
	mov	r0, #0
	pop	{r1-r8, lr}
	bx lr	

@ write execution procedures next
@ each of these get executed respectively on different input operations
@ executed on binary '+' operation
executeAdd:
	push	{r2, lr}
	add 	r2, r0, r1
	bvs	handleOverflow
	mov	r0, r2
	pop	{r2, lr}
	bx lr


	
@ executed on binary '-' operation
executeSubtract:
	bx lr
	
@ executed on binary '*' operation
executeMultiply:
	bx lr
	
@ executed on binary '/' operation (hint, use div function below)
executeDivide:
	bx lr
	
@ executed on unary (one input) '-' operation
executeNegate:
	bx lr


@ write error handling procedures next
@ NOTE: you'll want to use the stack here, since these handlers may be called from other functions (e.g., handleDivByZero will be called by executeDivide)

@ called on undefined input
@ should print appropriate error message
handleUndefined:
	push	{r0, r1, lr}
	ldr	r0, =ADDR_UART0
	ldr	r1, =string_undefined
	bl 	print_string
	mov	r8, #1
	pop	{r0, r1, lr}
	bx lr
	
@ called on overflow
@ hint: detect overflow using the 'vc' condition flag
@ for example, you might use: bvc (branch if overflow clear) and bvs (branch if overflow set) or the corresponding branch with link (blvc or blvs)
@ should print appropriate error message
handleOverflow:
	push	{r0, r1, lr}
	ldr	r0, =ADDR_UART0
	ldr	r1, =string_overflow
	bl 	print_string
	mov	r8, #1
	pop	{r0, r1, lr}
	bx lr
	
@ called on division by zero
@ should print appropriate error message
handleDivByZero:
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

@ author: Brandon Lawrence
@
@ div: computes result of integer division r0/r1
@
@ results: r0 = r0/r1
@          
div:
@preamble
	push {r1, r2, r3, r4, r5, r6, r7, r8, lr}

div_main:
	@r0 holds numerator
	@r1 holds denominator

	mov r4, #1
	mov r5, #-1
	
	cmp r1, #0
	moveq r3, #0
	beq div_exit
	mullt r6, r4, r5
	movlt r4, r6
	mullt r6, r1, r5
	movlt r1, r6
	
	cmp r0, #0
	mullt r6, r4, r5
	movlt r4, r6
	mullt r6, r0, r5
	movlt r0, r6
	
	mov r7, r0
	mov r8, r1
	
	mov r3,#0
	mov r2,r1


div_counter:		@sets r2 to the largest multiple
	cmp r2,r0		@of 2 smaller than r0
	lsrgt r2,r2,#1	
	bge div_loop
	lsl r2,r2,#1
	b div_counter

div_loop:		
	cmp r2,r1
	blt div_exit
	
	lsl r3,r3,#1	@r3 stores result
	cmp r0,r2
	subge r0,r0,r2
	addge r3,r3,#1
	
	lsr r2,r2,#1
	b div_loop

div_exit:
	mul r0,r3,r4
	mul r6, r3, r8
	sub r1, r7, r6
	
@wrap-up
	pop {r1, r2, r3, r4, r5, r6, r7, r8, lr}
	bx lr


@ string messages to use and print in different scenarios
.data
last:	.word 0x00
string_start:
	.asciz "Starting calculator\n\r"
	.word 0x00

string_input_either:
	.asciz "Input operation or operand:\n\r"
	.word 0x00

string_input_operation:
	.asciz "Input operation:\n\r"
	.word 0x00

string_input_operand:
	.asciz "Input operand:\n\r"
	.word 0x00

string_result:
	.asciz "Result is: "
	.word 0x00
string_quit:
	.asciz "Quitting calculator\n\r"
	.word 0x00
string_undefined:
	.asciz "Operation Undefined\n\r"
	.word 0x00
string_overflow:
	.asciz "Error Overflow\n\r"
	.word 0x00
string_div_by_zero:
	.asciz "Error Divide by Zero\n\r"
	.word 0x00
_operandA:
	.word 0x00
_operation:
	.byte 0x00
.align
_operandB:
	.word 0x00

@ Using this as a buffer for input
@ NOTE: has enough space for -MAX_INT
buf:		.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
buf_end:	.byte 0
