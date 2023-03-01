[BITS 16]
[ORG 0x8000]
[CPU KATMAI]

jmp short entry
nop

; Generally my calling convention is (e)AX, (e)DX are function arguments, pass additional arguments RTL
;   callee saves segment registers, (e)CX, (e)BX, BP
;   caller saves (e)SI, (e)DI, (e)flags
;
; (e)AX and (e)DX are considered scratch registers

;-- Configuration Constants

%define MAX_SECTORS           4
%define MAX_DISK_RETRY        10
%define KERNEL_ENTRY          0x100000

;-- End Configuration
%define MAX_OSLDR_BYTES       (512 * MAX_SECTORS)

;-- Memory (Stack/Heap) layout

; 8 KiB stack
%define STACK_END             0x0500
%define STACK_START           0x2500

%define HEAP_START            0x3000

; read_sector heap
%define retry_count__WORD     0x3000
%define CHS_LBA__WORD         0x3002
%define CHS_Temp__WORD        0x3004

; load_binary heap
%define ff_first_fat__WORD    0x3010
%define high_mem_dest__DWORD  0x3012
%define buf_bytes_used__WORD  0x3016

; load_elf heap


; FAT12 FAT is 9KiB = 0x3600 - 0x5FFF
%define FAT_Table             0x3600
;-- End memory layout

; 4 KiB byte buffer
%define DISK_BUFFER           0x6000
%define DISK_BUFFER_LEN       0x1000

; 12 bytes
%define FSInfo                0x7000

; 20 bytes
%define KInfo                 0x7010

; 59 bytes
%define BPB_DATA              0x7030

%define CBoot_Conf            0x7100

; 0x200 (512 bytes) 0x7400 - 0x76FF
%define directory_ent_buf     0x7400

%define BIOSMemoryMap         0x7700

%define CBootInfo             0x7A00

%define OSLDR_ENTRY           0x8000



;-- Structures

; 33 bytes BPB + 26 Byte EBPB
struc BPBStruct
    .OemName        resb 8
    .BytesPerSect   resw 1
    .SecsPerClust   resb 1
    .ResSectors     resw 1
    .FATs           resb 1
    .RootDirEnts    resw 1
    .Sectors        resw 1
    .Media          resb 1
    .SectPerFAT     resw 1
    .SectPerTrack   resw 1
    .Heads          resw 1
    .Hidden         resd 1
    .SectorHuge     resd 1
    ; begin EBPB
    .DriveNumber    resb 1
    .NTReserved     resb 1
    .Signature      resb 1
    .VolumeID       resd 1
    .VolumeLabel    resb 11
    .SysIdent       resb 8
endstruc

; 12 bytes
struc FSInfoStruct
    .first_root_dir_sector resw 1
    .last_root_dir_sector  resw 1
    .root_dir_len          resw 1
    .first_data_sector     resw 1
    .active_cluster        resw 1
    .active_FAT_cluster    resw 1
endstruc

; 20 bytes
struc KInfoStruct
    .load_address          resd 1
    .file_len              resd 1
    .file_name             resb 8
    .file_ext              resb 3
    .reserved1             resb 1
endstruc

; Address Range Descriptor Structure
;
; Offset in Bytes		Name		Description
;	0	    BaseAddrLow		u32 - Low 32 Bits of Base Address
;	4	    BaseAddrHigh	u32 - High 32 Bits of Base Address
;	8	    LengthLow		u32 - Low 32 Bits of Length in Bytes
;	12	    LengthHigh		u32 - High 32 Bits of Length in Bytes
;	16	    Type		    u32 - Address type of  this range.
;   20      ExtType         u32 -  ACPI 3.0 extended type
struc AddressRangeDescStruct
    .BaseAddrLow    resd 1
    .BaseAddrHigh   resd 1
    .LengthLow      resd 1
    .LengthHigh     resd 1
    .Type           resd 1
    .ExtType        resd 1
endstruc

; 20 bytes, passed to loaded kernel
struc CBootInfoStruct
    .MemoryMapPtr      resd 1
    .MemoryMapEntries  resd 1
    .BPBDataPtr        resd 1
    .FSInfoPtr         resd 1
    .KInfoPtr          resd 1
endstruc

struc CBoot_Config
    .cboot_flags       resb 1
    .entry_count       resb 1
    .entry_list        resw 1
endstruc

struc CBoot_Entry
    .ent_type          resb 1
    .ent_flags         resb 1
    .ent_name          resb 16
    .ent_file          resb 8
    .ent_ext           resb 3
    .ent_res           resb 1
    .ent_path          resw 1
endstruc

struc ElfIdent
    .ei_magic          resb 4
    .ei_class          resb 1
    .ei_data           resb 1
    .ei_version        resb 1
    .ei_osabi          resb 1
    .ei_abiversion     resb 1
    .ei_pad            resb 7
endstruc

%define EI_NIDENT 16
struc Elf32_Ehdr
    .e_ident           resb EI_NIDENT
    .e_type            resw 1
    .e_machine         resw 1
    .e_version         resd 1
    .e_entry           resd 1
    .e_phoff           resd 1
    .e_shoff           resd 1
    .e_flags           resd 1
    .e_ehsize          resw 1
    .e_phentsize       resw 1
    .e_phnum           resw 1
    .e_shentsize       resw 1
    .e_shnum           resw 1
    .e_shstrndx        resw 1
endstruc

struc Elf64_Ehdr
    .e_ident           resb EI_NIDENT
    .e_type            resw 1
    .e_machine         resw 1
    .e_version         resd 1
    .e_entry           resq 1
    .e_phoff           resq 1
    .e_shoff           resq 1
    .e_flags           resd 1
    .e_ehsize          resw 1
    .e_phentsize       resw 1
    .e_phnum           resw 1
    .e_shentsize       resw 1
    .e_shnum           resw 1
    .e_shstrndx        resw 1
