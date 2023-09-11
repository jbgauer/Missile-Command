
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

	#arg is 8 shifted

	ARG = 8


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
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX

		CALL update_missiles
		CALL redraw_bases
		CALL redraw_crosshair

		POPL %EDX
		POPL %ECX 
		POPL %EAX
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
		
		#%ESI = cmd
		#%EBX = unsinged long arg
		MOVL 8(%ESP), %EAX			#12 above EBP
		CMPL $4, %EAX 
		JA invalidCmd				#jmp if invalid

		JMP *jump_table(,%EAX,4)

	invalidCmd:
		MOVL $-1, %EAX			#return -1

		ret

	jump_table:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------
# void update_missiles(void)
#Subroutine for tasklet that processes the missiles. It will see if the missile
#is exploding, if it is draw @ and decrement unti reaches 0, which will erase 
#the missile. If its not exploding it updates x,y and erases new location and 
#redraws it. 
# Input: none
# Output: none
# Registers: 
#%ESI = head pointer
#%EBX = prev pointer
#%EDI = temp store
#%ECX = old x
#%EDX = old y 

update_missiles:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		MOVL mp1_missile_list, %ESI 		#Moving head of missile list to ESI
		CMPL $0, %ESI 
		JE dontNotify					#if head = null end
		XORL %EBX, %EBX 				#sets prev to 0
	top:
		MOVL X(%ESI), %ECX 			#storing old x 
		MOVL Y(%ESI), %EDX			#storing old y 
		MOVL EXPLODED(%ESI), %EDI 		#storing 'exploded' in EDI
		CMPL $0, %EDI				#checking if exploded
		JNE missileExploded 

		#update x,y
		MOVL VX(%ESI), %EDI 
		ADDL %EDI, X(%ESI) 			#x = x + vx 
		MOVL X(%ESI), %EDI
		SARL $TOPSHIFT, %EDI			#shift right 16 to get top 16 bits	
		CMPL $79, %EDI
		JA outOfBounds				#jmp if x < 0 || x > 79
		MOVL VY(%ESI), %EDI
		ADDL %EDI, Y(%ESI)			#y = y + vy 
		MOVL Y(%ESI), %EDI
		SARL $TOPSHIFT, %EDI		#shift right 16 to get top 16 bits	
		CMPL $24, %EDI
		JA outOfBounds				#jmp if y > 24 || y < 0

		#has missile reached dest?
		MOVL X(%ESI), %EDI
		SARL $TOPSHIFT, %EDI			#shift right 16 to get top 16 bits	
		CMPL DEST_X(%ESI), %EDI		
		JNE notReachedDest
		MOVL Y(%ESI), %EDI
		SARL $TOPSHIFT, %EDI		#shift right 16 to get top 16 bits	
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
		
		
		#erase old position
		#void mp1_printToScreen(X, Y, C)
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $32			#empty char
		MOVL %EDX, %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_y to stack
		MOVL %ECX, %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX
		
		
		#draw to screen with EXPLOSION Character
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $64			#exploded char
		MOVL Y(%ESI), %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_y to stack
		MOVL X(%ESI), %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
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
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $32			#empty char
		MOVL %EDX, %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_y to stack
		MOVL %ECX, %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes old top_x to stack
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		#re-draw in new postiion
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		MOVL C(%ESI), %EDI
		PUSHL %EDI			#c char
		MOVL Y(%ESI), %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
		PUSHL %EDI				#pushes top_y to stack
		MOVL X(%ESI), %EDI 
		SARL $TOPSHIFT, %EDI			#shifts to get top 16
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

		PUSHL %EAX 			#caller save
		PUSHL %ECX 
		PUSHL %EDX 
		PUSHL %EBX		#pushes argument prev pointer
		PUSHL %ESI 		#pushes argument head pointer
		CALL mp1_missile_remove			#removes missile
		POPL %EDX 		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX
		POPL %EAX

		#special increment
		CMPL $0, %EBX 	#checking if prev = 0
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
		MOVL NEXT(%ESI), %ESI		#curr = curr -> next 
	endCheck:
		CMPL $0, %ESI				#is curr = 0?
		JNE top				#if there is a next missile go to top

		CMPL $0, %EAX
		JE dontNotify
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		CALL mp1_notify_user 		#notify user-space
		POPL %EDX
		POPL %ECX 
		POPL %EAX
	
	dontNotify:	
		POPL %EDI		#pop back out
		POPL %ESI
		POPL %EBX
		leave
		ret

