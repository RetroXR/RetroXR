#pragma once

// The engine's arithmetic, as the GDScript reference meets it.
//
// The solvers here are ports of GbPrinterStrip and GbThermalRibbon and must
// give their numbers to the bit. GDScript does vector arithmetic in real_t
// (float) through the Variant operators, and everything it reads out of a
// vector (`v.x`, `v.dot(w)`, `v.length()`) becomes a 64-bit float: so `f.x *
// c.y` is a double multiply and `v * s` a float one. The ports write each of
// those out (`(double)f.x * c.y`, `v * (real_t)s`) rather than leave them to
// C++'s promotion rules, which would differ.
//
// The geometry below is copied from Godot 4.7.2 (core/math/geometry_2d.h,
// geometry_3d.cpp/.h), which GDScript's Geometry2D/Geometry3D call; godot-cpp
// has no copy of it. godot-cpp's Vector2/3, Rect2 and AABB methods used here
// were compared with the engine's line for line (2026-11-10): the same, but for
// normalize() on a non-finite vector, which paper never is.

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace Xenu::Paper
{
using godot::AABB;
using godot::Rect2;
using godot::real_t;
using godot::Vector2;
using godot::Vector3;

// GDScript's minf/maxf are Godot's MIN/MAX: `a < b ? a : b`. std::min/max pick
// the other operand on a tie, which is a different signed zero.
inline double gmin(double a, double b) { return a < b ? a : b; }
inline double gmax(double a, double b) { return a > b ? a : b; }
inline double gclamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

// Godot's double wrapf (core/math/math_funcs.h), which GDScript's wrapf() is.
// godot-cpp has only a real_t one: called with doubles it rounds to float, and
// the strip's hinge speeds, read back off the angles through it, parted from
// the script's at 3e-8 on the first frame.
inline bool is_zero_approx(double v) { return std::fabs(v) < godot::CMP_EPSILON; }
inline bool is_equal_approx(double a, double b)
{
    if (a == b)
        return true;
    double tolerance = godot::CMP_EPSILON * std::fabs(a);
    if (tolerance < godot::CMP_EPSILON)
        tolerance = godot::CMP_EPSILON;
    return std::fabs(a - b) < tolerance;
}
inline double wrapf(double p_value, double p_min, double p_max)
{
    double range = p_max - p_min;
    if (is_zero_approx(range))
        return p_min;
    double result = p_value - (range * std::floor((p_value - p_min) / range));
    if (is_equal_approx(result, p_max))
        return p_min;
    return result;
}


// sin, cos, atan2 and exp from this library's libm, or from the engine's.
// GDScript calls the engine's, and the official Windows editor is built with
// MinGW, whose sin/cos/atan2 part from MSVC's in the last bit of a double now
// and then: 1e-16 in a hinge angle, which the float points rarely show, and
// which paper in contact (chaotic) could grow. The engine's cost a call into
// Godot each, so they are for checking the port to the bit (`engine_math`,
// paper_native_probe and gb_printer_tests native/), not for running it. sqrt is
// IEEE-exact everywhere.
struct Trig
{
    bool engine = false;
    double sin(double x) const { return engine ? godot::UtilityFunctions::sin(x) : std::sin(x); }
    double cos(double x) const { return engine ? godot::UtilityFunctions::cos(x) : std::cos(x); }
    double atan2(double y, double x) const { return engine ? godot::UtilityFunctions::atan2(y, x) : std::atan2(y, x); }
    double exp(double x) const { return engine ? godot::UtilityFunctions::exp(x) : std::exp(x); }
};

// Vector3 / int in GDScript: the int becomes a real_t.
inline Vector3 div(const Vector3 &v, int n) { return v / (real_t)n; }

inline Vector2 closest_point_to_segment(const Vector2 &p_point, const Vector2 &p_segment_a, const Vector2 &p_segment_b)
{
    Vector2 p = p_point - p_segment_a;
    Vector2 n = p_segment_b - p_segment_a;
    real_t l2 = n.length_squared();
    if (l2 < 1e-20f)
        return p_segment_a;
    real_t d = n.dot(p) / l2;
    if (d <= 0.0f)
        return p_segment_a;
    else if (d >= 1.0f)
        return p_segment_b;
    return p_segment_a + n * d;
}

inline bool segment_intersects_segment(const Vector2 &p_from_a, const Vector2 &p_to_a, const Vector2 &p_from_b, const Vector2 &p_to_b)
{
    Vector2 B = p_to_a - p_from_a;
    Vector2 C = p_from_b - p_from_a;
    Vector2 D = p_to_b - p_from_a;

    real_t ABlen = B.dot(B);
    if (ABlen <= 0)
        return false;
    Vector2 Bn = B / ABlen;
    C = Vector2(C.x * Bn.x + C.y * Bn.y, C.y * Bn.x - C.x * Bn.y);
    D = Vector2(D.x * Bn.x + D.y * Bn.y, D.y * Bn.x - D.x * Bn.y);

    if ((C.y < (real_t)-godot::CMP_EPSILON && D.y < (real_t)-godot::CMP_EPSILON) || (C.y > (real_t)godot::CMP_EPSILON && D.y > (real_t)godot::CMP_EPSILON))
        return false;
    if (godot::Math::is_equal_approx(C.y, D.y))
        return false;

    real_t ABpos = D.x + (C.x - D.x) * D.y / (D.y - C.y);
    if ((ABpos < 0) || (ABpos > 1))
        return false;
    return true;
}

inline Vector3 closest_point_to_segment(const Vector3 &p_point, const Vector3 &p_segment_a, const Vector3 &p_segment_b)
{
    Vector3 p = p_point - p_segment_a;
    Vector3 n = p_segment_b - p_segment_a;
    real_t l2 = n.length_squared();
    if (l2 < 1e-20f)
        return p_segment_a;
    real_t d = n.dot(p) / l2;
    if (d <= 0.0f)
        return p_segment_a;
    else if (d >= 1.0f)
        return p_segment_b;
    return p_segment_a + n * d;
}

inline void closest_points_between_segments(const Vector3 &p_p0, const Vector3 &p_p1, const Vector3 &p_q0, const Vector3 &p_q1, Vector3 &r_ps, Vector3 &r_qt)
{
    Vector3 p = p_p1 - p_p0;
    Vector3 q = p_q1 - p_q0;
    Vector3 r = p_p0 - p_q0;

    real_t a = p.dot(p);
    real_t b = p.dot(q);
    real_t c = q.dot(q);
    real_t d = p.dot(r);
    real_t e = q.dot(r);

    real_t s = 0.0f;
    real_t t = 0.0f;

    real_t det = a * c - b * b;
    if (det > godot::CMP_EPSILON) {
        real_t bte = b * e;
        real_t ctd = c * d;
        if (bte <= ctd) {
            if (e <= 0.0f) {
                s = (-d >= a ? 1 : (-d > 0.0f ? -d / a : 0.0f));
                t = 0.0f;
            } else if (e < c) {
                s = 0.0f;
                t = e / c;
            } else {
                s = (b - d >= a ? 1 : (b - d > 0.0f ? (b - d) / a : 0.0f));
                t = 1;
            }
        } else {
            s = bte - ctd;
            if (s >= det) {
                if (b + e <= 0.0f) {
                    s = (-d <= 0.0f ? 0.0f : (-d < a ? -d / a : 1));
                    t = 0.0f;
                } else if (b + e < c) {
                    s = 1;
                    t = (b + e) / c;
                } else {
                    s = (b - d <= 0.0f ? 0.0f : (b - d < a ? (b - d) / a : 1));
                    t = 1;
                }
            } else {
                real_t ate = a * e;
                real_t btd = b * d;
                if (ate <= btd) {
                    s = (-d <= 0.0f ? 0.0f : (-d >= a ? 1 : -d / a));
                    t = 0.0f;
                } else {
                    t = ate - btd;
                    if (t >= det) {
                        s = (b - d <= 0.0f ? 0.0f : (b - d >= a ? 1 : (b - d) / a));
                        t = 1;
                    } else {
                        s /= det;
                        t /= det;
                    }
                }
            }
        }
    } else {
        if (e <= 0.0f) {
            s = (-d <= 0.0f ? 0.0f : (-d >= a ? 1 : -d / a));
            t = 0.0f;
        } else if (e >= c) {
            s = (b - d <= 0.0f ? 0.0f : (b - d >= a ? 1 : (b - d) / a));
            t = 1;
        } else {
            s = 0.0f;
            t = e / c;
        }
    }

    r_ps = (1 - s) * p_p0 + s * p_p1;
    r_qt = (1 - t) * p_q0 + t * p_q1;
}
} // namespace Xenu::Paper
