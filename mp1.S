
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

	# Character to draw empty space ' '

	EMPTYCHAR = 32

	#Character to draw crosshair '+'

	CROSSHAIRCHAR = 43

	# Shift 16 space

	TOPSHIFT = 16


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
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		#%ESI = cmd
		#%EBX = unsinged long arg
		MOVL 20(%ESP), %ESI			#20 above esp is cmd
		CMPL $4, %ESI 
		JA invalidCmd				#jmp if invalid

		JMP *jump_table(,%ESI,4)

		jump_table:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


	invalidCmd:
		MOVL $-1, %EAX			#return -1

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret


# ----------------- Functions private to this file -------------------

update_missiles:

		#%ESI = head pointer
		#%EBX = prev pointer
		#%EDI = temp store
		#%ECX = old x
		#%EDX = old y 
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		MOVL mp1_missile_list, %ESI 		#Moving head of missile list to ESI
		XORL %EBX, %EBX 				#sets prev to 0
	top:
		MOVL EXPLODED(%ESI), %EDI 		#storing 'exploded' in EDI
		CMPL $0, %EDI				#checking if exploded
		JNE missileExploded 

		#update x,y
		MOVL X(%ESI), %ECX 			#storing old x 
		MOVL Y(%ESI), %EDX			#storing old y 

		MOVL VX(%ESI), %EDI 
		ADDL %EDI, X(%ESI) 			#x = x + vx 
		MOVL X(%ESI), %EDI
		SHRL $16, %EDI			#shift right 16 to get top 16 bits	
		CMPL $79, %EDI
		JA outOfBounds				#jmp if x < 0 || x > 79
		MOVL VY(%ESI), %EDI
		ADDL %EDI, Y(%ESI)			#y = y + vy 
		MOVL Y(%ESI), %EDI
		SHRL $16, %EDI		#shift right 16 to get top 16 bits	
		CMPL $24, %EDI
		JA outOfBounds				#jmp if y > 24 || y < 0

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

	missileDecrement:
		#decrement exploded
		SUBL $1, EXPLODED(%ESI)			#exploded = exploded -1
		MOVL EXPLODED(%ESI), %EDI
		CMPL $0, %EDI				#if exploded == 0
		JE eraseMissile

		#draw to screen with EXPLOSION Character
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL EXPLODED			#exploded char
		MOVL Y(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_y to stack
		MOVL X(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX
		JMP nextMissile
		

	notReachedDest:
		#has screen position changed?
		#erase old position
		#void mp1_printToScreen(X, Y, C)
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL EMPTYCHAR			#empty char
		MOVL %EDX, %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_y to stack
		MOVL %ECX, %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		#re-draw in new postiion
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL C(%ESI)			#c char
		MOVL Y(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_y to stack
		MOVL X(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX
		JMP nextMissile
	
	outOfBounds:
		MOVL %ECX, X(%ESI)		#restore old x
		MOVL %EDX, Y(%ESI) 		#restore old y

	eraseMissile:
		#erase missile
		#void mp1_missile_remove(head, prev)

		PUSHL %EAX 
		PUSHL %ECX 
		PUSHL %EDX 
		PUSHL %EBX		#pushes argument prev pointer
		PUSHL %ESI 		#pushes argument head pointer
		CALL mp1_missile_remove			#removes missile
		POPL %EDX 		#pop args
		POPL %EDX		
		POPL %EDX
		POPL %ECX
		POPL %EAX
		#special increment
		CMPL 0, %EBX 	#checking if prev = 0
		JNE notBeginList
		#beginning of list
		MOVL mp1_missile_list, %ESI		#set curr = head
		JMP endCheck

	notBeginList:
		MOVL NEXT(%EBX), %ESI 		#curr = prev->next
		JMP endCheck

	nextMissile:
		#check if %ESI is storing something
		MOVL %ESI, %EBX				#prev = curr
		MOVL NEXT(%ESI), %ESI		#head = curr -> next 
	endCheck:
		CMPL $0, %ESI				#is curr = 0?
		JNE top				#if there is a next missile go to top

		CMPL $0, %EAX
		JNE dontNotify
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		CALL mp1_notify_user 		#notify user-space
		POPL %EDX
		POPL %ECX 
		POPL %EAX

	dontNotify:	
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

		#%ESI = base_index
		#%EBX = draw_index
		#%EDI = temp store
		#%EDX = temp store
		#%ECX = base_counter 
		XORL %ESI, %ESI		#esi = 0
		XORL %ECX, %ECX		#ecx = 0
	topLoop:
		MOVL base_alive, %EDI
		MOVB (%EDI, %ESI), %DL
		CMPB $0, %DL
		JE	baseDestroyed		#jmp if base not destroyed
		
		#base is not destroyed
		XORL %EBX, %EBX 		#draw_index = 0
	notDestroyedLoop:
		#print out base
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		#push c, y , x
		#c = base_pic[draw_index]
		MOVL base_alive, %EDI
		MOVL (%EDI, %EBX), %EDI
		PUSHL %EDI

		#x = 18 + (base_index * 20) + draw_index
		MOVL %ESI, %EDI
		IMULL $20, %ESI 		#base_index * 20
		ADDL $18, %EDI			#above + 18
		ADDL %EBX, %EDI			#above + draw_index 
		PUSHL %EDI

		#y = 24
		PUSHL $24

		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX
		
		ADDL $1, %EBX
		CMPL $4, %EBX 
		JBE notDestroyedLoop			#loop if draw_index <= 4
		JMP nextIndex


	baseDestroyed:
		#base is destroyed
		XORL %EBX, %EBX 		#draw_index = 0
	destroyedLoop:
		#print out base
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		#push c, y , x
		#c = dead_base_pic[draw_index]
		MOVL dead_base_pic, %EDI
		MOVL (%EDI, %EBX), %EDI
		PUSHL %EDI

		#x = 18 + (base_index * 20) + draw_index
		MOVL %ESI, %EDI
		IMULL $20, %ESI		#base_index * 20
		ADDL $18, %EDI			#above + 18
		ADDL %EBX, %EDI			#above + draw_index 
		PUSHL %EDI
		
		#y = 24
		PUSHL $24

		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		ADDL $1, %EBX				#increment draw_index
		CMPL $4, %EBX 
		JBE destroyedLoop			#loop if draw_index <= 4

	nextIndex:
		ADDL $1, %ESI				#increment base_index
		CMPL $2, %ESI
		JBE topLoop					#loop if base_index <= 2

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

redraw_crosshair:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#redraw crosshair
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		#push c, y, x
		PUSHL CROSSHAIRCHAR			#crosshair character
		PUSHL crosshairs_x
		PUSHL crosshairs_y
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_missile_remove:
		#mp1_missile_remove(curr, prev)
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#ESI = curr
		#EBX = prev
		MOVL 4(%EBP), %ESI		#curr stored 4 above EBP
		MOVL 8(%EBP), %EBX		#prev stored 8 above EBP

		#erase from screen
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL EMPTYCHAR			#empty char
		MOVL Y(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_y to stack
		MOVL X(%ESI), %EDI 
		SHRL $16, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		#remove from linked list
		CMP $0, %EBX	
		JNE notHeadOfList			#jmp if prev is not null
		MOVL NEXT(%ESI), %EDI
		MOVL %EDI, mp1_missile_list		#sets new head
		JMP freeMissile

	notHeadOfList:
		MOVL NEXT(%ESI), %EDI
		MOVL %EDI, NEXT(%EBX)			#prev->next = curr->next
		
	freeMissile:
		#struct missile freed with mp1_free
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		MOVL NEXT(%ESI), %EDI
		PUSHL %EDI			#push curr pointer
		CALL mp1_free
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX
		POPL %EAX 

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_printToScreen:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#void mp1_printToScreen(X, Y, C)
		#%EDI = X 
		#%EDX = Y 
		MOVL 4(%EBP), %EDI		#x was pushed 4 bytes from ebp
		MOVL 8(%EBP), %EDX		#y pushed 8 from ebp
		MOVB 12(%EBP), %CL		#store c to CL
 
		IMULL $160, %EDI	 	#x = x*80*2
		IMULL $2, %EDX			#y = y*2
		ADDL %EDX, %EDI			# x*80*2 + y*2
		MOVL %EDI, %EAX

		PUSHL %EDX		
		CALL mp1_poke			#draw to screen	
		POPL %EDX

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret


#-------------------------------------------

#original functions

mp1_ioctl_startgame:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#%EDI = temp reg
		#initialize
		MOVL $0, mp1_missile_list		#set head = null
		MOVL $0, mp1_score				#score = 0
		MOVL base_alive, %EDI
		MOVB $1, %EDI			#setting base_alive to 0
		MOVB $1, 1(%EDI)
		MOVB $1, 2(%EDI)	
		#crosshair
		MOVL $40, crosshairs_x		#set x
		MOVL $12, crosshairs_y		#set y
			

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_ioctl_addmissile:
		#int mp1_ioctl_addmissile (struct missile* user_missile)
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#%ESI = arg
		#%EDI = temp reg

		MOVL 28(%ESP), %ESI 		#28 above esp is arg


		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_ioctl_movexhairs:
		#int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		#ESI = x change 
		#EBX = y change
		#EDI = temp reg 
		MOVL 4(%EBP), %EDI
		MOVL %EDI, %EBX
		SHRL $16, %EBX			#contains top 16 bit
		MOVL %EDI, %ESI  
		SHLL $16, %ESI 
		SHRL $16, %ESI			#contains bottom 16 bit
		#setting x
		ADDL %ESI, crosshairs_x 	#increment X
		CMPL $0, crosshairs_x
		JGE xUpper					#if x >= 0 jmp
		MOVL $0, crosshairs_x			#set x = 0
		JMP setY

	xUpper:
		CMPL $79, crosshairs_x
		JLE setY						#if x <= 79 jmp
		MOVL $79, crosshairs_x			#set x = 79

	setY:
		ADDL %EBX, crosshairs_y 	#increment X
		CMPL $0, crosshairs_y
		JGE yUpper					#if y >= 0 jmp
		MOVL $0, crosshairs_y			#set y = 0
		JMP drawCrosshair

	yUpper:
		CMPL $23, crosshairs_x
		JLE drawCrosshair				#if y <= 23 jmp
		MOVL $23, crosshairs_x			#set y = 23

	drawCrosshair:
		#draw crosshair
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		#c
		PUSHL CROSSHAIRCHAR
		#Y
		PUSHL crosshairs_y
		#X
		PUSHL crosshairs_x
		CALL mp1_printToScreen
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		MOVL $0, %EAX				#return 0

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_ioctl_getstatus:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		



		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

mp1_ioctl_endgame:
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		#free all memory in linked list
		


		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret



