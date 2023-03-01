[BITS 16]
[ORG 0x0600]
[CPU KATMAI]

;
;
; This file is the same as floppyboot.S, no work has been done to support FAT16/32 volumes
;
;

jmp short entry
nop

;-- BPB (BIOS Parameter Block)
%define bsOemName      bp+0x03
%define bsBytesPerSect bp+0x0B
%define bsSecsPerClust bp+0x0D
%define bsResSectors   bp+0x0E
%define bsFATs         bp+0x10
%define bsRootDirEnts  bp+0x11
%define bsSectors      bp+0x13
%define bsMedia        bp+0x15
%define bsSectPerFAT   bp+0x16
%define bsSectPerTrack bp+0x18
%define bsHeads        bp+0x1A
%define bsHidden       bp+0x1C
%define bsSectorHuge   bp+0x20

db 'CBOOTLDR'                           ; OEM label (up to 8 bytes, padded with spaces)
dw 0x0200                               ; bytes/sector (dw)
db 0x01                                 ; sectors/allocation unit (db)
dw 0x0001                               ; reserved sectors (dw)
db 0x02                                 ; number of fats (db)
dw 0x00E0                               ; max # of root dir entries (dw)
dw 0x0B40                               ; sectors total in image (dw)
db 0xF0                                 ; media descriptor (db)
dw 0x0009                               ; sectors in a fat (dw)
dw 0x0012                               ; sectors/track (dw)
dw 0x0002                               ; heads (dw)
dd 0x00000000                           ; hidden sectors (dd)
dd 0x00000000                           ; sectors if |s| > 65536 (dd)
;-- End BPB

;-- EBPB (Extended BIOS Parameter Block)
%define bsDriveNumber   bp+0x24
%define bsNTFlags       bp+0x25
%define bsSigniture     bp+0x26
%define bsVolumeSerial  bp+0x27
%define bsVolumeLabel   bp+0x2B
%define bsSysID         bp+0x36

db 0x01                             ; drive number from int 0x13 or in DL (db)
db 0x00                             ; Reserved or Flags in NT (db)
db 0x29                             ; Signature (must be 0x28 or 0x29) (db)
dd 0xDEADBEEF                       ; VolumeID 'Serial' number. (dd)
times 0x0B db 0x20                  ; Volume label string. This field is padded with spaces (11)
db 'FAT12   '                       ; System identifier string. Representation of the FAT file system type. (8)
;-- End EBPB

; Generic Low mem map (from osdev wiki)
; start 	        end 	    size 	        type 	                    description
; Low Memory (the first MiB)
; 0x00000000 	0x000003FF 	1 KiB 	        RAM - partially unusable  	Real Mode IVT (Interrupt Vector Table)
; 0x00000400 	0x000004FF 	256 bytes 	    RAM - partially unusable 	BDA (BIOS data area)
; 0x00000500 	0x00007BFF 	almost 30 KiB 	RAM - free for use 	        Conventional memory
; 0x00007C00  	0x00007DFF 	512 bytes 	    RAM - partially unusable  	Your OS BootSector
; 0x00007E00 	0x0007FFFF 	480.5 KiB 	    RAM - free for use 	        Conventional memory
; 0x00080000 	0x0009FFFF 	128 KiB 	    RAM - partially unusable 	EBDA (Extended BIOS Data Area)
; 0x000A0000 	0x000FFFFF 	384 KiB 	    various (unusable) 	        Video memory, ROM Area


; Some FAT and CHS formulas
;
; first_fat_sector = bsResSectors;
; root_dir_sectors = ((bsRootDirEnts * 32) + (bsBytesPerSect - 1)) / bsBytesPerSect;
; first_data_sector = bsResSectors + (bsFATs * bsSectPerFAT) + root_dir_sectors;
; data_sectors = bsSectors - (bsResSectors + (bsFATs * bsSectPerFAT) + root_dir_sectors);
; total_clusters = data_sectors / bsSectsPerClust
; first_sector_of_cluster = ((cluster - 2) * fat_boot->sectors_per_cluster) + first_data_sector;
; Sectors are 1 based, not 0 based, accessing 0 results in an error
; on a typical 1.44MB floppy, there are 2 tracks, 80 cylinders and 18 sectors per track, 512 bytes per sector
; 2 * 80 * 18 = 2880, 2880 * 512 bytes = 1.44MiB
;
; Temp = LBA / (Sectors per Track)
; Sector = (LBA % (Sectors per Track)) + 1
; Head = Temp % (Number of Heads)
; Cylinder = Temp / (Number of Heads)
;

