
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	X_TOP = 6
	Y	  = 8
	Y_TOP = 10
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
		leave
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
		leave
		ret


# ----------------- Functions private to this file -------------------

update_missiles:

		#%ESI = head pointer
		#%EDI = temp store
		#%EBX = prev pointer

		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		MOVL mp1_missile_list, %ESI 		#Moving head of missile list to ESI

	top:
		MOVL EXPLODED(%ESI), %EDI 		#storing 'exploded' in EDI
		CMPL $0, %EDI			#checking if exploded
		JNE missileExploded 

		#update x,y
		MOVL VS(%ESI), %EDI 
		ADDL %EDI, X(%ESI) 			#x = x + vx 
		MOVL X(%ESI), %EDI
		CMPL $0, %EDI
		JL outOfBounds				#jmp if x < 0
		CMPL $79, %EDI
		JG outOfBounds				#jmp if x > 79
		MOVL VY(%ESI), %EDI
		ADDL %EDI, Y(%ESI)			#y = y + vy 
		MOVL Y(%ESI), %EDI
		CMPL $0, %EDI
		JL outOfBounds				#jmp if y < 0
		CMPL $24, %EDI
		JG outOfBounds				#jmp if y > 24

		#has missile reached dest?
		MOVL X(%ESI), %EDI
		CMPL DEST_X(%ESI), %EDI		
		JNE notReachedDest
		MOVL Y(%ESI), %EDI
		CMPL DEST_Y(%ESI), %EDI
		JNE notReachedDest

		#missile has reached destination

	missileExploded:
		PUSHL %ECX
		PUSHL %EDX 
		PUSHL %ESI 				#pushes argument head pointer
		CALL missile_explode			#removes missile
		POPL %EDX				#pop argument
		POPL %EDX
		POPL %ECX
		CMPL $0, %EAX			
		JNE missleDecrement		#if EAX /= 0 then don't call mp1_notify
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		CALL mp1_notify_user 		#notify user-space
		POPL %EDX
		POPL %ECX 
		POPL %EAX
	missileDecrement:
		#decrement exploded
		SUBL $1, EXPLODED(%ESI)			#exploded = exploded -1
		MOVL EXPLODED(%ESI), %EDI
		CMPL $0, %EDI				#if exploded == 0
		JE outOfBounds

		#draw to screen with EXPLOSION Character
		MOVL EXPLOSION, %CL 	#store explosion char to %CL
		MOVW X_TOP(%ESI), %EDI		
		IMULW $160, %EDI	 	#x = x*80*2
		MOVW Y_TOP(%ESI), %EDX	
		IMULW $2, %EDX			#y = y*2
		

		PUSHL %EDX		
		CALL mp1_poke		
		POPL %EDX

	notReachedDest:
		#has screen position changed?
		#erase old position

		#re-draw in new postiion
	
	outOfBounds:
		#erase missile
		#void mp1_missile_remove(head)

		PUSHL %EAX 
		PUSHL %ECX 
		PUSHL %EDX 
		PUSHL %ESI 		#pushes argument head pointer
		CALL mp1_missile_remove			#removes missile
		POPL %EDX 		#pop argument
		POPL %EDX
		POPL %ECX
		POPL %EAX
		JMP nextMissile


	nextMissile:
		#check if %ESI is storing something
		MOVL NEXT(%ESI), %ESI		#%ESI = %ESI -> next 
		CMPL $0, %ESI
		JNE top				#if there is a next missile go to top

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

#new functions

redraw_bases:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI


		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

redraw_crosshair:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI


		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_missile_remove:
		leave
		ret

#original functions

mp1_ioctl_startgame:
		leave
		ret

mp1_ioctl_addmissile:
		leave
		ret

mp1_ioctl_movexhairs:
		leave
		ret

mp1_ioctl_getstatus:
		leave
		ret

mp1_ioctl_endgame:
		leave
		ret