endstruc

struc Elf32_Phdr
    .p_type            resd 1
    .p_offset          resd 1
    .p_vaddr           resd 1
    .p_paddr           resd 1
    .p_filesz          resd 1
    .p_memsz           resd 1
    .p_flags           resd 1
    .p_align           resd 1
endstruc

struc Elf32_Shdr
    .sh_name           resd 1
    .sh_type           resd 1
    .sh_flags          resd 1
    .sh_addr           resd 1
    .sh_offset         resd 1
    .sh_size           resd 1
    .sh_link           resd 1
    .sh_info           resd 1
    .sh_addralign      resd 1
    .sh_entsize        resd 1
endstruc

struc Elf64_Phdr
    .p_type            resd 1
    .p_flags           resd 1
    .p_offset          resq 1
    .p_vaddr           resq 1
    .p_paddr           resq 1
    .p_filesz          resq 1
    .p_memsz           resq 1
    .p_align           resq 1
endstruc

struc Elf64_Shdr
    .sh_name           resd 1
    .sh_type           resd 1
    .sh_flags          resq 1
    .sh_addr           resq 1
    .sh_offset         resq 1
    .sh_size           resq 1
    .sh_link           resd 1
    .sh_info           resd 1
    .sh_addralign      resq 1
    .sh_entsize        resq 1
endstruc

;-- End Structures

;-- Error Codes

; No signature present
%define SIGNATURE_MISSING               0xDEAD_BEEF

; A20 enablement errors
%define A20_FAILURE                     0xF000_0001

; BIOS read sector errors
%define DISK_READ_RETRY_FAILURE         0xF100_0001

; Memory map detection errors
%define MM_E820_NO_SUPPORT              0xFD00_0001
%define MM_E820_NONSTANDARD             0xFD00_0002
%define MM_E820_NO_SMAP                 0xFD00_0003
%define MM_E820_MISC_ERR                0xFD00_FFFF

;Init FSInfo Errors
%define FS_MUL_OVERFLOW                 0xFE00_0001

; load_binary errors
%define FF_FILE_NOT_FOUND               0xFF00_0001
%define FF_FILE_OUT_OF_BOUNDS           0xFF00_0002
;-- End Error Codes

entry:
    cli                         ; We do not want to be interrupted

    xor ax, ax                  ; 0 AX
    mov ds, ax                  ; Set segment registers to 0
    mov es, ax                  ; *
    mov fs, ax                  ; *
    mov gs, ax                  ; *

    mov ss, ax                  ; Set Stack Segment to 0
    mov sp, STACK_START         ; Set Stack Pointer

    mov bp, OSLDR_ENTRY

    mov cx, BPBStruct_size      ; size of BPB+EBPB
    mov si, dx                  ; stage1 places address of first byte in dx
    mov di, BPB_DATA            ; copy to a safe location
    rep movsb

    sti

    jmp 0:main

main:
    call SetTextMode                    ; init VGA to 80x25 16 color text mode (clear screen)
    call disable_cursor
    
    mov eax, dword [OSLDR_SIG]
    cmp eax, 0xDEADBEEF
    je main.signature_present

    mov eax, SIGNATURE_MISSING
    call error_printer

.signature_present:
    lea si, [HelloPrompt_cstr]
    call PrintString

    call EnableA20
    lea si, [A20_OK_cstr]
    call PrintString

    ; detect memory map
    call detect_memory_E820
    lea si, [MemMap_OK_cstr]
    call PrintString

    ; enter big unreal mode (code < 64KiB, 4GiB data segment)
    call EnterUnrealMode
    lea si, [UnrealMode_OK_cstr]
    call PrintString

    ; init FAT file structures
    call InitFSInfo
    lea si, [DiskDetect_OK_cstr]
    call PrintString

    ; TODO: find file and load elf header
    call load_binary
    lea si, [FindFile_OK_cstr]
    call PrintString

    lea si, [OkMsg_cstr]
    call PrintString

    mov dword [CBootInfo + CBootInfoStruct.MemoryMapPtr], BIOSMemoryMap
    mov dword [CBootInfo + CBootInfoStruct.BPBDataPtr], BPB_DATA
    mov dword [CBootInfo + CBootInfoStruct.FSInfoPtr], FSInfo
    mov dword [CBootInfo + CBootInfoStruct.KInfoPtr], KInfo
    mov edx, CBootInfo                                                ; pointer to CBootInfo structure that has some useful information for the kernel

    call SetTextMode                    ; clear screen
    cli                                 ; disable interrupts
    lgdt [gdt32_info]                   ; load GDT register with start address of Global Descriptor Table
    mov eax, cr0
    or al, 1                            ; set PE (Protection Enable) bit in CR0 (Control Register 0)
    mov cr0, eax

    jmp $+2                             ; clear instruction cache
    jmp dword 08h:KERNEL_ENTRY

    ; TODO: parse elf/elf64 header to find where to load sections

; stop the system
hcf:
    hlt
    jmp short hcf

; EAX = error code
error_printer:
    call u32toStr
    lea si, [ErrorCodeMsg_cstr]
    call PrintString
    lea si, [u32toStr_buf]
    call PrintString
    jmp hcf

; ################
;
; STRING FUNCTIONS
;
; #################

