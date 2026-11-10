#include "PaperStripSolver.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;
using namespace Xenu::Paper;

namespace Xenu
{
namespace
{
// GbPrinterStrip's constants, same names.
constexpr double BEND_STIFFNESS = 3.2e-5;
constexpr double MASS_PER_M = 0.0057;
constexpr double CURL_RADIUS = 0.13;
constexpr double SWAY_W2 = 40.0;
constexpr double SWAY_REF_LENGTH = 0.1;
constexpr double SWAY_ZETA = 0.3;
constexpr double SWAY_GAIN = 0.3;
constexpr double SWAY_SPIN = 0.15;
constexpr double SWAY_MAX = 0.8;
constexpr double ROOT_HOLD = 6.0;
constexpr double DAMPING = 1.0;
constexpr double MAX_STEP = 1.0 / 240.0;
constexpr int MAX_SUBSTEPS = 8;
constexpr double CONTACT_FROM = 0.008;
constexpr int CONTACT_PASSES = 3;
constexpr double PATCH_DEPTH = 0.03;
constexpr double UNDER_BOX = 1.0;
constexpr double TERMINAL_SPEED = 0.5;
constexpr double REST_SPEED = 0.012;
constexpr double SKIN = 0.0008;
} // namespace

void PaperStripSolver::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("solve", "dt", "gravity", "spin_accel", "shove", "length", "root", "root_angle",
                             "angles", "speeds", "points", "sway", "sway_speed", "boxes", "planes", "patches", "fingers",
                             "other_paper", "other_bounds"),
        &PaperStripSolver::solve);
    ClassDB::bind_method(D_METHOD("set_engine_math", "engine"), &PaperStripSolver::set_engine_math);
    ClassDB::bind_method(D_METHOD("get_engine_math"), &PaperStripSolver::get_engine_math);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "engine_math"), "set_engine_math", "get_engine_math");
}

Array PaperStripSolver::solve(double dt, Vector2 gravity, double spin_accel, Vector2 shove,
    double length, Vector2 root, double root_angle,
    PackedFloat64Array angles, PackedFloat64Array speeds, PackedVector2Array points,
    double sway, double sway_speed,
    PackedVector2Array boxes, PackedFloat64Array planes, PackedFloat64Array patches,
    PackedFloat64Array fingers, PackedVector2Array other_paper, Rect2 other_bounds)
{
    _length = length;
    _segments = (int)angles.size();
    _angles.assign(angles.ptr(), angles.ptr() + angles.size());
    _speeds.assign(speeds.ptr(), speeds.ptr() + speeds.size());
    _points.assign(points.ptr(), points.ptr() + points.size());
    _sway = sway;
    _sway_speed = sway_speed;
    _root = root;
    _root_angle = root_angle;

    _boxes.clear();
    for (int64_t i = 0; i + 1 < boxes.size(); i += 2)
        _boxes.push_back(Rect2(boxes[i], boxes[i + 1]));
    _planes.clear();
    for (int64_t i = 0; i + 2 < planes.size(); i += 3)
        _planes.push_back(Plane{Vector2((real_t)planes[i], (real_t)planes[i + 1]), planes[i + 2]});
    _patches.clear();
    for (int64_t i = 0; i + 6 < patches.size(); i += 7)
        _patches.push_back(Patch2{Vector2((real_t)patches[i], (real_t)patches[i + 1]), patches[i + 2],
            Vector2((real_t)patches[i + 3], (real_t)patches[i + 4]), patches[i + 5], patches[i + 6]});
    _fingers.clear();
    for (int64_t i = 0; i + 2 < fingers.size(); i += 3)
        _fingers.push_back(Finger{Vector2((real_t)fingers[i], (real_t)fingers[i + 1]), fingers[i + 2]});
    _other_paper.assign(other_paper.ptr(), other_paper.ptr() + other_paper.size());
    _other_bounds = other_bounds;

    step(dt, gravity, spin_accel, shove);

    PackedFloat64Array out_angles;
    out_angles.resize((int64_t)_angles.size());
    std::copy(_angles.begin(), _angles.end(), out_angles.ptrw());
    PackedFloat64Array out_speeds;
    out_speeds.resize((int64_t)_speeds.size());
    std::copy(_speeds.begin(), _speeds.end(), out_speeds.ptrw());
    PackedVector2Array out_points;
    out_points.resize((int64_t)_points.size());
    std::copy(_points.begin(), _points.end(), out_points.ptrw());
    Array result;
    result.push_back(out_angles);
    result.push_back(out_speeds);
    result.push_back(out_points);
    result.push_back(_sway);
    result.push_back(_sway_speed);
    result.push_back(_contact_motion);
    return result;
}

