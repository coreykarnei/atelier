/**
 * Doc comment for the fixture. {@link Inventory} exercises every construct the
 * highlight query is expected to tag.
 */
package dev.sterlingcore.atelier.fixtures;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import static java.lang.Math.max;
import java.util.stream.*;

/// Markdown doc comment (JEP 467).
@FunctionalInterface
interface Shape extends Comparable<Shape> {
    double area();

    default String describe() {
        return "shape with area " + area();
    }
}

enum Color { RED, GREEN, BLUE }

record Point(int x, int y) {
    Point {
        if (x < 0) throw new IllegalArgumentException("negative");
    }
}

@interface Tag { String value() default "none"; }

sealed abstract class Base permits Inventory {}

// Line comment before the class.
public final class Inventory extends Base implements Shape, AutoCloseable {
    public static final int MAX_ITEMS = 0x7F;
    private static final double TAX_RATE = 1.5e-1;
    private final Map<String, Integer> counts;
    protected List<? extends Number> readings;
    volatile transient long ticks = 0L;
    char delimiter = '\n';
    float ratio = 3.14f;
    int mask = 0b1010_1010, oct = 017;

    @Deprecated(since = "1.2")
    public Inventory(Map<String, Integer> counts, String... labels) {
        super();
        this.counts = counts;
        this.readings = List.of(1, 2.0, 3L);
    }

    /* Block comment on a method. */
    @Override
    public double area() {
        return counts.size() * TAX_RATE;
    }

    public static <T extends Comparable<T>> T pick(T first, T second) {
        return first.compareTo(second) >= 0 ? first : second;
    }

    public synchronized int count(String label, int fallback) throws Exception {
        Integer stored = counts.get(label);
        if (stored == null) {
            return fallback;
        } else if (stored > MAX_ITEMS) {
            throw new IllegalStateException("too many: \t" + stored);
        }
        int total = 0;
        outer:
        for (int i = 0; i < stored; i++) {
            for (Map.Entry<String, Integer> e : counts.entrySet()) {
                if (e.getValue() % 2 == 0) continue outer;
                total += e.getValue() << 1;
            }
        }
        while (total > 100) { total -= 10; }
        do { total++; } while (total < 0);
        switch (label) {
            case "a", "b" -> total *= 2;
            default -> total = max(total, fallback);
        }
        Object o = stored;
        String kind = switch (o) {
            case Integer i when i > 5 -> "big";
            case Integer i -> "small";
            default -> {
                yield "other";
            }
        };
        assert kind != null : "kind";
        synchronized (this) {
            ticks = ticks | 1L & ~0L ^ 2L;
        }
        try {
            Function<Integer, Integer> twice = n -> n * 2;
            Function<Integer, Integer> inc = (a) -> a + 1;
            var mapped = Stream.of(1, 2, 3).map(String::valueOf).collect(Collectors.toList());
            int[] arr = new int[]{1, 2};
            boolean flag = !(arr.length == 2) || o instanceof Integer && true;
            System.out.println(mapped + kind + flag + twice.apply(inc.apply(3)));
        } catch (RuntimeException | Error ex) {
            ex.printStackTrace();
        } finally {
            total--;
        }
        String block = """
            text block A
            second line
            """;
        return total >>> 1;
    }

    @Override
    public void close() {
        Color c = Color.RED;
        Runnable r = this::describe;
        Inventory.MAX_ITEMS += 0;
    }
}