; Prints a C-Style string (null terminated) using BIOS vga teletype call
; void PrintString(char* buf)
;
; si = pointer to C style string
; ax, bx are clobbered
PrintString:
    mov al, byte [si]           ; Get a byte from string and store in AL register
    cmp al, 00h                 ; Check if value in AL is zero (end of string)
    jz PrintString.endp         ; If end then return
    inc si                      ; Increment SI pointer if we arent at the end of the string

                                ; AL =  byte to display
    mov ah, 0x0E	            ; Tell BIOS that we need to print one charater on screen.
    mov bh, 0x00	            ; Page no.
    mov bl, 0x07	            ; Text attribute 0x07 is lightgrey font on black background
    int 0x10	                ; Call video interrupt

    jmp PrintString             ; Fetch next character from string
.endp:
    ret                         ; Return from procedure


; Sets output to 80x25 16 color text mode via BIOS call
; also clears screen
; void SetTextMode(void)
SetTextMode:
    xor ah, ah                  ; Set Video mode BIOS function
    mov al, 0x02                ; 16 color 80x25 Text mode
    int 0x10                    ; Call video interrupt

    mov ah, 0x05                ; Select active display page BIOS function
    xor al, al                  ; page 0
    int 0x10                    ; call video interrupt
.endp:
    ret

;
; Converts a uint32 to a ascii string representation
; void i32toStr (uint number)
; IN: EAX = number
; OUT: void
;
; EAX, EDX, CX are clobbered
u32toStr:
    push bx
    push cx

    mov edx, eax
    xor cx, cx                      ; character count
.next_place:
    mov eax, edx                    ; eax is our nibble, edx is the u32

    and eax, 0x000F
    cmp ax, 0x0A
    jge u32toStr.gte_0a

    add ax, 0x30                    ; less than 0x0a we add 0x30 for 0-9 in ascii
    jmp u32toStr.stack_number
.gte_0a:
    add ax, 0x37                    ; greater than or equal to 0x0a we add 0x37 for A-F in ascii
.stack_number:
    push ax
    shr edx, 4                      ; div by 16
    inc cx                          ; increase count
    test edx, edx
    jz u32toStr.build_buf
    jmp u32toStr.next_place

.build_buf:
    ; first character in buffer is u32toStr_buf+2, last is u32toStr_buf+9
    lea bx, [u32toStr_buf]
    add bx, 2                   ; point bx past '0x'
.next_byte_buf:
    pop ax
    and ax, 0x00FF
    mov byte [bx], al
    inc bx
    loop u32toStr.next_byte_buf

.endp:
    pop cx
    pop bx
    ret


; ####################
;
; END STRING FUNCTIONS
;
; ####################

; ##############################
;
; SYSTEM CONFIGURATION FUNCTIONS
;
; ##############################

; disables blinking text mode cursor
disable_cursor:
	pushf
	push eax
	push edx
 
	mov dx, 0x3D4
	mov al, 0xA	    ; low cursor shape register
	out dx, al
 
	inc dx
	mov al, 0x20	; bits 6-7 unused, bit 5 disables the cursor, bits 0-4 control the cursor shape
	out dx, al
 
	pop edx
	pop eax
	popf
	ret

;
;NT 0x15 Function 2400 - Disable A20
;Returns:
;
;   CF = clear if success
;   AH = 0
;   CF = set on error
;   AH = status (01=keyboard controller is in secure mode, 0x86=function not supported)
;
;INT 0x15 Function 2401 - Enable A20
;Returns:
;
;   CF = clear if success
;   AH = 0
;   CF = set on error
;   AH = status (01=keyboard controller is in secure mode, 0x86=function not supported)
;
;INT 0x15 Function 2402 - A20 Status
;   Returns:
;
;   CF = clear if success
;   AH = status (01: keyboard controller is in secure mode; 0x86: function not supported)
;   AL = current state (00: disabled, 01: enabled)
;   CX = set to 0xffff is keyboard controller is no ready in 0xc000 read attempts
;   CF = set on error
;
;INT 0x15 Function 2403 - Query A20 support
;Returns:
;
;CF = clear if success
;AH = status (01: keyboard controller is in secure mode; 0x86: function not supported)
;BX = status.
;
;BX contains a bit pattern:
;
;    Bit 0 - supported on keyboard controller
;    Bit 1 - if supported on bit 1 of I/O port 0x92
;    Bits 2:14 - Reserved
;    Bit 15 - 1 if additional data is available.
;
; I/O Port 0x92 infomation:
;
;    Bit 0 - Setting to 1 causes a fast reset
;    Bit 1 - 0: disable A20; 1: enable A20
;    Bit 2 - Manufacturer defined
;    Bit 3 - power on password bytes (CMOS bytes 0x38-0x3f or 0x36-0x3f). 0: accessible, 1: inaccessible
;    Bits 4-5 - Manufacturer defined
;    Bits 6-7 - 00: HDD activity LED off; any other value is "on"
;
EnableA20:
    push bx
    push cx
    ; end prolog

    ; checked this way since this will /always/ work
.a20_check:
    pushf
    push ds
    push es
    push di
    push si
    cli

    xor ax, ax
    mov es, ax

    not ax                      ; ax = 0xFFFF
    mov ds, ax

    mov di, 0x0500              ; scratch location 1
    mov si, 0x0510              ; scratch location 2

    mov al, byte [es:di]
    push ax                     ; save whatever is at 0x0000:0500, physical location 0x0500

    mov al, byte [ds:si]
    push ax                     ; save whatever is at 0xFFFF:0510 [clarification: 0x100500 physical location (0x100500 - 1MB = 0x0500)]

    mov byte [es:di], 0x00      ; zero non-wraped location and write 0xFF to it after (ab)using wrapping
    mov byte [ds:si], 0xFF      ; if the non-wrapped location is 0xFF, then we wraped and A20 is disabled

    cmp byte [es:di], 0xFF

    pop ax
    mov byte [ds:si], al        ; restore original contents of scratch location 2

    pop ax
    mov byte [es:di], al        ; restore original contents of scratch location 1

    mov ax, 0                   ; return 0 if es:di == ds:si (memory wraps)
    je EnableA20.end_check
    mov ax, 1                   ; return 1 if es:di != ds:si (A20 is enabled)
