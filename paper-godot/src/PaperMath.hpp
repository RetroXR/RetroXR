#pragma once

// The little geometry the paper solver needs that godot-cpp has no copy of.
// closest_points_between_segments is Godot 4.7.2's (core/math/geometry_3d.h).

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace Xenu::Paper
{
using godot::AABB;
using godot::real_t;
using godot::Vector3;

inline double gmin(double a, double b) { return a < b ? a : b; }
inline double gmax(double a, double b) { return a > b ? a : b; }
inline double gclamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

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