#void redraw_bases(void)
#Subroutine for tasklet in charge of drawing the bases to the screen. If 
#base is destroyed, draw destroyed base, else draw alive base.
#Input: none
#output: none
#Registers: 
#%ESI = base_index
#%EBX = draw_index
#%EDI = temp store
#%EDX = temp store
#%ECX = base_counter 

redraw_bases:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		XORL %ESI, %ESI		#esi = 0
		XORL %ECX, %ECX		#ecx = 0
	topLoop:
		MOVL $base_alive, %EDI
		MOVB (%EDI, %ESI,1), %DL	#increment and move to dl
		CMPB $0, %DL
		JE	baseDestroyed		#jmp if base not destroyed
		
		#base is not destroyed
		XORL %EBX, %EBX 		#draw_index = 0

	notDestroyedLoop:
		#print out base
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		#push c, y , x
		#c = base_pic[draw_index]
		MOVL $base_pic, %EDI
		MOVL (%EDI, %EBX,1), %EDI
		PUSHL %EDI

		#y = 24
		PUSHL $24

		#x = 18 + (base_index * 20) + draw_index
		MOVL %ESI, %EDI
		IMULL $20, %EDI 		#base_index * 20
		ADDL $18, %EDI			#above + 18
		ADDL %EBX, %EDI			#above + draw_index 
		PUSHL %EDI

		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX
		
		ADDL $1, %EBX		#increment draw_index
		CMPL $4, %EBX 			
		JBE notDestroyedLoop			#loop if draw_index <= 4
		JMP nextIndex


	baseDestroyed:
		#base is destroyed
		XORL %EBX, %EBX 		#draw_index = 0
	destroyedLoop:
		#print out base
		PUSHL %EAX				#caller save
		PUSHL %ECX
		PUSHL %EDX
		#push c, y , x
		#c = dead_base_pic[draw_index]
		MOVL $dead_base_pic, %EDI
		MOVL (%EDI, %EBX,1), %EDI
		PUSHL %EDI

		#y = 24
		PUSHL $24

		#x = 18 + (base_index * 20) + draw_index
		MOVL %ESI, %EDI
		IMULL $20, %EDI		#base_index * 20
		ADDL $18, %EDI			#above + 18
		ADDL %EBX, %EDI			#above + draw_index 
		PUSHL %EDI

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

#void redraw_crosshair(void)
#redraws the crosshair at the specified x,y numbers stored
#Input: none
#output : none
#Registers: standard c
redraw_crosshair:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#redraw crosshair
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		#push c, y, x
		PUSHL $43			#crosshair character
		PUSHL crosshairs_y		#set X
		PUSHL crosshairs_x		#set y 
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

#mp1_missile_remove(struct missile *curr, struct missile *prev)
#takes in pointers to curr and prev and erases it from the screen, removes it from
#the linked list, and then frees the missile in memory
#input : pointer to current struct missile
# pointer to previous struct missile
#output: none
#registers: 
#ESI = curr
#EBX = prev
mp1_missile_remove:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		#mp1_missile_remove(curr, prev)
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		#ESI = curr
		#EBX = prev
		MOVL 8(%EBP), %ESI		#curr stored 8 above EBP
		MOVL 12(%EBP), %EBX		#prev stored 12 above EBP

		#erase from screen
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $32				#empty char
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
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %ESI 			#push curr pointer
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

