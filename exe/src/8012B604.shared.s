/* increment the message frame counter and send a corresponding message event */
lui $v0, 0x8012
lw $a0, -0x3e9c($v0)
addiu $v1, $a0, 1
sw $v1, -0x3e9c($v0)
jal 0x80129a30
/* restore regs and return */
lw $a1, 0x34($s0)
lw $a2, 0x38($s0)
li $v1, -5
j 0x8019017c
