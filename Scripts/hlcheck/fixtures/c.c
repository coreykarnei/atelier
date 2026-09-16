/**
 * Dense C fixture for hlcheck: preprocessor, structs, function pointers,
 * parameters, control flow, operators, literals, attributes, labels.
 */
#include <stdio.h>
#include <stdlib.h>
#include "local_header.h"

#define BUFFER_SIZE 256
#define SQUARE(x) ((x) * (x))
#define STRINGIFY(s) #s
#undef UNUSED_MACRO

#ifdef DEBUG_BUILD
#  define LOG(fmt, ...) fprintf(stderr, fmt, __VA_ARGS__)
#elif defined(RELEASE_BUILD)
#  define LOG(fmt, ...) ((void)0)
#else
#  define LOG(fmt, ...) do { } while (0)
#endif

#pragma once

// Line comment.
/* Block comment. */

typedef unsigned long long ull_t;
typedef struct Point Point;

enum Color { RED = 0, GREEN, BLUE = 0x2 };

struct Point {
    int x, y;
    const char *label;
    void (*on_move)(struct Point *self, int dx, int dy);
    struct { float r, g, b; } tint;
};

union Value {
    int i;
    float f;
    unsigned char bytes[4];
};

static const int MAX_ITEMS = 42;
extern volatile int g_flag;
register int fast;
__attribute__((unused)) static int hidden = 1;
[[nodiscard]] static int checked(void);

static inline int add(int a, int b) { return a + b; }

static void point_move(struct Point *self, int dx, int dy) {
    self->x += dx;
    self->y -= dy;
    LOG("moved %s\n", self->label);
}

int apply(int (*fn)(int, int), int values[], size_t n, ...) {
    int acc = 0;
    for (size_t i = 0; i < n; ++i) {
        acc = fn(acc, values[i]);
    }
    return acc;
}

int main(int argc, char **argv) {
    struct Point p = { .x = 1, .y = 2, .label = "origin", .on_move = point_move };
    Point *pp = &p;
    ull_t big = 18446744073709551615ULL;
    double d = 3.14e-2, e = 1.5f, h = 0x1p-3;
    int hex = 0xFF, oct = 0755, bin = 0b1010, dec = 10L;
    char c = '\n', q = 'q';
    const char *msg = "tab\tnewline\n quote \" percent %d";
    const char *joined = "part one, " "part two";
    _Bool ok = true, no = false;
    void *nothing = NULL;

    if (argc > 1 && argv[1] != NULL) {
        printf("%s %d\n", argv[1], SQUARE(argc));
    } else if (argc == 1) {
        puts(__FILE__);
    } else {
        goto cleanup;
    }

    switch (p.x) {
    case RED:
        p.on_move(pp, 1, -1);
        break;
    case 1:
        pp->on_move(pp, 0, 0);
        break;
    default:
        break;
    }

    while (hex-- > 0) {
        if (hex % 2 == 0) continue;
        hex >>= 1;
    }

    do {
        oct = ok ? oct << 1 : oct | bin;
    } while (oct < 100 && !no);

    int sum = apply(add, (int[]){1, 2, 3}, 3);
    size_t sz = sizeof(struct Point) + sizeof p + __builtin_expect(sum, 0);
    int *heap = malloc(sz * sizeof(int));
    heap[0] = big & 0xFF ^ ~dec;
    free(heap);
    (void)c; (void)q; (void)msg; (void)joined; (void)d; (void)e; (void)h; (void)nothing; (void)fast;

cleanup:
    fprintf(stdout, "done %lu\n", (unsigned long)sz);
    return EXIT_SUCCESS;
}