.end_check:
    pop si
    pop di
    pop es
    pop ds
    popf
    sti

    cmp ax, 1
    je EnableA20.endp         ; A20 is already enabled

    mov ax, 0x2403
    int 0x15
    jc EnableA20.do_fallback_a20    ; carry = error...not supported?
    cmp ah, 0
    ja EnableA20.do_fallback_a20   ; non-zero return = error as well

    mov al, bl
    and al, 0000_0010b
    cmp al, 0000_0010b
    je EnableA20.do_fast_a20        ; if fast a20 is supported use it

    jmp EnableA20.do_bios_a20       ; else fall back to enabling via BIOS

.do_fallback_a20:
    ; TODO: write keyboard microcontroler method for enabling A20
    mov eax, A20_FAILURE
    jmp error_printer

.do_bios_a20:
    mov ax, 0x2401
    int 0x15
    jmp EnableA20.a20_check
.do_fast_a20:
    in al, 0x92                 ; read from FAST A20 port
    or al, 2                    ; bit 0 is a fast reset, bit 1 is fast A20
    and al, 0xFE                ; make sure bit 0 is 0
    out 0x92, al                ; enable A20
    jmp EnableA20.a20_check
.endp:
    pop cx
    pop bx

    ret


EnterUnrealMode:
    cli                         ; no interrupts
    push ds                     ; save real mode
    push bx

    lgdt [unreal_gdt_info]

    mov  eax, cr0               ; switch to pmode
    or al,1                     ; set pmode bit
    mov  cr0, eax

    jmp $+2                     ; clear instruction cache

    mov  bx, 0x08               ; select descriptor 1
    mov  ds, bx                 ; 8h = 1000b

    and al,0xFE                 ; back to realmode
    mov  cr0, eax               ; by toggling bit again

    pop bx
    pop ds                      ; get back old segment
    sti
.endp:
    ret


; ##################################
;
; END SYSTEM CONFIGURATION FUNCTIONS
;
; ##################################


; ##########################
;
; DISK AND FILE IO FUNCTIONS
;
; ##########################

; Setup required calculations for working with FAT12 disk
; and load all FAT's to memory
;
; IN:   SI = address of BPB/EBPB structure
InitFSInfo:
    push bx
    push cx
    push es

.calc_root_dir:
    ;-- calculate the total root directory length (in sectors)
    mov ax, word [BPB_DATA + BPBStruct.RootDirEnts]
    shl ax, 0x05                        ; bsRootDirEnts * 32

    mov bx, word [BPB_DATA + BPBStruct.BytesPerSect]
    push bx                             ; save original BytesPerSect
    dec bx                              ; bsBytesPerSect - 1

    add ax, bx                          ; AX = (bsRootDirEnts * 32) + (bsBytesPerSect -1)

    pop bx                              ; restore original bx
    xor dx, dx
    div bx                              ; quotient in AX, remainder in DX

    mov word [FSInfo + FSInfoStruct.root_dir_len], ax         ; store value in root_dir_len

.calc_rootdir_sect:
    ;-- calculate the first root_dir sector location
    mov dx, [BPB_DATA + BPBStruct.SectPerFAT]
    movzx ax, byte [BPB_DATA + BPBStruct.FATs]
    mul dx

    mov dx, word [BPB_DATA + BPBStruct.ResSectors]
    add ax, dx
    mov word [FSInfo + FSInfoStruct.first_root_dir_sector], ax

    mov bx, word [FSInfo + FSInfoStruct.root_dir_len]
    add ax, bx
    mov word [FSInfo + FSInfoStruct.last_root_dir_sector], ax

.calc_data_sect:
    ;-- calculate the first data sector
    movzx ax, byte [BPB_DATA + BPBStruct.FATs]
    mov bx, word [BPB_DATA + BPBStruct.SectPerFAT]
    mul bx                                                      ; bsFATs * bsSectPerFAT = DX:AX
    ja InitFSInfo.dat_no_OF                                     ; if mul operation fits in AX, CF=0, ZF=0

    mov eax, FS_MUL_OVERFLOW
    call error_printer                                          ; if AX*BX is > a word, error

.dat_no_OF:
    mov bx, word [BPB_DATA + BPBStruct.ResSectors]
    add ax, bx                                                  ; bsReservedSectors + AX

    mov bx, word [FSInfo + FSInfoStruct.root_dir_len]
    add ax, bx                                                  ; + root_dir_len

    mov word [FSInfo + FSInfoStruct.first_data_sector], ax      ; store in first_data_sector

    ;-- store entire FAT in memory
    mov ax, word [BPB_DATA + BPBStruct.ResSectors]              ; first sector of FAT
    mov cx, word [BPB_DATA + BPBStruct.SectPerTrack]            ; 18 sectors to load TODO: fix this, there are 2 FAT's at 9 sectors a piece so it equals a full track...but this isn't right
    xor bx, bx
    mov es, bx
    mov bx, FAT_Table                                           ; populate FAT table
.load_fat:
    push cx

    call read_sector                                            ; AX and BX (and maybe ES) are incremented after each call to read_sector
    pop cx
    loop InitFSInfo.load_fat                                    ; CX is deincremented after each loop

.endp:

    pop es
    pop cx
    pop bx
    ret