#void mp1_printToScreen(int X, int Y,char C)
#this function takes in x,y,c and calculates the value to draw it to memory
#y*160+x*2. Then calls mp1_poke to draw to screen.
#inputs: x-cord, y-cord, and c char.
#outputs: none
#registers:
#%EDI = X 
#%EDX = Y 
mp1_printToScreen:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		MOVL 8(%EBP), %EDI		#x was pushed 4 bytes from ebp
		MOVL 12(%EBP), %EDX		#y pushed 8 from ebp
		MOVB 16(%EBP), %CL		#store c to CL
 
		IMULL $160, %EDX	 	#y = y*80*2
		IMULL $2, %EDI   		#x = x*2
		ADDL %EDX, %EDI			#y*80*2 + x*2
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

#int mp1_ioctl_startgame(unsigned long ignore)
#function initializes all variables, sets crosshair, and sets all bases alive.
#input : ignore
#output: none
#registers:
#%EDI = temp reg
mp1_ioctl_startgame:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		
		#initialize
		MOVL $0, mp1_missile_list		#set head = null
		MOVW $0, mp1_score				#score = 0

		MOVL $65793, base_alive		#setting bases alive = 00000000000000010000000100000001
		#crosshair
		MOVL $40, crosshairs_x		#set x
		MOVL $12, crosshairs_y		#set y
			

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

#int mp1_ioctl_addmissile(struct missile* user_missile)
#this function allocates memory for a missile, stores it to the linked list
#it fails the memory is freed and -1 is returned. Success return 0.
#input: pointer to a struct missile that is being added
#output: 0 if success, -1 if failed
#registers:
#%ESI = arg (struct missile*)
#%EDI = temp reg
mp1_ioctl_addmissile:
		#int mp1_ioctl_addmissile (struct missile* user_missile)
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
	
		#%ESI = arg
		#%EDI = temp reg
		MOVL ARG(%EBP), %ESI 		#8 above ebp is arg

		#dynamic memory allocation
		PUSHL %ECX			#caller save
		PUSHL %EDX
		PUSHL $36			#size of struct missile is 36 bytes
		CALL mp1_malloc
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX 
		MOVL %EAX, %EDI
		CMPL $0, %EAX 		#check to see if failed 
		JE addFailed
		
		#data copy
		PUSHL %ECX			#caller save
		PUSHL %EDX
		PUSHL $36			#size of struct missile is 36 bytes
		PUSHL %ESI			#from
		PUSHL %EAX			#to
		CALL mp1_copy_from_user
		POPL %EDX			#pop args
		POPL %EDX			#pop args
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX 
		CMPL $0, %EAX
		JE addSuccess 		#all bytes added successfully 

		#not added successfully so must free memory
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %EDI			#push memory address
		CALL mp1_free
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX
		POPL %EAX 
	addFailed:
		#free any memory allocated before returning 
		MOVL $-1, %EAX			#return -1
		JMP addEnd
	addSuccess:
		MOVL mp1_missile_list, %EBX
		MOVL %EBX, NEXT(%EDI)			# new ->next = head
		MOVL %EDI, mp1_missile_list  		#head = new
		MOVL $0, %EAX					#return 0

	
	addEnd:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret


#int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
#this function moves the crosshair, making sure it doesnt go out of bounds 
#input: unsigned long which top 16 stores y, and bottom 16 stores x.
#output: always return 0
#registers:
#ESI = x change 
#EBX = y change
#EDI = temp reg 
#ECX = temp reg
mp1_ioctl_movexhairs:
		#int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
	
		
		MOVL ARG(%EBP), %EDI			#args is 8 above ebp 
		MOVL %EDI, %EBX
		SARL $16, %EBX			#contains top 16 bit
		MOVL %EDI, %ESI  
		SHLL $16, %ESI 
		SARL $16, %ESI			#contains bottom 16 bit
		#setting x
		ADDL crosshairs_x, %ESI
		CMPL $0, %ESI
		JGE xUpper					#if x >= 0 jmp
		MOVL $0, %ESI			#set x = 0
		JMP setY

	xUpper:
		CMPL $79, %ESI
		JLE setY						#if x <= 79 jmp
		MOVL $79, %ESI					#set x = 79

	setY:
		ADDL crosshairs_y, %EBX 	
		CMPL $0, %EBX 
		JGE yUpper					#if y >= 0 jmp
		MOVL $0, %EBX 			#set y = 0
		JMP eraseCrosshair

	yUpper:
		CMPL $24, %EBX 
		JLE eraseCrosshair				#if y <= 23 jmp
		MOVL $24, %EBX 					#set y = 23

	eraseCrosshair:
		#erase crosshair
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $EMPTYCHAR			#empty char
		PUSHL crosshairs_y		#y
		PUSHL crosshairs_x		#x
		CALL mp1_printToScreen
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX		#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		MOVL %ESI, crosshairs_x		#set x 
		MOVL %EBX, crosshairs_y	   #set y

		#draw crosshair
		PUSHL %EAX			#caller save
		PUSHL %ECX
		PUSHL %EDX
		#c
		PUSHL $CROSSHAIRCHAR			#'+' char
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

