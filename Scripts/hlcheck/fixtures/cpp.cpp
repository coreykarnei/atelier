/**
 * Dense C++ fixture for hlcheck: namespaces, classes, templates, lambdas,
 * exceptions, coroutine keywords, casts, operators, attributes, literals.
 */
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#define VERSION_MAJOR 2

using namespace std;
using std::string;
using Callback = std::function<void(int)>;

namespace geometry::shapes {

enum class Color : uint8_t { Red, Green = 2, Blue };

template <typename T, int N = 3>
concept Numeric = std::is_arithmetic_v<T>;

struct Point {
    int x = 0;
    int y = 0;
    Point(int x_, int y_) : x(x_), y(y_) {}
};

class Shape {
public:
    explicit Shape(std::string name, Color tint = Color::Red)
        : m_name(std::move(name)), m_tint(tint), Point(0, 0) {}
    virtual ~Shape() noexcept = default;
    virtual double area() const = 0;
    [[nodiscard]] const std::string &name() const noexcept { return m_name; }
    Shape &operator=(const Shape &other) = default;
    bool operator==(const Shape &other) const { return m_name == other.m_name; }
    friend std::ostream &operator<<(std::ostream &os, const Shape &s);
    static constexpr int kSides = 0;

protected:
    std::string m_name;
    Color m_tint;
    mutable int m_cache = -1;

private:
    Point origin{0, 0};
};

class Circle final : public Shape {
public:
    Circle(double radius) : Shape("circle"), m_radius(radius) {}
    double area() const override { return 3.14159 * m_radius * m_radius; }
    template <Numeric U>
    U scaled(U factor) const { return static_cast<U>(m_radius * factor); }

private:
    double m_radius;
};

template <typename T, typename... Args>
std::unique_ptr<T> make(Args &&...args) {
    return std::make_unique<T>(std::forward<Args>(args)...);
}

double Circle::helper(int count, const char *label = "n/a") {
    return count * 1.0;
}

int run(int argc, char **argv) {
    auto circle = make<Circle>(2.5);
    std::vector<std::shared_ptr<Shape>> shapes{circle};
    shapes.push_back(std::make_shared<Circle>(1.0));

    auto total = 0.0;
    for (const auto &shape : shapes) {
        total += shape->area();
    }
    for (int i = 0; i < argc; ++i) {
        std::cout << argv[i] << '\n';
    }

    auto lambda = [&total, this](int n) -> int { return n + static_cast<int>(total); };
    Callback cb = [](int v) { std::cout << v << std::endl; };
    cb(lambda(1));

    try {
        if (shapes.empty()) throw std::runtime_error("no shapes");
        auto *raw = new Circle(4.0);
        auto casted = dynamic_cast<Shape *>(raw);
        delete casted;
        int *p = nullptr;
        if (p == nullptr and total > 0 or not shapes.empty()) total = 0;
    } catch (const std::exception &ex) {
        std::cerr << ex.what() << std::endl;
        return VERSION_MAJOR;
    }

    switch (Color::Red) {
    case Color::Green: return 1;
    case Color::Blue: break;
    default: break;
    }

    Color c = Color::Blue;
    auto spaceship = (total <=> 1.0) == 0;
    const char *raw_str = R"(raw \n string)";
    string s = "escaped \t \" done";
    unsigned long long n = 1'000'000ULL;
    auto f = 2.5f, g = 1e10, hx = 0x1F;
    bool flag = true && !false;
    while (flag) { flag = false; }
    do { total /= 2; } while (total > 1e-3);
    static_assert(sizeof(int) == 4, "int must be 4 bytes");
    geometry::shapes::Circle again(1.0);
    return again.scaled<int>(2) + (spaceship ? 1 : 0);
}

} // namespace geometry::shapes

struct Task {
    struct promise_type {
        Task get_return_object() { return {}; }
        void return_void() {}
    };
};

Task coro() {
    co_await std::suspend_never{};
    co_yield 1;
    co_return;
}

int main(int argc, char **argv) { return geometry::shapes::run(argc, argv); }