; load configured boot entries and options
read_bootconf:
; TODO: Load boot entries
; TODO: Should consist of a BootMenu name and path to executable for ELF
; TODO: and a BootMenu name, path, and memory address to load file to for BIN
; TODO: for ELFs there should later be an option to enable multiboot/multiboot2 and a way to pass arguments to the ELF
.endp:

; load a configured ELF boot menu option and determine if it is a ELF32/64 and load accordingly
parse_elf:

; load a elf32 file to the elf headers specified points in memory
.load_elf32:
; TODO: Everything
.elf32_endp:

; load an elf64 file, this is only supported if the entry point is in the lower 4GiB of memory
.load_elf64:
; TODO: Everything, get elf32 working first
.elf64_endp:

; find and load a binary executable
load_binary:
    mov dword [high_mem_dest__DWORD], KERNEL_ENTRY
    mov word [buf_bytes_used__WORD], 0

    mov ax, [FSInfo + FSInfoStruct.first_root_dir_sector]
    xor bx, bx
    mov es, bx
    mov bx, directory_ent_buf                                   ; setup to write to dir entry buffer
    push ax
    push bx                                                     ; setup stack
.next_sector:
    pop bx
    pop ax

    cmp ax, word [FSInfo + FSInfoStruct.last_root_dir_sector]
    jg load_binary.file_error                                     ; we do not have to fix the stack from here

    call read_sector                                            ; load 1 disk sector of Directory entries to memory

    push ax                                                     ; store next sector for next load_binary.next_sector
    sub bx, 0x200                                               ; restore bx to start of buffer for next read
    push bx                                                     ; store buffer location for next load_binary.next_sector

.next_entry:
; scan through 8.3 filenames in this sector until found or at end of sector
; loop back to next_sector if not found
    cmp bx, directory_ent_buf+0x200
    je load_binary.next_sector                                    ; if we are at the end of buffer, load the next sector

    mov cx, 0xA                     ; max of 11 filename length of 11 characters
    lea si, [filename]              ; filename in si
    mov di, bx                      ; current memory location (8.3 name is at offset 0)
    add bx, 0x20                    ; move bx to the next entry
    repe cmpsb                      ; compare the strings
    jne load_binary.next_entry

.found:
; if we found the file in the current sector, get some more information about it
; like file size and first fat cluster

    sub bx, 0x06                    ; read first FAT cluster (offset 26)
    mov ax, word [bx]
    mov word [ff_first_fat__WORD], ax

    mov word [FSInfo + FSInfoStruct.active_cluster], ax
    mov di, DISK_BUFFER
.load_file:
; read file we found from data sectors to the osloader entry point (0x8000)
; this involves walking the FAT cluster chain and checking for 0x0FFF (end of file)
; first_sector_of_cluster = ((cluster - 2) * fat_boot->sectors_per_cluster) + first_data_sector
; fat_offset = active_cluster + (active_cluster / 2);// multiply by 1.5
; ent_offset = fat_offset % section_size;
;
    cmp di, DISK_BUFFER + DISK_BUFFER_LEN
    jne load_binary.no_flush

.flush_buffer:
    mov si, DISK_BUFFER
    mov cx, DISK_BUFFER_LEN
    mov eax, [high_mem_dest__DWORD]     ; load current position in high mem location
.copy_to_himem:
    mov bl, byte [si]
    mov byte [ds:eax], bl
    inc eax
    inc si
    loop load_binary.copy_to_himem
    mov [high_mem_dest__DWORD], eax     ; save current position in high mem location
    mov word [buf_bytes_used__WORD], 0  ; reset byte count on flush
    mov di, DISK_BUFFER                 ; reset to start of low mem disk buffer

.no_flush:

    ; first_sector_of_cluster = ((cluster - 2) * fat_boot->sectors_per_cluster) + first_data_sector
    mov ax, word [FSInfo + FSInfoStruct.active_cluster]
    sub ax, 0x2
    movzx dx, byte [BPB_DATA + BPBStruct.SecsPerClust]
    mul dx
    mov dx, word [FSInfo + FSInfoStruct.first_data_sector]
    add ax, dx

    xor bx, bx
    mov es, bx
    mov bx, di                              ;ES:BX = destination, AX = LBA
    call read_sector
    mov di, bx                              ; save updated next sector
    add word [buf_bytes_used__WORD], 0x0200

.fat12_next:
    ;-- Look up next cluster for FAT12
    ; fat_offset = active_cluster + (active_cluster / 2);
    mov ax, word [FSInfo + FSInfoStruct.active_cluster]
    mov bx, ax
    shr ax, 1
    add bx, ax
    mov word [FSInfo + FSInfoStruct.active_FAT_cluster], bx

    mov si, FAT_Table
    mov ax, word [bx + si]                   ; look up value at FAT cluster

    test word [FSInfo + FSInfoStruct.active_cluster], 0x0001
    jz load_binary.is_odd_cluster
    shr ax, 0x4
    jmp load_binary.test_fat
.is_odd_cluster:
    and ax, 0x0FFF
.test_fat:
    cmp ax, 0x0FF8
    jge load_binary.end_file                                    ; end of file marker found

    cmp ax, 0x0FF7
    jl load_binary.valid_cluster
    inc ax                                                    ; move to the next cluster if the current one is marked as a bad cluster
.valid_cluster:
    mov word [FSInfo + FSInfoStruct.active_cluster], ax       ; else update active cluster with the next cluster and load the next sector
    jmp load_binary.load_file                                   ; do this until we find the end of file cluster chain marker

.stack_fixup_and_error:
    add sp, 0x04                        ; add 4 (2 words) to SP to fix it if we error after load_binary.next_sector                                      ; since we use the stack to store the next directory entry disk sector to read
.file_error:
    mov eax, FF_FILE_NOT_FOUND
    call error_printer

