<?php

declare(strict_types=1);

namespace App\Inventory;

use App\Contracts\Describable;
use App\Support\{Clock, Money as Cash};
use function App\Support\format_price;
use const App\Support\DEFAULT_CURRENCY;

// A line comment.
# A hash comment.

/**
 * A doc comment describing the enum.
 *
 * @see Describable
 */
#[Attribute(Attribute::TARGET_CLASS)]
enum Status: string implements Describable
{
    case Active = 'active';
    case Retired = 'retired';

    public const DEFAULT_STATUS = self::Active;

    public function describe(): string
    {
        return match ($this) {
            self::Active => 'in stock',
            self::Retired => 'gone',
        };
    }
}

interface Priced
{
    public function price(): float;
}

trait Loggable
{
    protected static int $logCount = 0;

    public function log(string $message, mixed ...$context): void
    {
        static::$logCount++;
        self::$logCount += 1;
        error_log(sprintf("[%s] %s", static::class, $message));
    }
}

trait Auditable
{
    public function log(string $message, mixed ...$context): void
    {
        print $message;
    }
}

/** A widget with a price. */
abstract class Widget implements Priced, \JsonSerializable
{
    use Loggable;

    public const int MAX_ITEMS = 100;
    private const TAX_RATE = 0.0825;

    public readonly string $sku;
    protected ?Clock $clock = null;
    private array $tags = [];

    public function __construct(
        string $sku,
        private float $basePrice = 9.99,
        public Status $status = Status::Active,
        Clock|null $clock = null,
    ) {
        $this->sku = strtoupper($sku);
        $this->clock = $clock ?? new Clock();
        parent::__construct();
    }

    abstract public function price(): float;

    final public static function create(string $sku, float ...$prices): static
    {
        return new static($sku, ...$prices);
    }

    public function jsonSerialize(): array
    {
        return ['sku' => $this->sku, 'price' => $this->price(), 'tags' => $this->tags];
    }

    protected function taxed(float $amount): float
    {
        return $amount * (1 + self::TAX_RATE);
    }

    public function __toString(): string
    {
        return "Widget {$this->sku} costs \${$this->basePrice} at {$this->clock?->now()}\n";
    }
}

final class Gadget extends Widget
{
    use Loggable, Auditable {
        Loggable::log insteadof Auditable;
        Auditable::log as protected auditLog;
    }

    public function price(): float
    {
        return $this->taxed($this->basePrice);
    }
}

/**
 * Sum the prices of every widget.
 *
 * @param Widget[] $widgets
 */
function total_price(array $widgets, int $round = 2, bool $verbose = false, ?string &$label = null): float
{
    global $config;
    static $calls = 0;
    $calls++;

    $total = 0.0;
    foreach ($widgets as $index => $widget) {
        if (!$widget instanceof Widget) {
            continue;
        } elseif ($widget->status === Status::Retired) {
            continue;
        } else {
            $total += $widget->price();
        }
    }

    for ($i = 0; $i < count($widgets); $i++) {
        $label .= (string) $i;
    }

    $n = 3;
    while ($n-- > 0) {
        $total = $total ** 1;
    }

    do {
        $n++;
    } while ($n < 3);

    switch ($round) {
        case 0:
            $total = (int) $total;
            break;
        case 1:
        default:
            $total = round($total, $round);
    }

    try {
        if ($total < 0 && !$verbose || $total === null) {
            throw new \InvalidArgumentException("negative total: $total");
        }
    } catch (\InvalidArgumentException | \TypeError $e) {
        echo $e->getMessage(), PHP_EOL;
        print "failed\n";
        exit(1);
    } finally {
        unset($n);
    }

    if (isset($config['debug']) && !empty($config)) {
        goto done;
    }

    done:
    return $total;
}

function each_price(Widget ...$widgets): \Generator
{
    foreach ($widgets as $widget) {
        yield $widget->sku => $widget->price();
    }
    yield from array_map(fn(Widget $w): float => $w->price(), $widgets);
    return count($widgets);
}

$prices = array_map(fn(Widget $w): float => $w->price(), [new Gadget('abc'), Gadget::create('xyz', 1.5)]);
$closure = function (int $x) use ($prices, &$total): int {
    return $x + count($prices);
};
[$first, $second] = $prices;
list('a' => $a, 'b' => $b) = ['a' => 1, 'b' => 2];

$hex = 0xFF;
$oct = 0o17;
$bin = 0b1010;
$big = 1_000_000;
$flt = 1.5e-3;
$str = 'single \'quoted\' string';
$esc = "tab\t newline\n unicode \u{1F600} dollar \$notvar";
$interp = "Hello {$first} and $second and {$prices[0]} and ${first}";
$heredoc = <<<EOT
    Total: {$total}
    Escaped: \n
    EOT;
$nowdoc = <<<'EOT'
    Raw $total
    EOT;
$shell = `ls -la`;
$cast = (float) "1.5" + (int) '2' . (bool) 0;
$check = $first <=> $second ?: PHP_INT_MAX;
$null = null;
$flag = true and false or !TRUE xor FALSE;
$ref = &$prices;
$clone = clone $closure;
$_GET['id'] ?? $_SERVER['REQUEST_URI'];
$ternary = $flag ? __CLASS__ : __FILE__;
$obj = new class extends Gadget {};
$fqcn = Gadget::class;
$method = Status::from('active')->describe();
$nullsafe = $widget?->clock?->timezone;
$result = \App\Support\format_price(DEFAULT_CURRENCY, $total);
$config['debug'] ??= true;
$rounded = round(num: $total, precision: 2);
$shifted = 1 << 2 | 4 & 3 ^ ~1 >> 1 % 2;
@file_get_contents('missing');

?>
<div><?= htmlspecialchars($str) ?></div>
