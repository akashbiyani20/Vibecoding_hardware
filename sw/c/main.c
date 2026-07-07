// ============================================================================
// main.c — the first C program on our CPU
// ----------------------------------------------------------------------------
// Exercises everything Stage E added: multiply via libgcc (__mulsi3 — the
// core has no multiplier, gcc links a software one), string literals
// (.rodata in RAM), globals (.data preload + .bss zeroing), byte loads
// (string walking = LBU), the timer, GPIO, and UART both directions.
// ============================================================================
#include "bsp.h"

int  answer   = 42;          // .data  — preloaded initialized global
int  counter;                // .bss   — crt0 must zero this

int square(int x) { return x * x; }   // '*' -> __mulsi3 (software multiply)

int main(void) {
    uart_puts("hello from C!\n");

    uart_puts("answer=");
    uart_put_udec((uint32_t)answer);          // .data preload works
    uart_putc('\n');

    uart_puts("counter=");
    uart_put_udec((uint32_t)counter);         // .bss zeroing works
    uart_putc('\n');

    uart_puts("7*7=");
    uart_put_udec((uint32_t)square(7));       // software multiply works
    uart_putc('\n');

    // blink: 3 timed pulses on LED0 (timer-based, no calibrated loops)
    for (int i = 0; i < 3; i++) {
        GPIO_OUT = 1;  delay_cycles(200);
        GPIO_OUT = 0;  delay_cycles(200);
    }
    uart_puts("blink done\n");

    // echo: whatever arrives on RX goes back out on TX, shifted +1
    // (proves receive path; 'A' in -> 'B' out)
    for (int i = 0; i < 2; i++) {
        char c = uart_getc();
        uart_putc((char)(c + 1));
    }
    uart_puts("\nbye\n");
    return 0;
}