.end_file:
    cmp word [buf_bytes_used__WORD], 0
    je load_binary.endp                   ; no need to flush if buffer is empty (multiple of 4KiB)

    mov si, DISK_BUFFER
    mov cx, word [buf_bytes_used__WORD]
    shl cx, 0x09
    mov eax, [high_mem_dest__DWORD]
.copy_to_himem_final:
    mov bl, byte [si]
    mov byte [ds:eax], bl
    inc eax
    inc si
    loop load_binary.copy_to_himem_final
    mov [high_mem_dest__DWORD], eax
    mov word [buf_bytes_used__WORD], cx

.endp:
    add sp, 0x04                        ; fix stack before returning
    ret



; ##############################
;
; END DISK AND FILE IO FUNCTIONS
;
; ##############################


; ##############################
;
; BIOS call wrappers
;
; ##############################

; Read sector from disk
; In:	AX - LBA to read
; 		ES:BX - offset of transfer buffer destination

; Out:  AX - next sector
;       BX - BX + 0x200
;
;   ES can be incremented by 0x1000 if BX wraps!
;
; Details of BIOS call
;   AH = 02
;	AL = number of sectors to read
;	CH = track/cylinder number  (0-1023 dec., see below)
;	CL = sector number  (1-17 dec.)
;	DH = head number  (0-15 dec.)
;	DL = drive number (0=A:, 1=2nd floppy, 80h=drive 0, 81h=drive 1)
;	ES:BX = pointer to buffer
;
; At least AX, CX, DX are clobbered
; memory at ES:BX -> ES:BX+(AL-1) are overwritten
read_sector:
    push ax                             ; save original LBA for return value
    mov word [retry_count__WORD], 0     ; reset disk retry count

.lba_to_chs:
    mov word [CHS_LBA__WORD], ax         ; TODO: fix up these varibles

.get_temp:
    xor dx, dx
    div word [BPB_DATA + BPBStruct.SectPerTrack]
    mov word [CHS_Temp__WORD], ax        ; TODO: fix up these varibles

.get_sect:
    xor dx, dx
    mov ax, word [CHS_LBA__WORD]         ; TODO: fix up these varibles
    div word [BPB_DATA + BPBStruct.SectPerTrack]           ; (LBA % (Sectors per Track))

    inc dx                  ; +1
    push dx                 ; remainder = Sector

.get_head:
    xor dx, dx
    mov ax, word [CHS_Temp__WORD]        ; TODO: fix up these varibles
    div word [BPB_DATA + BPBStruct.Heads]      ; Temp % Heads

    push dx                 ; remainder = head

; this isn't quite correct, Cylinder/track is the 8 MSB of CX and the 2 MSB of CL
; with the sector in the 6 LSB of CL. This will work as long as there are less than 255 Cylinders/Tracks
.get_cyl:
    xor dx, dx
    mov ax, word [CHS_Temp__WORD]
    div word [BPB_DATA + BPBStruct.Heads]      ; Temp / Heads

    push ax                 ; quotient = cylinder

.end_lba_conv:
    xor ax, ax
    mov cx, ax
    mov dx, ax

    pop ax
    mov ch, al              ; Cylinder

    pop ax
    mov dh, al              ; Head

    pop ax
    mov cl, al              ; Sector

    mov dl, [BPB_DATA + BPBStruct.DriveNumber]

.do_read:
    mov ax, 0x0201          ; to get around the annoying 127 sector limit on reads, we will read 1 sector at a time per call
                            ; disk read BIOS call index, AH = 0x02, AL=0x01
    int 0x13
    jnc read_sector.endp

.reset_disk:
    cmp word [retry_count__WORD], MAX_DISK_RETRY
    ja read_sector.disk_fail

    xor ax, ax
    int 0x13                                ; reset disk BIOS call

    inc word [retry_count__WORD]
    jmp read_sector.do_read

.disk_fail:
    mov eax, DISK_READ_RETRY_FAILURE
    call error_printer

.endp:
    pop ax
    inc ax                  ; next LBA sector
    add bx, 0x200           ; add a sector to bx
    jnc read_sector.no_bx_overflow

    mov dx, es
    add dh, 0x10            ; ...add 1000h to ES, new segment. ie. IP = (CS << 4) + PC
    mov es, dx
.no_bx_overflow:
    ret
