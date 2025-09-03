format PE console
entry start

include 'win32a.inc'

section '.data' data readable writeable
    usage_msg    db 'Использование: program число исходная_система целевая_система', 13, 10, 0
    error_msg    db 'Ошибка: некорректные аргументы!', 13, 10, 0
    result_msg   db 'Результат: ', 0
    newline      db 13, 10, 0
    
    output_buf   rb 256
    number       dd 0
    base_from    dd 0
    base_to      dd 0

section '.bss' readable writeable
    argc         dd ?
    argv         rd 64

section '.code' code readable executable

start:
    ; Получаем аргументы командной строки
    call parse_command_line_simple
    mov [argc], eax
    
    ; Проверяем количество аргументов
    cmp eax, 4
    jne .usage_error
    
    ; Аргумент 1: число
    mov esi, [argv + 4]    ; argv[1] - число
    
    ; Аргумент 2: исходная система
    mov esi, [argv + 8]    ; argv[2] - исходная система
    call str_to_int
    mov [base_from], eax
    
    ; Аргумент 3: целевая система
    mov esi, [argv + 12]   ; argv[3] - целевая система
    call str_to_int
    mov [base_to], eax
    
    ; Проверка систем счисления
    cmp dword [base_from], 2
    jl .error
    cmp dword [base_from], 36
    jg .error
    cmp dword [base_to], 2
    jl .error
    cmp dword [base_to], 36
    jg .error
    
    ; Парсим число
    mov esi, [argv + 4]    ; argv[1] - число
    mov ebx, [base_from]
    call parse_number
    jc .error
    
    mov [number], eax
    
    ; Преобразуем в целевую систему
    mov eax, [number]
    mov ebx, [base_to]
    mov edi, output_buf
    call int_to_str
    
    ; Вывод результата
    invoke printf, result_msg
    invoke printf, output_buf
    invoke printf, newline
    jmp .exit

.usage_error:
    invoke printf, usage_msg
    jmp .exit

.error:
    invoke printf, error_msg

.exit:
    invoke ExitProcess, 0

; ==============================================
; Простой парсинг командной строки
; Выход: EAX = argc
; ==============================================
parse_command_line_simple:
    push esi
    push edi
    push ebx
    
    ; Используем GetCommandLineA для получения командной строки
    call [GetCommandLineA]
    mov esi, eax
    mov edi, argv
    xor ecx, ecx           ; argc = 0
    
    ; Пропускаем пробелы в начале
.skip_leading_spaces:
    lodsb
    test al, al
    jz .done
    cmp al, ' '
    je .skip_leading_spaces
    cmp al, 9              ; tab
    je .skip_leading_spaces
    
    dec esi                ; вернуться к первому не-пробелу
    
    ; Первый аргумент - имя программы
    mov [edi], esi
    add edi, 4
    inc ecx
    
    ; Пропускаем имя программы
.skip_program_name:
    lodsb
    test al, al
    jz .done
    cmp al, ' '
    je .skip_after_program
    cmp al, '"'
    jne .skip_program_name
    ; Пропускаем quoted name
.skip_quoted_name:
    lodsb
    test al, al
    jz .done
    cmp al, '"'
    jne .skip_quoted_name
    
.skip_after_program:
    ; Парсим остальные аргументы
.parse_args:
    ; Пропускаем пробелы
    lodsb
    test al, al
    jz .done
    cmp al, ' '
    je .parse_args
    cmp al, 9              ; tab
    je .parse_args
    
    dec esi                ; вернуться к началу аргумента
    mov [edi], esi         ; сохраняем начало аргумента
    add edi, 4
    inc ecx
    
    ; Ищем конец аргумента
.find_arg_end:
    lodsb
    test al, al
    jz .done
    cmp al, ' '
    je .found_space
    cmp al, 9              ; tab
    je .found_space
    jmp .find_arg_end
    
.found_space:
    mov byte [esi-1], 0    ; заменяем пробел на нулевой байт
    jmp .parse_args
    
.done:
    mov eax, ecx           ; argc
    pop ebx
    pop edi
    pop esi
    ret

; ==============================================
; Преобразование строки в число
; Вход: ESI - указатель на строку, EBX - основание
; Выход: EAX - число, CF=1 если ошибка
; ==============================================
parse_number:
    xor eax, eax
    xor ecx, ecx
    
.next_char:
    mov cl, byte [esi]
    test cl, cl
    jz .done
    
    ; Преобразование символа в цифру
    cmp cl, '0'
    jb .error
    cmp cl, '9'
    jbe .digit_0_9
    
    cmp cl, 'A'
    jb .error
    cmp cl, 'Z'
    jbe .digit_A_Z
    
    cmp cl, 'a'
    jb .error
    cmp cl, 'z'
    jbe .digit_a_z
    
    jmp .error

.digit_0_9:
    sub cl, '0'
    jmp .check_digit

.digit_A_Z:
    sub cl, 'A' - 10
    jmp .check_digit

.digit_a_z:
    sub cl, 'a' - 10

.check_digit:
    cmp ecx, ebx
    jge .error
    
    ; Умножение текущего результата на основание и добавление цифры
    mul ebx
    jo .error
    add eax, ecx
    jc .error
    
    inc esi
    jmp .next_char

.done:
    clc
    ret

.error:
    stc
    ret

; ==============================================
; Преобразование числа в строку
; Вход: EAX - число, EBX - основание, EDI - буфер
; ==============================================
int_to_str:
    push edi
    push esi
    
    ; Обработка нуля
    test eax, eax
    jnz .not_zero
    mov byte [edi], '0'
    mov byte [edi+1], 0
    jmp .done

.not_zero:
    mov esi, edi
    add esi, 255           ; конец буфера
    mov byte [esi], 0      ; нулевой терминатор
    dec esi
    
.convert_loop:
    xor edx, edx
    div ebx
    
    ; Преобразование остатка в символ
    cmp edx, 9
    jbe .digit_0_9_
    add edx, 'A' - 10
    jmp .store_digit

.digit_0_9_:
    add edx, '0'

.store_digit:
    mov [esi], dl
    dec esi
    
    test eax, eax
    jnz .convert_loop

    ; Копируем результат в начало буфера
    inc esi
    mov ecx, esi
.copy_loop:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    test al, al
    jnz .copy_loop

.done:
    pop esi
    pop edi
    ret

; ==============================================
; Преобразование строки в число (для систем счисления)
; Вход: ESI - указатель на строку
; Выход: EAX - число
; ==============================================
str_to_int:
    xor eax, eax
    xor ecx, ecx
    mov ebx, 10
    
.convert:
    mov cl, byte [esi]
    test cl, cl
    jz .done
    
    cmp cl, '0'
    jb .error
    cmp cl, '9'
    ja .error
    
    sub cl, '0'
    imul eax, ebx
    add eax, ecx
    
    inc esi
    jmp .convert

.done:
    ret

.error:
    mov eax, 0
    ret

section '.idata' import data readable
    library kernel32, 'kernel32.dll', \
            msvcrt, 'msvcrt.dll'
    
    import kernel32, \
           ExitProcess, 'ExitProcess', \
           GetCommandLineA, 'GetCommandLineA'
    
    import msvcrt, \
           printf, 'printf'
