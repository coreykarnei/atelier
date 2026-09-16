// hlcheck fixture: dense C# exercising the highlight query.
#nullable enable
#region Usings
using System;
using System.Collections.Generic;
using System.Linq;
using static System.Math;
using Alias = System.Text.StringBuilder;
#endregion

namespace Atelier.Fixtures.Highlight
{
    /// <summary>
    /// Doc comment on an interface.
    /// </summary>
    public interface IShape<T> where T : struct
    {
        double Area { get; }
        event EventHandler? Changed;
    }

    /** Block doc comment. */
    [Serializable]
    [Obsolete("Use Circle", error: false)]
    public sealed class Circle : IShape<int>, IDisposable
    {
        private const double Tau = 6.283185307179586;
        public const int MaxItems = 0x1F + 0b1010 + 1_000;
        private static readonly string[] names = { "a", "b\n", "c" };
        private readonly List<double> radii = new();
        protected internal float scale = 1.5f;
        public string? Label { get; set; } = "circle";
        public int Count => radii.Count;
        public event EventHandler? Changed;

        public Circle(double radius, string label = "unit", params int[] extras)
        {
            radii.Add(radius);
            Label = label;
            this.scale = extras.Length > 0 ? extras[0] : 1.0f;
        }

        ~Circle() { }

        public double Area => Tau / 2 * radii[0] * radii[0];

        public static Circle operator +(Circle a, Circle b) => new Circle(a.radii[0] + b.radii[0]);

        public static implicit operator double(Circle c) => c.Area;

        [return: NotNull]
        public async Task<string> DescribeAsync<TKey>(TKey key, out int written, ref bool flag, in long tick)
            where TKey : notnull
        {
            written = 0;
            var sb = new Alias();
            string interpolated = $"Circle {Label} r={radii[0]:F2} {{literal}} \t{key}";
            string verbatim = @"C:\path\to\file";
            string raw = """
                raw text "quoted"
                """;
            char ch = '\n';
            char plain = 'x';
            foreach (var r in radii)
            {
                if (r > 1.0 && r <= 2.0 || !flag)
                {
                    sb.Append(r);
                }
                else if (r is double d and > 3.0)
                {
                    continue;
                }
                else
                {
                    break;
                }
            }
            for (int i = 0; i < 3; i++) { written += i; }
            while (written > 10) { written--; }
            do { written++; } while (written < 5);
            switch (written)
            {
                case 0:
                    goto done;
                case 1 when flag:
                    break;
                default:
                    break;
            }
            var kind = written switch
            {
                < 0 => "negative",
                0 => "zero",
                _ => "positive",
            };
            try
            {
                await Task.Delay(10);
                throw new InvalidOperationException(nameof(written));
            }
            catch (InvalidOperationException ex) when (ex.Message != null)
            {
                Console.WriteLine(ex.Message);
            }
            finally
            {
                flag = true;
            }
            done:
            var query = from n in names where n.Length > 0 orderby n descending select n.ToUpper();
            Func<int, int> square = x => x * x;
            Action<int> print = static (int v) => Console.WriteLine(v);
            int? maybe = null;
            int sure = maybe ?? default;
            maybe ??= 7;
            var t = (Left: 1, Right: 2.5);
            object o = (object)sure;
            var casted = o as string;
            bool check = o is not null;
            var arr = new[] { 1, 2, 3 };
            var slice = arr[1..^1];
            var size = sizeof(int);
            var type = typeof(Circle);
            var clone = this with { };
            lock (radii) { }
            unsafe { int* p = &sure; }
            yield return kind;
            return interpolated + verbatim + raw + ch + plain + Sqrt(4.0) + Max(1, 2);
        }

        private static int Helper(int a, int b = 2) => a % b;

        private int count;
        public int Total { get => count; set => count = value; }

        public void Dispose()
        {
#if DEBUG
            Console.WriteLine("debug");
#endif
#pragma warning disable CS1591
            var items = Enumerable.Empty<int>().Select<int, int>(v => v).ToList();
            int Local(int q) => q << 1;
            Changed?.Invoke(this, EventArgs.Empty);
            Local(3);
            base.ToString();
        }
    }

    public struct Point { public int X; public int Y; }
    public record Person(string Name, int Age);
    public record struct Pair(int A, int B);
    public enum Color { Red = 1, Green, Blue }
    public delegate void Handler(object sender);
}
