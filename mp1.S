
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		CALL update_missiles
		CALL redraw_bases
		CALL redraw_crosshair

		POPL %EDI
		POPL %ESI
		POPL %EBX
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		ret


# ----------------- Functions private to this file -------------------

update_missiles:

		#%ESI = head pointer
		#%EDI = temp store
		#%EBX = 

		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		MOVL mp1_missile_list, %ESI 		#Moving head of missile list to ESI

	top:
		MOVL 28(%ESI), %EDI 		#storing 'exploded' in EDI
		CMPL $0, %EDI			#checking if exploded
		JNE missileExploded 

		#update x,y 
		ADDL 12(%ESI), 4(%ESI) 		#x = x + vx 
		MOVL 4(%ESI), %EDI
		CMPL $0, %EDI
		JL outOfBounds				#jmp if x < 0
		CMPL $79, %EDI
		JG outOfBounds				#jmp if x > 79
		ADDL 16(%ESI), 8(%ESI)		#y = y + vy 
		MOVL 8(%ESI), %EDI
		CMPL $0, %EDI
		JL outOfBounds				#jmp if y < 0
		CMPL $24, %EDI
		JG outOfBounds				#jmp if y > 24

		#has missile reached dest?
		MOVL 4(%ESI), %EDI
		CMPL 20(%ESI), %EDI		
		JNE notReachedDest
		MOVL 8(%ESI), %EDI
		CMPL 24(%ESI), %EDI
		JNE notReachedDest

		#missile has reached destination
	missileExploded:
		




	notReachedDest:
		#has screen changed?

	
	outOfBounds:
		#erase missile
		#void mp1_missile_remove(head)

		PUSHL %EAX 
		PUSHL %ECX 
		PUSHL %EDX 
		PUSHL %ESI 		#pushes argument head pointer
		CALL mp1_missile_remove			#removes missile
		POPL %EDX
		POPL %ECX
		POPL %EAX
		JMP nextMissile




	nextMissile:
		#check if %ESI is storing something
		MOVL 0(%ESI), %ESI		#%ESI = %ESI -> next 
		CMPL $0, %ESI
		JNE top				#if there is a next missile go to top

		POPL %EDI
		POPL %ESI
		POPL %EBX
		ret

#new functions

redraw_bases:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI


		POPL %EDI
		POPL %ESI
		POPL %EBX
		ret

redraw_crosshair:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI


		POPL %EDI
		POPL %ESI
		POPL %EBX
		ret

mp1_missile_remove:

		ret

#original functions

mp1_ioctl_startgame:
		ret

mp1_ioctl_addmissile:
		ret

mp1_ioctl_movexhairs:
		ret

mp1_ioctl_getstatus:
		ret

mp1_ioctl_endgame:
		ret