;-- Constants
; 0x600 -> 0x7FF is the MBR
%define REALLOC_ADDR          0x0600
; 0x2400 bytes for fats
%define FAT_TablePtr          0x0800
; 0x400 Bytes for RootDir entries, dont need a lot to look up the first few files
%define RootDir_TablePtr      0x2C00

;-- Data (Temp "heap")
%define first_root_dir_sector 0x3000
%define last_root_dir_sector  0x3002
%define root_dir_len          0x3004
%define first_data_sector     0x3006
%define osldr_first_fat       0x3008
%define osldr_len             0x300A

; Scratch locations for CHS to LBA function
%define CHS_Temp_Word         0x300E
%define CHS_LBA_Word          0x3010

%define active_cluster        0x3012
%define active_cluster_FAT    0x3014

%define disk_retry_count      0x3016

%define directory_ent_buf     0x3100
; gives us 4 KiB of heap space, more than enough for variables
%define HEAP_END              0x4000
;-- End Data

; 8 KiB stack, again more than enough
%define STACK_START           0x6000
%define BIOS_ENTRY            0x7C00
%define OSLDR_ENTRY           0x8000

;
; Error codes
; A = Overflow in data sector calculation in main.calc_data_sect
; B = File not found in find_file
; C = Disk read/retry failure in read_sector
; D = ES overflow in read_sector

entry:
    cli                         ; We do not want to be interrupted

    xor ax, ax                  ; 0 AX
    mov ds, ax                  ; Set segment registers to 0
    mov es, ax                  ; *
    mov fs, ax                  ; *
    mov gs, ax                  ; *

    mov ss, ax                  ; Set Stack Segment to 0
    mov sp, STACK_START         ; Setup stack

    mov ch, 0x01                ; 256 WORDs in MBR (512 bytes), 0x0100 in cx
    mov si, BIOS_ENTRY          ; Current MBR Address (loaded here by BIOS)
    mov di, REALLOC_ADDR        ; New MBR Address (our new relocation address)
    rep movsw                   ; copy 512 bytes from 0x0000:7c00 to 0x0000:0600

    mov bp, REALLOC_ADDR        ; move BP to the new start of the initial boot sector
    mov [bsDriveNumber], dl     ; BIOS passes drive number in DL

    sti                         ; all done with inital setup and relocation, reenable interupts
    jmp 0:main                  ; fix up cs:ip just in case and jump to relocated code

main:

.calc_root_dir:
    ;-- calculate the total root directory length (in sectors)
    mov ax, word [bsRootDirEnts]
    shl ax, 0x05                        ; bsRootDirEnts * 32

    mov bx, word [bsBytesPerSect]
    push bx                             ; save original BytesPerSect
    dec bx                              ; bsBytesPerSect - 1

    add ax, bx                          ; AX = (bsRootDirEnts * 32) + (bsBytesPerSect -1)

    pop bx                              ; restore original bx
    xor dx, dx
    div bx                              ; quotient in AX, remainder in DX

    mov word [root_dir_len], ax         ; store value in root_dir_len

.calc_rootdir_sect:
    ;-- calculate the first root_dir sector location
    mov dx, [bsSectPerFAT]
    movzx ax, byte [bsFATs]
    mul dx

    mov dx, word [bsResSectors]
    add ax, dx
    mov word [first_root_dir_sector], ax

    mov bx, word [root_dir_len]
    add ax, bx
    mov word [last_root_dir_sector], ax  ; calculate the last root dir entry ahead of time

