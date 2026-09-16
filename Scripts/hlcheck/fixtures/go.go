// Package fixture exercises every construct the go highlight query tags.
// It is a dense, representative file, not real code.
package fixture

import (
	"fmt"
	"regexp"
	str "strings"
	_ "embed"
)

/* Block comment before a const block. */
const (
	// MaxRetries is a doc comment on a const spec.
	MaxRetries      = 3
	Pi              = 3.14159
	Big             = 1_000_000
	Hex             = 0xDEADbeef
	Oct             = 0o755
	Bin             = 0b1010
	Exp             = 1e-9
	Im              = 2.5i
	Greeting string = "hi\tthere\né\x41"
	Raw             = `raw \n string`
	Rune            = 'x'
	Esc             = '\''
)

// Kind is an enumerated type built on iota.
type Kind int

const (
	KindA Kind = iota
	KindB
)

var (
	// counter documents a var spec inside a group.
	counter  uint64
	names    []string
	lookup   map[string]any
	ch       chan<- int
	nilValue error = nil
)

type Alias = Kind

// Shape is an interface with a method set.
type Shape interface {
	Area() float64
	fmt.Stringer
}

// Rect is a struct with tagged fields and an embedded type.
type Rect struct {
	Width, Height float64
	label         string `json:"label,omitempty"`
	*Kind
}

// NewRect is a constructor-shaped function.
func NewRect(w, h float64, opts ...func(*Rect)) *Rect {
	r := &Rect{Width: w, Height: h, label: "rect"}
	for _, opt := range opts {
		opt(r)
	}
	return r
}

// Area implements Shape.
func (r *Rect) Area() float64 {
	return r.Width * r.Height
}

func (r Rect) String() string { return fmt.Sprintf("%s %.2f", r.label, r.Area()) }

// Pair is a generic type.
type Pair[K comparable, V any] struct {
	Key K
	Val V
}

// Map is a generic free function.
func Map[T, U any](xs []T, f func(T) U) []U {
	out := make([]U, 0, len(xs))
	for i := range xs {
		out = append(out, f(xs[i]))
	}
	return out
}

// classify is a two-line doc comment: every line of the run should
// read as documentation, not as a plain comment.
func classify(n int, tags ...string) (result string, err error) {
	defer func() {
		if rec := recover(); rec != nil {
			err = fmt.Errorf("recovered: %v", rec)
		}
	}()
	switch {
	case n < 0:
		result = "negative"
	case n == 0:
		result = "zero"
		fallthrough
	default:
		result = "positive"
	}
	switch k := Kind(n); k {
	case KindA, KindB:
		_ = k
	}
	var s Shape = NewRect(1, 2)
	if rect, ok := s.(*Rect); ok && rect.Width > 0 || !ok {
		names = append(names, rect.label)
	} else if n%2 == 1 {
		counter++
	} else {
		counter -= 1
	}
	// A plain in-body comment, not documentation.
	x := 1 << 3 | 2 &^ 1 ^ 7 >> 1 /* trailing block comment */
	x <<= 2
	x &= 0xFF
	y := ^x + -x
	_ = y
	lookup = map[string]any{"a": 1, "b": true, "c": nil}
	delete(lookup, "a")
	for i := 0; i < len(tags); i++ {
		if i > 5 {
			break
		}
		continue
	}
outer:
	for {
		select {
		case v := <-make(chan int):
			_ = v
			break outer
		default:
			goto done
		}
	}
done:
	go func(id int) { println(id) }(cap(names))
	str.ToUpper(result)
	re := regexp.MustCompile(`^a+$`)
	_ = re.MatchString("aaa")
	panic("unreachable")
}

func main() {
	p := Pair[string, int]{Key: "k", Val: 1}
	fmt.Println(p.Key, p.Val, Map([]int{1, 2}, func(i int) string { return fmt.Sprint(i) }))
	r, err := classify(MaxRetries, "a", "b")
	if err != nil {
		panic(err)
	}
	fmt.Println(r, min(1, 2), max(3, 4), new(Rect), clear)
}