; Address Range Descriptor Structure
;
; Offset in Bytes		Name		Description
;	0	    BaseAddrLow		Low 32 Bits of Base Address
;	4	    BaseAddrHigh	High 32 Bits of Base Address
;	8	    LengthLow		Low 32 Bits of Length in Bytes
;	12	    LengthHigh		High 32 Bits of Length in Bytes
;	16	    Type		Address type of  this range.
; Address Range Descriptor Structure
;
; Offset in Bytes		Name		Description
;	0	    BaseAddrLow		Low 32 Bits of Base Address
;	4	    BaseAddrHigh	High 32 Bits of Base Address
;	8	    LengthLow		Low 32 Bits of Length in Bytes
;	12	    LengthHigh		High 32 Bits of Length in Bytes
;	16	    Type		Address type of  this range.
; Input:
;
;	EAX	Function Code	E820h
;	EBX	Continuation	Contains the "continuation value" to get the
;				next run of physical memory.  This is the
;				value returned by a previous call to this
;				routine.  If this is the first call, EBX
;				must contain zero.
;	ES:DI	Buffer Pointer	Pointer to an  Address Range Descriptor
;				structure which the BIOS is to fill in.
;	ECX	Buffer Size	The length in bytes of the structure passed
;				to the BIOS.  The BIOS will fill in at most
;				ECX bytes of the structure or however much
;				of the structure the BIOS implements.  The
;				minimum size which must be supported by both
;				the BIOS and the caller is 20 bytes.  Future
;				implementations may extend this structure.
;	EDX	Signature	'SMAP' -  Used by the BIOS to verify the
;				caller is requesting the system map
;				information to be returned in ES:DI.
;
; Output:
;
;	CF	Carry Flag	Non-Carry - indicates no error
;	EAX	Signature	'SMAP' - Signature to verify correct BIOS
;				revision.
;	ES:DI	Buffer Pointer	Returned Address Range Descriptor pointer.
;				Same value as on input.
;	ECX	Buffer Size	Number of bytes returned by the BIOS in the
;				address range descriptor.  The minimum size
;				structure returned by the BIOS is 20 bytes.
;	EBX	Continuation	Contains the continuation value to get the
;				next address descriptor.  The actual
;				significance of the continuation value is up
;				to the discretion of the BIOS.  The caller
;				must pass the continuation value unchanged
;				as input to the next iteration of the E820
;				call in order to get the next Address Range
;				Descriptor.  A return value of zero means that
;				this is the last descriptor
;
; Address Range Descriptor Structure
;
; Offset in Bytes		Name		Description
;	0	    BaseAddrLow		Low 32 Bits of Base Address
;	4	    BaseAddrHigh	High 32 Bits of Base Address
;	8	    LengthLow		Low 32 Bits of Length in Bytes
;	12	    LengthHigh		High 32 Bits of Length in Bytes
;	16	    Type		Address type of  this range.
;
; The BaseAddrLow and BaseAddrHigh together are the 64 bit BaseAddress of this range.
; The BaseAddress is the physical address of the start of the range being specified.
;
; The LengthLow and LengthHigh together are the 64 bit Length of this range.
; The Length is the physical contiguous length in bytes of a range being specified.
;
; The Type field describes the usage of the described address range as defined in the table below.

; Value	       Pneumonic		           Description
;   1	    AddressRangeMemory	    This run is available RAM usable by the operating system.
;   2	    AddressRangeReserved	This run of addresses is in use or reserved by the system, and must not be used by the operating system.
; Other	    Undefined		        Undefined - Reserved for future use.
detect_memory_E820:
    push es         ; save segment registers

    push bx
    shr ebx, 16
    push bx         ; save ebx on a 16bit stack

    push cx
    shr ecx, 16
    push cx         ; save ecx on a 16bit stack
    ; end prolog
    mov dword [CBootInfo + CBootInfoStruct.MemoryMapEntries], 0

    mov eax, 0xE820                 ; select 0xE820 function
    mov ebx, 0x0000                 ; Continuation value

    mov dx, (BIOSMemoryMap >> 4)
    mov es, dx
    mov di, 0                      ; (BIOSMemoryMap >> 4):0 makes di an index into BIOSMemoryMap

    mov ecx, AddressRangeDescStruct_size
    mov edx, 0x534D4150                ; 'SMAP' magic

    int 0x15
    jnc detect_memory_E820.no_error

    mov eax, MM_E820_NO_SUPPORT
    jmp error_printer

.no_error:
    inc dword [CBootInfo + CBootInfoStruct.MemoryMapEntries]
    cmp eax, 0x534D4150
    jne detect_memory_E820.no_smap_returned

    cmp ecx, 20
    jb detect_memory_E820.nonstandard_e820

    cmp ebx, 0
    je detect_memory_E820.endp                  ; 0 in ebx means we have reached the end of memory ranges

    add di, AddressRangeDescStruct_size         ; increment di to next descriptor
    mov edx, eax                                ; 'SMAP' to edx
    mov eax, 0xE820                             ; select E820 function

    int 0x15
    jnc detect_memory_E820.no_error             ; carry indicates an error

.other_error:
    mov eax, MM_E820_MISC_ERR
    jmp error_printer
.nonstandard_e820:
    mov eax, MM_E820_NONSTANDARD
    jmp error_printer
.no_smap_returned:
    mov eax, MM_E820_NO_SMAP
    jmp error_printer

.endp:
    xor ebx, ebx
    xor ecx, ecx

    pop cx
    shl ecx, 16
    pop cx

    pop bx
    shl ebx, 16
    pop bx

    pop es

    ret

; ##############################
;
; end BIOS call wrappers
;
; ##############################

;-- Data
%define StrCRLF_NUL 0Dh, 0Ah, 00h

HelloPrompt_cstr:
    db 'CBoot', StrCRLF_NUL
OkMsg_cstr:
    db 'Booting!', StrCRLF_NUL
A20_OK_cstr:
    db '[ok] A20 gate enabled', StrCRLF_NUL
UnrealMode_OK_cstr:
    db '[ok] Unreal mode enabled', StrCRLF_NUL
DiskDetect_OK_cstr:
    db '[ok] boot disk detected', StrCRLF_NUL
FindFile_OK_cstr:
    db '[ok] loaded kernel', StrCRLF_NUL
MemMap_OK_cstr:
    db '[ok] Memory map detection', StrCRLF_NUL

; print this, then u32toStr_buf for errors
ErrorCodeMsg_cstr:
    db 'Error -> ', 00h
u32toStr_buf:
    db '0x00000000', StrCRLF_NUL

filename:
    db 'BOOTTESTBIN'