void PaperStripSolver::step(double dt, Vector2 gravity, double spin_accel, Vector2 shove)
{
    if (_segments == 0 || dt <= 0.0)
        return;
    _patch_index.build_2d(_patches, SKIN);
    double simulated = gmin(dt, MAX_STEP * MAX_SUBSTEPS);
    int n_steps = (int)gmax(1, std::ceil(simulated / MAX_STEP));
    double h = simulated / n_steps;
    _contact_motion = 0.0;
    std::vector<Vector2> was = _points;
    for (int s = 0; s < n_steps; s++) {
        swing(h, shove, spin_accel);
        substep(h, gravity, spin_accel);
    }
    double farthest = 0.0;
    for (size_t i = 0; i < _points.size(); i++)
        farthest = gmax(farthest, (double)_points[i].distance_squared_to(was[i]));
    if (std::sqrt(farthest) < REST_SPEED * simulated)
        _contact_motion = 0.0;
}

void PaperStripSolver::swing(double h, Vector2 shove, double spin_accel)
{
    Vector2 mid = _points[_points.size() / 2] - _root;
    Vector2 across;
    if ((double)mid.length_squared() > 1e-10) {
        double phi = _trig.atan2(-(double)mid.y, (double)mid.x);
        across = Vector2((real_t)(-_trig.sin(phi)), (real_t)(-_trig.cos(phi)));
    }
    double w2 = SWAY_W2 * gclamp(SWAY_REF_LENGTH / _length, 0.4, 3.0);
    double push = SWAY_GAIN / gmax(_length, 0.02) * (double)shove.dot(across) + SWAY_SPIN * spin_accel;
    _sway_speed += (push - w2 * _sway - 2.0 * SWAY_ZETA * std::sqrt(w2) * _sway_speed) * h;
    _sway += _sway_speed * h;
    if (std::fabs(_sway) > SWAY_MAX) {
        _sway = gclamp(_sway, -SWAY_MAX, SWAY_MAX);
        _sway_speed = 0.0;
    }
}

void PaperStripSolver::lay_points()
{
    _points.resize(_segments + 1);
    double ds = _length / _segments;
    Vector2 p = _root;
    double phi = _root_angle;
    _points[0] = p;
    for (int i = 0; i < _segments; i++) {
        phi += _angles[i];
        p += Vector2((real_t)_trig.cos(phi), (real_t)(-_trig.sin(phi))) * (real_t)ds;
        _points[i + 1] = p;
    }
}

void PaperStripSolver::substep(double h, Vector2 gravity, double spin_accel)
{
    int n = _segments;
    double ds = _length / n;
    double m = MASS_PER_M * ds;
    double k = BEND_STIFFNESS / ds;
    double curl = ds / CURL_RADIUS;
    std::vector<double> before = _angles;

    Vector2 f = gravity * (real_t)m;
    Vector2 sum_f;
    double sum_cxf = 0.0;
    double sum_m = 0.0;
    Vector2 sum_mc;
    double sum_mcc = 0.0;
    std::vector<double> torque(n);
    std::vector<double> inertia(n);
    for (int i = n - 1; i >= 0; i--) {
        Vector2 c = (_points[i] + _points[i + 1]) * (real_t)0.5;
        sum_f += f;
        sum_cxf += (double)f.x * (double)c.y - (double)f.y * (double)c.x;
        sum_m += m;
        sum_mc += c * (real_t)m;
        sum_mcc += m * (double)c.length_squared() + m * ds * ds / 12.0;
        Vector2 p = _points[i];
        torque[i] = sum_cxf - ((double)sum_f.x * (double)p.y - (double)sum_f.y * (double)p.x);
        inertia[i] = sum_mcc - 2.0 * (double)p.dot(sum_mc) + (double)p.length_squared() * sum_m;
    }

    for (int i = 0; i < n; i++) {
        double ki = i == 0 ? k * ROOT_HOLD : k;
        double rest = i == 0 ? 0.0 : curl + _sway / (n - 1);
        double inert = inertia[i];
        double c = 2.0 * DAMPING * std::sqrt(ki * inert);
        double applied = torque[i] + spin_accel * inert;
        double w = (inert * _speeds[i] + h * (applied - ki * (_angles[i] - rest)))
            / (inert + h * c + h * h * ki);
        _speeds[i] = w;
        _angles[i] += h * w;
    }
    std::vector<Vector2> was = _points;
    lay_points();
    limit_move(before, was, TERMINAL_SPEED * h);
    std::vector<double> free_angles = _angles;
    contact();
    std::vector<bool> contacted(n);
    for (int i = 0; i < n; i++)
        contacted[i] = std::fabs(wrapf(_angles[i] - free_angles[i], -Math_PI, Math_PI)) > 1e-7;
    limit_move(before, was, TERMINAL_SPEED * h);
    for (int i = 0; i < n; i++) {
        _contact_motion = gmax(_contact_motion, std::fabs(wrapf(_angles[i] - before[i], -Math_PI, Math_PI)) / h);
        _speeds[i] = contacted[i] ? 0.0 : wrapf(_angles[i] - before[i], -Math_PI, Math_PI) / h;
    }
}