#int mp1_ioctl_getstatus(unsigned long* user_status)
#this function loads score into bottom 16, and status of three cities into 16,17,18
#0 if destroyed, 1 if alive.
#input: unsigned long* user_status which points to a memory address needed to 
#copy to. 
#output: 0 if successful, -1 if failed. 
#registers:
#%ESI = hold main status
#%EDI = temp reg
#%EBX = temp reg
#%EDX = hold status of bases
#%ECX = user_status
mp1_ioctl_getstatus:
	
		#int mp1 ioctl getstatus (unsigned long* user status)
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
	
		
		XORL %EDX, %EDX			#set edx = 0
		XORL %ESI, %ESI
		MOVL ARG(%EBP), %ECX 		#arg is 8 above ebp

		#low-16 current score
		MOVW mp1_score, %SI #moves mp1_score to low 16 of esi
		
		#16,17,18 are current cities 0 is destroyed, 1 is alive
		MOVL $base_alive, %EDI
		MOVB 0(%EDI), %BL 
		CMPB $0, %BL			#is it alive?
		JBE sndBase
		ADDL $65536, %EDX		#value for a 1 at 16-bit
	sndBase:
		MOVB 1(%EDI), %BL
		CMPB $0, %BL			#is it alive?
		JBE thrdBase
		ADDL $131072, %EDX		#value  for a 1 at 17-bit


	thrdBase:
		MOVB 2(%EDI), %BL
		CMPB $0, %BL			#is it alive?
		JBE doneStatus
		ADDL $262144, %EDX		#value  for a 1 at 18-bit

	doneStatus:
		ADDL %EDX, %ESI
		#create space for esi
		PUSHL %ECX		#caller save
		PUSHL %EDX
		PUSHL $4			#size of struct missile is 36 bytes
		CALL mp1_malloc
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX 
		MOVL %EAX, %EDI
		MOVL %ESI, (%EDI)		#move value into memory address

		PUSHL %EAX		#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL $4				#n = 4
		PUSHL %EDI				#from %EDI
		PUSHL %ECX				#to %ECX
		CALL mp1_copy_to_user
		POPL %EDX 				#pop args
		POPL %EDX 				#pop args
		POPL %EDX 				#pop args
		POPL %EDX
		POPL %ECX 
		POPL %EAX

		#free that space
		PUSHL %EAX		#caller save
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %EDI			#push memory address
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

#int mp1_ioctl_endgame(unsigned long ignore)
#this function clears the memory used by linked list and cleanup
#input: ignore
#output: 0 for success
#registers:
#%ESI = curr ptr
#%EBX = next ptr
mp1_ioctl_endgame:
		PUSHL %EBP				#callee setup
		MOVL %ESP, %EBP
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
	
		#%ESI = curr ptr
		#%EBX = next ptr
		#free all memory in linked list
		MOVL mp1_missile_list, %ESI				#curr = head
	endTopLoop:
		CMPL $0, %ESI
		JE  endDone
		MOVL NEXT(%ESI), %EBX			#next = curr->next
		#free memory
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %ESI			#push memory address
		CALL mp1_free
		POPL %EDX			#pop args
		POPL %EDX
		POPL %ECX
		POPL %EAX

		MOVL %EBX, %ESI		#curr = next
		JMP endTopLoop


	endDone:
		MOVL $0, %EAX		#return success
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
