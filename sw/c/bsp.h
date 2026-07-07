// ============================================================================
// bsp.h — Board Support Package: how C talks to OUR hardware
// ----------------------------------------------------------------------------
// Each peripheral register is just an address (docs/memory_map.md).
// `volatile` is essential: it forbids the compiler from caching or
// reordering these accesses — every read/write in the C code becomes a
// real bus transaction, which is the entire point.
// ============================================================================
#ifndef BSP_H
#define BSP_H

#include <stdint.h>

#define GPIO_OUT   (*(volatile uint32_t *)0x10000000u)
#define UART_TX    (*(volatile uint32_t *)0x10001000u)
#define UART_STAT  (*(volatile uint32_t *)0x10001004u)
#define UART_RX    (*(volatile uint32_t *)0x10001008u)
#define TIMER_LO   (*(volatile uint32_t *)0x10002000u)
#define TIMER_HI   (*(volatile uint32_t *)0x10002004u)

#define UART_TX_BUSY  (1u << 0)
#define UART_RX_VALID (1u << 1)

// ---- serial output ----------------------------------------------------------
static inline void uart_putc(char c) {
    while (UART_STAT & UART_TX_BUSY) {}   // wait for the transmitter
    UART_TX = (uint32_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

// ---- serial input -------------------------------------------------------------
static inline int uart_rx_ready(void) {
    return (UART_STAT & UART_RX_VALID) != 0;
}

static inline char uart_getc(void) {          // blocking
    while (!uart_rx_ready()) {}
    return (char)UART_RX;                     // reading pops the byte
}

// ---- printing numbers (no printf on 4 KB of RAM!) --------------------------------
static inline void uart_put_udec(uint32_t v) {
    char buf[10];
    int  i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { buf[i++] = (char)('0' + v % 10); v /= 10; }
    while (i) uart_putc(buf[--i]);
}

static inline void uart_put_hex(uint32_t v) {
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc("0123456789abcdef"[(v >> i) & 0xF]);
}

// ---- time -----------------------------------------------------------------------
static inline uint32_t time_lo(void) { return TIMER_LO; }

static inline void delay_cycles(uint32_t n) {  // accurate, no calibration
    uint32_t start = TIMER_LO;
    while (TIMER_LO - start < n) {}            // wraparound-safe subtraction
}

#endif // BSP_H