void PaperStripSolver::limit_move(const std::vector<double> &before, const std::vector<Vector2> &was, double limit)
{
    for (int pass = 0; pass < 8; pass++) {
        double farthest = 0.0;
        for (size_t i = 0; i < _points.size(); i++)
            farthest = gmax(farthest, (double)_points[i].distance_to(was[i]));
        if (farthest <= limit + 1e-7)
            return;
        double fraction = gmin(0.9, limit / farthest * 0.95);
        for (int i = 0; i < _segments; i++)
            _angles[i] = before[i] + wrapf(_angles[i] - before[i], -Math_PI, Math_PI) * fraction;
        lay_points();
    }
}

double PaperStripSolver::skin() const
{
    return gmin(SKIN * 2.0, _length / _segments * 0.25);
}

void PaperStripSolver::contact()
{
    double phi_min = 0.0;
    double phi_max = 0.0;
    double heading = 0.0;
    for (double angle : _angles) {
        heading += angle;
        phi_min = gmin(phi_min, heading);
        phi_max = gmax(phi_max, heading);
    }
    bool self_contact = phi_max - phi_min >= Math_PI - 0.05;
    bool external = !(_boxes.empty() && _planes.empty() && _patches.empty() && _fingers.empty());
    if (!self_contact && !external && _other_paper.empty())
        return;
    double ds = _length / _segments;
    int first = (int)gmax(1, std::ceil(CONTACT_FROM / ds));
    Vector2 shift;
    bool any = false;
    std::vector<Vector2> out = _points;
    _self_bounds.resize(_segments);
    for (int j = 1; j <= _segments; j++) {
        Vector2 was = _points[j];
        Vector2 p = was + shift;
        for (int attempt = 0; attempt < CONTACT_PASSES; attempt++) {
            Vector2 push = j >= first ? push_out(p) : Vector2();
            if (self_contact || any)
                push += self_push(p + push, out, j);
            if (!_other_paper.empty() && _other_bounds.intersects(Rect2(out[j - 1], p + push - out[j - 1]).abs(), true)) {
                for (int k = 0; k < (int)_other_paper.size() - 1; k++) {
                    if (j == 1 && k == 0)
                        continue;
                    push += segment_push(out[j - 1], p + push, _other_paper[k], _other_paper[k + 1]);
                }
            }
            if (push == Vector2())
                break;
            any = true;
            Vector2 d = (p + push) - out[j - 1];
            p = (double)d.length_squared() > 1e-14 ? out[j - 1] + d.normalized() * (real_t)ds : p + push;
        }
        out[j] = p;
        _self_bounds[j - 1] = Rect2(out[j - 1], p - out[j - 1]).abs();
        shift = p - was;
    }
    if (!any)
        return;
    double phi = _root_angle;
    for (int i = 0; i < _segments; i++) {
        Vector2 d = out[i + 1] - out[i];
        double seg_phi = _trig.atan2(-(double)d.y, (double)d.x);
        _angles[i] = wrapf(seg_phi - phi, -Math_PI, Math_PI);
        phi += _angles[i];
    }
    lay_points();
}

Vector2 PaperStripSolver::self_push(Vector2 p, const std::vector<Vector2> &out, int j)
{
    Vector2 start = out[j - 1];
    Vector2 push;
    double sk = skin();
    Rect2 bounds = Rect2(start, p - start).abs().grow((real_t)sk);
    for (int k = 0; k < j - 2; k++) {
        if (!bounds.intersects(_self_bounds[k], true))
            continue;
        Vector2 correction = segment_push(start, p + push, out[k], out[k + 1]);
        push += correction;
        if (correction != Vector2())
            bounds = Rect2(start, p + push - start).abs().grow((real_t)sk);
    }
    return push;
}

