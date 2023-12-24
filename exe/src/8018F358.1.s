/* when starting to play XA, initialize frame counter and show subtitle message */
/* start with original function code */
lui $v1, 0x801f
addiu $v0, $v1, -0x4928
sw $a1, 0x4($v0)
sw $a2, 0x8($v0)
sw $a0, 0xc($v0)
li $v0, 2
sw $v0, -0x4928($v1)
/* initialize frame counter */
lui $v0, 0x8012
sw $zero, -0x3e9c($v0)
/* show subtitles */
lui $v0, 0x801b
addiu $v0, $v0, -0xcf8
lw $v1, 0($v0) /* 0-based disc number */
lh $a0, 0x26($s1) /* XA index */
addiu $a0, $a0, 160 /* subtitle message index = num original messages in stage B + XA index */
bnez $v1, skipStageA
addiu $a0, $a0, 48 /* add the extra message count for stage A */
skipStageA:
/* show subtitle message */
sw $a0, 0x44($v0)
lw $a0, 0x40($v0)
ori $a0, 4
sw $a0, 0x40($v0)
jr $ra