.calc_data_sect:
    ;-- calculate the first data sector
    movzx ax, byte [bsFATs]
    mov bx, word [bsSectPerFAT]
    mul bx                              ; bsFATs * bsSectPerFAT = DX:AX
    ja main.dat_no_OF                   ; if mul operation fits in AX, CF=0, ZF=0
    mov al, "A"                         ; if AX*BX is > a word, error
    jmp early_error                     ; it means the FAT is larger than 64k
                                        ; and this wont happen on a floppy
.dat_no_OF:
    mov bx, word [bsResSectors]
    add ax, bx                          ; bsReservedSectors + AX

    mov bx, word [root_dir_len]
    add ax, bx                          ; + root_dir_len

    mov word [first_data_sector], ax    ; store in first_data_sector

    ;-- store entire FAT in memory
    mov ax, word [bsResSectors]     ; first sector of FAT
    mov cx, word [bsSectPerTrack]   ; 18 sectors to load TODO: fix this, there are 2 FAT's at 9 sectors a piece so it equals a full track...but this isn't right

    mov bx, FAT_TablePtr            ; initially load ES = 0, BX = 0xA00
.load_fat:
    push cx
    call read_sector                ; AX and BX (and maybe ES) are incremented after each call to read_sector
    pop cx
    loop main.load_fat              ; CX is deincremented after each loop
.end_load_fat:

    call find_file                  ; load OSLOADER.BIN
    mov dx, REALLOC_ADDR+3          ; pass address of BPB to stage2 in dx
    jmp 0:OSLDR_ENTRY               ; off to stage2 :)

; find and load a file
find_file:
    mov ax, [first_root_dir_sector]

    mov bx, directory_ent_buf       ; setup to write to dir entry buffer
    push ax
    push bx                         ; setup stack
.next_sector:
    pop bx
    pop ax

    cmp ax, word [last_root_dir_sector]
    jg find_file.file_error         ; we do not have to fix the stack from here

    call read_sector                ; load 1 disk sector of Directory entries to memory

    push ax                         ; store next sector for next find_file.next_sector
    sub bx, 0x200                   ; restore bx to start of buffer for next read
    push bx                         ; store buffer location for next find_file.next_sector

.next_entry:
; scan through 8.3 filenames in this sector until found or at end of sector
; loop back to next_sector if not found
    cmp bx, directory_ent_buf+0x200
    je find_file.next_sector        ; if we are at the end of buffer, load the next sector

    cmp byte [bx], 0x0
    je find_file.endp               ; empty dir entry, end of file listings

    mov cx, 0xA                     ; max of 11 filename length of 11 characters
    lea si, [filename]              ; filename in si
    mov di, bx                      ; current memory location (8.3 name is at offset 0)
    add bx, 0x20                    ; move bx to the next entry
    repe cmpsb                      ; compare the strings
    jne find_file.next_entry

.found:
; if we found the file in the current sector, get some more information about it
; like file size and first fat cluster

    sub bx, 0x06                    ; read first FAT cluster (offset 26)
    mov ax, word [bx]
    mov word [osldr_first_fat], ax

    mov word [active_cluster], ax
    mov di, OSLDR_ENTRY
.load_file:
; read file we found from data sectors to the osloader entry point (0x8000)
; this involves walking the FAT cluster chain and checking for 0x0FFF (end of file)
; first_sector_of_cluster = ((cluster - 2) * fat_boot->sectors_per_cluster) + first_data_sector
; fat_offset = active_cluster + (active_cluster / 2);// multiply by 1.5
; ent_offset = fat_offset % section_size;
;

    mov ax, word [active_cluster]
    sub ax, 0x2
    movzx dx, byte [bsSecsPerClust]
    mul dx
    mov dx, word [first_data_sector]
    add ax, dx                           ; ((osldr_fat_cluster - 2) * sectors_per_cluster)

    mov bx, di
    call read_sector
    mov di, bx                          ; save updated next sector

    ;-- Look up next cluster for FAT12
    mov ax, word [active_cluster]
    mov bx, ax
    shr ax, 1                           ; div by 2
    add bx, ax
    mov word [active_cluster_FAT], bx   ; calculate the fat offset because of FAT12...

    mov si, FAT_TablePtr
    mov ax, word [bx + si]

    test word [active_cluster], 0x0001
    jz find_file.is_odd_cluster

    shr ax, 0x4
    jmp find_file.test_fat