Vector2 PaperStripSolver::segment_push(Vector2 start, Vector2 end, Vector2 a, Vector2 b) const
{
    double sk = skin();
    if (gmin(start.x, end.x) > gmax(a.x, b.x) + sk || gmax(start.x, end.x) < gmin(a.x, b.x) - sk
        || gmin(start.y, end.y) > gmax(a.y, b.y) + sk || gmax(start.y, end.y) < gmin(a.y, b.y) - sk)
        return Vector2();
    Vector2 near_point = closest_point_to_segment(end, a, b);
    Vector2 d = end - near_point;
    if (segment_intersects_segment(start, end, a, b)) {
        Vector2 along = (b - a).normalized();
        Vector2 normal = Vector2((real_t)(-(double)along.y), along.x);
        if ((double)normal.dot(start - a) < 0.0)
            normal = -normal;
        return normal * (real_t)gmax(0.0, sk - (double)normal.dot(end - a));
    }
    if ((double)d.length_squared() < sk * sk) {
        Vector2 normal = (double)d.length_squared() > 1e-14 ? d.normalized() : (start - near_point).normalized();
        return normal * (real_t)(sk - (double)d.length());
    }
    return Vector2();
}

Vector2 PaperStripSolver::push_out(Vector2 p)
{
    Vector2 best;
    bool inside = false;
    double now_under = gmax(under(p), 0.0);
    Vector2 fallback;
    for (const Rect2 &box : _boxes) {
        Rect2 r = solid(box);
        if (!r.has_point(p))
            continue;
        inside = true;
        Vector2 end = r.get_end();
        const Vector2 ways[4] = {
            Vector2((real_t)((double)r.position.x - (double)p.x), 0.0f),
            Vector2((real_t)((double)end.x - (double)p.x), 0.0f),
            Vector2(0.0f, (real_t)((double)r.position.y - (double)p.y)),
            Vector2(0.0f, (real_t)((double)end.y - (double)p.y)),
        };
        for (const Vector2 &o : ways) {
            if (fallback == Vector2() || (double)o.length_squared() < (double)fallback.length_squared())
                fallback = o;
            if (best != Vector2() && (double)o.length_squared() >= (double)best.length_squared())
                continue;
            Vector2 to = p + o + o.normalized() * (real_t)1e-6;
            if (under(to) > now_under + SKIN * 0.5 || in_solid(to))
                continue;
            best = o;
        }
    }
    if (inside && best == Vector2())
        best = fallback;
    best += off_surface(p + best);
    for (const Finger &finger : _fingers) {
        Vector2 d = p + best - finger.center;
        double reach = finger.radius + SKIN;
        if ((double)d.length_squared() < reach * reach) {
            double l = d.length();
            best += (l > 1e-6 ? d / (real_t)l : Vector2(0.0f, -1.0f)) * (real_t)(reach - l);
        }
    }
    return best;
}

Vector2 PaperStripSolver::off_surface(Vector2 p)
{
    Vector2 out;
    double deepest = 0.0;
    for (const Plane &plane : _planes) {
        double u = plane.offset + SKIN - (double)plane.normal.dot(p);
        if (u > deepest) {
            deepest = u;
            out = plane.normal * (real_t)u;
        }
    }
    for (int index : _patch_index.query(Vector3(p.x, p.y, 0))) {
        const Patch2 &piece = _patches[index];
        double u = in_patch(piece, p);
        if (u > deepest) {
            deepest = u;
            out = piece.normal * (real_t)u;
        }
    }
    return out;
}

double PaperStripSolver::in_patch(const Patch2 &piece, Vector2 p)
{
    double u = piece.offset + SKIN - (double)piece.normal.dot(p);
    if (u <= 0.0 || u > piece.depth)
        return 0.0;
    Vector2 along = Vector2(piece.normal.y, (real_t)(-(double)piece.normal.x));
    if (std::fabs((double)along.dot(p - piece.center)) > piece.reach)
        return 0.0;
    return u;
}

Rect2 PaperStripSolver::solid(const Rect2 &box)
{
    Rect2 r = box.grow((real_t)SKIN);
    return Rect2(r.position - Vector2((real_t)UNDER_BOX, 0.0f), r.size + Vector2((real_t)UNDER_BOX, 0.0f));
}

bool PaperStripSolver::in_solid(Vector2 p) const
{
    for (const Rect2 &box : _boxes)
        if (solid(box).has_point(p))
            return true;
    return false;
}

double PaperStripSolver::under(Vector2 p)
{
    double deepest = -INFINITY;
    for (const Plane &plane : _planes)
        deepest = gmax(deepest, plane.offset + SKIN - (double)plane.normal.dot(p));
    if (!_patches.empty()) {
        deepest = gmax(deepest, 0.0);
        for (int index : _patch_index.query(Vector3(p.x, p.y, 0)))
            deepest = gmax(deepest, in_patch(_patches[index], p));
    }
    return deepest != -INFINITY ? deepest : 0.0;
}
} // namespace Xenu
