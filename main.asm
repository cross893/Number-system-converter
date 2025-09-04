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
    
    ; Парсим число (специальная обработка для разных систем)
    mov esi, [argv + 4]    ; argv[1] - число
    mov ebx, [base_from]
    call parse_number_proper
    jc .error
    
    mov [number], eax
    
    ; Преобразуем в целевую систему
    mov eax, [number]
    mov ebx, [base_to]
    mov edi, output_buf
    call int_to_str_proper
    
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
; Правильное преобразование строки в число
; Для десятичной системы: знак +/- в начале
; Для других систем: дополнение до двух
; Вход: ESI - указатель на строку, EBX - основание
; Выход: EAX - число, CF=1 если ошибка
; ==============================================
parse_number_proper:
    ; Для десятичной системы обрабатываем знак
    cmp ebx, 10
    jne .binary_system
    
    ; Десятичная система - обрабатываем знак
    xor eax, eax
    xor ecx, ecx
    mov edx, 1             ; флаг знака (1 = положительное)
    
    ; Проверяем знак
    mov cl, byte [esi]
    cmp cl, '-'
    jne .check_plus_dec
    mov edx, -1            ; отрицательное число
    inc esi
    jmp .convert_dec
    
.check_plus_dec:
    cmp cl, '+'
    jne .convert_dec
    inc esi
    
.convert_dec:
    ; Преобразуем десятичное число
.next_char_dec:
    mov cl, byte [esi]
    test cl, cl
    jz .done_dec
    
    cmp cl, '0'
    jb .error
    cmp cl, '9'
    ja .error
    
    sub cl, '0'
    imul eax, 10
    jo .error
    add eax, ecx
    jc .error
    
    inc esi
    jmp .next_char_dec
    
.done_dec:
    imul eax, edx          ; применяем знак
    clc
    ret

.binary_system:
    ; Для не-десятичных систем используем дополнение до двух
    xor eax, eax
    xor ecx, ecx
    
    ; Определяем длину числа
    push esi
    mov edi, esi
    xor ecx, ecx
.get_length:
    mov al, [edi]
    test al, al
    jz .length_done
    inc edi
    inc ecx
    jmp .get_length
    
.length_done:
    pop esi
    
    ; Для двоичной системы: если длина 32 символа, это может быть отрицательное
    cmp ebx, 2
    jne .convert_other
    
    cmp ecx, 32
    jne .convert_other
    
    ; Проверяем первый бит (для отрицательного числа)
    mov cl, byte [esi]
    cmp cl, '1'
    jne .convert_other
    
    ; Это отрицательное число в двоичном дополнении до двух
    call parse_binary_twos_complement
    jmp .done_other

.convert_other:
    ; Обычное преобразование для других систем
    xor eax, eax
    
.next_char_other:
    mov cl, byte [esi]
    test cl, cl
    jz .done_other
    
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
    jmp .next_char_other

.done_other:
    clc
    ret

.error:
    stc
    ret

; Преобразование двоичного числа в дополнении до двух
parse_binary_twos_complement:
    xor eax, eax
    xor ecx, ecx
    mov edx, 32            ; 32 бита
    
.convert_binary:
    mov cl, byte [esi]
    cmp cl, '0'
    je .bit_zero
    cmp cl, '1'
    jne .error_binary
    
    ; Устанавливаем бит
    push ecx
    mov ecx, edx
    dec ecx
    bts eax, ecx           ; установить бит
    pop ecx
    
.bit_zero:
    inc esi
    dec edx
    jnz .convert_binary
    
    ; Это число в дополнении до двух, интерпретируем как signed
    clc
    ret

.error_binary:
    stc
    ret

; ==============================================
; Правильное преобразование числа в строку
; Для десятичной системы: знак минус
; Для других систем: дополнение до двух
; Вход: EAX - число, EBX - основание, EDI - буфер
; ==============================================
int_to_str_proper:
    ; Для десятичной системы выводим со знаком
    cmp ebx, 10
    je .decimal_output
    
    ; Для других систем используем беззнаковое представление
    ; Но для двоичной системы можем выводить в дополнении до двух
    cmp ebx, 2
    jne .unsigned_output
    
    ; Для двоичной системы проверяем, отрицательное ли число
    test eax, eax
    jns .unsigned_output
    
    ; Отрицательное число - выводим в дополнении до двух
    call format_binary_twos_complement
    ret

.decimal_output:
    ; Десятичный вывод со знаком
    push edi
    push esi
    
    ; Проверяем отрицательное число
    test eax, eax
    jns .positive_decimal
    mov byte [edi], '-'    ; добавляем знак минус
    inc edi
    neg eax                ; делаем число положительным
    
.positive_decimal:
    ; Обычное преобразование
    mov esi, edi
    add esi, 254
    mov byte [esi], 0
    dec esi
    
.convert_decimal:
    xor edx, edx
    mov ecx, 10
    div ecx
    
    add dl, '0'
    mov [esi], dl
    dec esi
    
    test eax, eax
    jnz .convert_decimal
    
    ; Копируем результат
    inc esi
    mov ecx, edi
    cmp byte [ecx], '-'    ; проверяем минус
    jne .copy_decimal
    inc ecx
    
.copy_decimal:
    mov al, [esi]
    mov [ecx], al
    inc esi
    inc ecx
    test al, al
    jnz .copy_decimal
    
    pop esi
    pop edi
    ret

.unsigned_output:
    ; Беззнаковый вывод для не-десятичных систем
    push edi
    push esi
    
    ; Обработка нуля
    test eax, eax
    jnz .not_zero_unsigned
    mov byte [edi], '0'
    mov byte [edi+1], 0
    jmp .done_unsigned

.not_zero_unsigned:
    mov esi, edi
    add esi, 255
    mov byte [esi], 0
    dec esi
    
.convert_unsigned:
    xor edx, edx
    div ebx
    
    ; Преобразование остатка в символ
    cmp edx, 9
    jbe .digit_0_9_unsigned
    add edx, 'A' - 10
    jmp .store_digit_unsigned

.digit_0_9_unsigned:
    add edx, '0'

.store_digit_unsigned:
    mov [esi], dl
    dec esi
    
    test eax, eax
    jnz .convert_unsigned

    ; Копируем результат
    inc esi
.copy_unsigned:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    test al, al
    jnz .copy_unsigned

.done_unsigned:
    pop esi
    pop edi
    ret

; Форматирование двоичного числа в дополнении до двух
format_binary_twos_complement:
    push edi
    push esi
    push ebx
    
    mov ebx, eax           ; сохраняем число
    mov ecx, 32            ; 32 бита
    mov esi, edi
    
.convert_bit:
    mov eax, ebx
    shr eax, 31            ; получаем старший бит
    and eax, 1
    add al, '0'
    mov [edi], al
    inc edi
    
    shl ebx, 1             ; сдвигаем к следующему биту
    dec ecx
    jnz .convert_bit
    
    mov byte [edi], 0      ; нулевой терминатор
    
    pop ebx
    pop esi
    pop edi
    ret

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