; GDT documentation below:
;
;    Pr: Present bit. This must be 1 for all valid selectors.
;
;    Privl: Privilege, 2 bits. Contains the ring level,
;           0 = highest (kernel), 3 = lowest (user applications).
;
;    S: Descriptor type. This bit should be set for code or data segments
;       and should be cleared for system segments (eg. a Task State Segment)
;
;    Ex: Executable bit. If 1 code in this segment can be executed
;        ie. a code selector. If 0 it is a data selector.
;
;    DC: Direction bit/Conforming bit.
;        Direction bit for data selectors: Tells the direction.
;        0 the segment grows up. 1 the segment grows down, ie. the offset has to be greater than the limit.
;
;        Conforming bit for code selectors:
;            If 1 code in this segment can be executed from an equal or lower privilege level.
;               For example, code in ring 3 can far-jump to conforming code in a ring 2 segment.
;               The privl-bits represent the highest privilege level that is allowed to execute the segment.
;                   For example, code in ring 0 cannot far-jump to a conforming code segment with privl==0x2
;                   while code in ring 2 and 3 can. Note that the privilege level remains the same
;                   ie. a far-jump form ring 3 to a privl==2-segment remains in ring 3 after the jump.
;
;            If 0 code in this segment can only be executed from the ring set in privl.
;
;    RW: Readable bit/Writable bit.
;        Readable bit for code selectors: Whether read access for this segment is allowed. Write access is never allowed for code segments.
;        Writable bit for data selectors: Whether write access for this segment is allowed. Read access is always allowed for data segments.
;
;    Ac: Accessed bit. Just set to 0. The CPU sets this to 1 when the segment is accessed.
;
;    Gr: Granularity bit. If 0 the limit is in 1 B blocks (byte granularity), if 1 the limit is in 4 KiB blocks (page granularity).
;
;    Sz: Size bit. If 0 the selector defines 16 bit protected mode. If 1 it defines 32 bit protected mode.
;        You can have both 16 bit and 32 bit selectors at once.
;
;    AvL: Availible to software bit, the CPU does not use this field and software can read/write to it
;
;    D/B bit: The default operand-size bit is found in code-segment and data-segment descriptors but not in system-segment descriptors. Setting
;              this bit to 1 indicates a 32-bit default operand size, and clearing it indicates a 16-bit default size.
;
;    E bit: Expand down bit: Setting this bit to 1 identifies the data segment as expand-down.
;           In expand-down segments, the segment limit defines the lower segment boundary while the base is the upper boundary
;
; A GDT entry is 8 bytes and is constructed as follows:
; First DWORD
;   0-15	Limit 0:15	First 16 bits in the segment limiter
;   16-31	Base 0:15	First 16 bits in the base address
;
; 2nd DWORD
;
;   0:7	    Base 16:23	Bits 16-23 in the base address
;   8:12	S/Type	    Segment type and attributes, S = bit 12, Type = 8:11, Type is either [1, DC, RW, Ac] <code> or [0, E, RW, Ac] <data>
;   13:14	Privl	    0 = Highest privilege (OS), 3 = Lowest privilege (User applications)
;   15	    Pr	        Set to 1 if segment is present
;   16:19	Limit 16:19	Bits 16-19 in the segment limiter
;   20:22	Attributes	Different attributes, depending on the segment type
;   23	    Gr	        Used together with the limiter, to determine the size of the segment
;   24:31	Base 24:31	The last 24-31 bits in the base address
;
;
;

ALIGN 4, db 0
unreal_gdt_info:
    unreal_gdt_size: dw (unreal_gdt_end - unreal_gdt_start) - 1
    unreal_gdt_ptr:  dd unreal_gdt_start

unreal_gdt_start:
    ; entry 0
    dq 0                    ; first entry is null

    ; entry 1 (4 GiB flat data map)
    ; first dword
    dw 0xFFFF               ; 0:15 limit
    dw 0x0000               ; 0:15 base
    ; second dword
    db 0x00                 ; 16:23 base
    db 1001_0010b            ; bit 0:4 = S/Type, [1, DC, RW, Ac] <code> or [0, E, RW, Ac] <data>
                            ; bit 5:6 = Privl
                            ; bit 7   = Present

    db 1000_1111b            ; bit 0:3 = 16:19 of Limit
                            ; bit 4 = Availible to software bit
                            ; bit 5 = Reserved (?)
                            ; bit 6 = D/B bit, depending on if this is code/data 1 = 32 bit operands or stack size
                            ; bit 7 = Granularity bit. 1 = multiply limit by 4096
    db 0x00                 ; base 24:31
    ; at the end of the day...
    ; base = 0x00000000
    ; limit = 0xFFFFF
    ; Accessed = 0, ignore this field
    ; RW = 1, data is Read/Write
    ; E = 0, Expand up, valid data is from base -> limit, if 1 valid data is from (limit + 1) -> base
    ; C/D = 0, Segment is a data segment
    ; S = 1, Segment is a system segment
    ; Privl = 00b, Ring0 segment
    ; Pr = 1, segment is present
    ; AVL = 0, ignore this field
    ; D/B bit = 0, 16bit code/stack
    ; Gr = 1, multiply limit by 4096
unreal_gdt_end:

ALIGN 4, db 0
gdt32_info:
    gdt32_size: dw (gdt32_end - gdt32_start) - 1
    gdt32_ptr:  dd gdt32_start

; check above for detailed information
gdt32_start:
    dq 0
    .gdt32_code:
        dw 0xFFFF
        dw 0x0000
        db 0x00
        db 1001_1000b
        db 1100_1111b
        db 0x00
    .gdt32_data:
        dw 0xFFFF
        dw 0x0000
        db 0x00
        db 1001_0010b
        db 1100_1111b
        db 0x00
gdt32_end:

%assign bytes_remaining ((MAX_OSLDR_BYTES - 4) - ($ - $$))
%warning OSLOADER has bytes_remaining bytes remaining for code (MAX: MAX_OSLDR_BYTES)

; this is here to make the stage2 bigger than 1 sector for testing
times ((MAX_OSLDR_BYTES - 4) - ($ - $$)) db 0x00
OSLDR_SIG: dd 0xDEADBEEF