.is_odd_cluster:
    and ax, 0x0FFF
.test_fat:
    cmp ax, 0x0FF8
    jge find_file.endp                  ; end of file marker found
    cmp ax, 0x0FF7
    jl find_file.valid_cluster
    inc ax                              ; move to the next cluster if the current one is marked as a bad cluster
.valid_cluster:
    mov word [active_cluster], ax       ; else update active cluster with the next cluster and load the next sector
    jmp find_file.load_file             ; do this until we find the end of file cluster chain marker


.stack_fixup_and_error:
    add sp, 0x04                        ; add 4 (2 words) to SP to fix it if we error after find_file.next_sector                                      ; since we use the stack to store the next directory entry disk sector to read
.file_error:
    mov al, "B"
    jmp early_error

.endp:
    add sp, 0x04                        ; fix stack before returning
    ret

; Read sector from disk
; In:	AX - LBA to read
; 		ES:BX - offset of transfer buffer destination
;
; Out:  AX - next sector
;       BX - BX + 0x200
;
;   it is an error if BX overflows, ensure that reads do not happen between segment boundries.
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
    mov word [disk_retry_count], 0      ; reset disk retry count

.lba_to_chs:
    mov word [CHS_LBA_Word], ax

.get_temp:
    xor dx, dx
    div word [bsSectPerTrack]
    mov word [CHS_Temp_Word], ax

.get_sect:
    xor dx, dx
    mov ax, word [CHS_LBA_Word]
    div word [bsSectPerTrack]           ; (LBA % (Sectors per Track))

    inc dx                  ; +1
    push dx                 ; remainder = Sector

.get_head:
    xor dx, dx
    mov ax, word [CHS_Temp_Word]
    div word [bsHeads]      ; Temp % Heads

    push dx                 ; remainder = head

; this isn't quite correct, Cylinder/track is the 8 MSB of CX and the 2 MSB of CL
; with the sector in the 6 LSB of CL. This will work as long as there are less than 255 Cylinders/Tracks
.get_cyl:
    xor dx, dx
    mov ax, word [CHS_Temp_Word]
    div word [bsHeads]      ; Temp / Heads

    push ax                 ; quotient = cylinder

.end_lba_conv:
    pop ax
    mov ch, al              ; Cylinder

    pop ax
    mov dh, al              ; Head

    pop ax
    mov cl, al              ; Sector

    mov dl, [bsDriveNumber]

.do_read:
    mov ax, 0x0201          ; to get around the annoying 127 sector limit on reads, we will read 1 sector at a time per call
                            ; disk read BIOS call index, AH = 0x02, AL=0x01
    int 0x13
    jnc read_sector.endp

.reset_disk:
    cmp word [disk_retry_count], 10
    ja read_sector.disk_fail

    xor ax, ax
    int 0x13                ; reset disk BIOS call
    inc word [disk_retry_count]
    jmp read_sector.do_read

.disk_fail:
    mov al, "C"
    jmp early_error

.endp:
    pop ax
    inc ax                  ; next LBA sector
    add bx, 0x200           ; add a sector to bx
    jnc read_sector.no_bx_overflow
    mov al, 'D'
    jmp early_error          ; throw an error if bx wraps

.no_bx_overflow:
    ret

; pass error as ascii character in al, errors a-zA-Z or 0-9
early_error:
    ; color 0x4F is white on red
    mov dx, 0xB800
    mov fs, dx

    ; the characters are two bytes in the order of 0xb8000: byte c, byte attribute
    ; since x86 is le, we store the attribute in the MSB of dx
    mov dh, 0x4F
    mov dl, al
    mov word [fs:0x0000], dx

.hcf:
    hlt
    jmp short early_error.hcf

filename: db 'OSLOADERBIN'

%assign bytes_remaining (510-($ - $$))
%warning MBR has bytes_remaining bytes remaining for code (MAX: 0x0200)

times (510 - ($ - $$)) db 0x00   ; Fill the rest of sector with 0x00

bootsig:
    dw 0xAA55                    ; Add boot signature at the end of bootloader