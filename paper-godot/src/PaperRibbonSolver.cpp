#include "PaperRibbonSolver.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;
using namespace Xenu::Paper;

namespace Xenu
{
namespace
{
// GbThermalRibbon's constants, same names.
constexpr double CURL_RADIUS = 0.065;
constexpr double MAX_STEP = 1.0 / 240.0;
constexpr int MAX_SUBSTEPS = 8;
constexpr int ITERATIONS = 8;
constexpr double SKIN = 0.0004;
constexpr double DRAG = 6.0;
constexpr double MAX_SPEED = 0.5;
constexpr double EI = 3.2e-5;
} // namespace

void PaperRibbonSolver::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("solve", "delta", "gravity", "angular_accel", "length", "width", "positions",
                             "velocities", "pin_row", "pin_positions", "patches"),
        &PaperRibbonSolver::solve);
    ClassDB::bind_method(D_METHOD("set_engine_math", "engine"), &PaperRibbonSolver::set_engine_math);
    ClassDB::bind_method(D_METHOD("get_engine_math"), &PaperRibbonSolver::get_engine_math);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "engine_math"), "set_engine_math", "get_engine_math");
}

Array PaperRibbonSolver::solve(double delta, Vector3 gravity, Vector3 angular_accel, double length, double width,
    PackedVector3Array positions, PackedVector3Array velocities, int pin_row, PackedVector3Array pin_positions,
    PackedFloat64Array patches)
{
    _length = length;
    _width = width;
    _positions.assign(positions.ptr(), positions.ptr() + positions.size());
    _velocities.assign(velocities.ptr(), velocities.ptr() + velocities.size());
    _segments = (int)_positions.size() / 2 - 1;
    _pin_row = pin_row;
    _pin_positions.assign(pin_positions.ptr(), pin_positions.ptr() + pin_positions.size());
    _patches.clear();
    for (int64_t i = 0; i + 8 < patches.size(); i += 9)
        _patches.push_back(Patch3{Vector3((real_t)patches[i], (real_t)patches[i + 1], (real_t)patches[i + 2]),
            patches[i + 3], Vector3((real_t)patches[i + 4], (real_t)patches[i + 5], (real_t)patches[i + 6]),
            patches[i + 7], patches[i + 8]});
    constraints();

    step(delta, gravity, angular_accel);

    PackedVector3Array out_positions;
    out_positions.resize((int64_t)_positions.size());
    std::copy(_positions.begin(), _positions.end(), out_positions.ptrw());
    PackedVector3Array out_velocities;
    out_velocities.resize((int64_t)_velocities.size());
    std::copy(_velocities.begin(), _velocities.end(), out_velocities.ptrw());
    PackedFloat64Array out_patches;
    out_patches.resize((int64_t)_patches.size() * 9);
    double *w = out_patches.ptrw();
    for (const Patch3 &patch : _patches) {
        *w++ = patch.normal.x;
        *w++ = patch.normal.y;
        *w++ = patch.normal.z;
        *w++ = patch.offset;
        *w++ = patch.center.x;
        *w++ = patch.center.y;
        *w++ = patch.center.z;
        *w++ = patch.reach;
        *w++ = patch.depth;
    }
    Array result;
    result.push_back(out_positions);
    result.push_back(out_velocities);
    result.push_back(_move_speed);
    result.push_back(_body_shift);
    result.push_back(_support_normal);
    result.push_back(out_patches);
    return result;
}

void PaperRibbonSolver::constraints()
{
    _edges.clear();
    _rest.clear();
    if (_segments <= 0)
        return;
    _mass = gmax(_length * 0.0057 / (double)_positions.size(), 1e-7);
    double ds = _length / _segments;
    auto edge = [this](int a, int b, double rest) {
        _edges.emplace_back(a, b);
        _rest.push_back(rest);
    };
    for (int row = 0; row < _segments + 1; row++) {
        edge(2 * row, 2 * row + 1, _width);
        if (row < _segments) {
            edge(2 * row, 2 * row + 2, ds);
            edge(2 * row + 1, 2 * row + 3, ds);
            edge(2 * row, 2 * row + 3, std::sqrt(ds * ds + _width * _width));
            edge(2 * row + 1, 2 * row + 2, std::sqrt(ds * ds + _width * _width));
        }
    }
}

void PaperRibbonSolver::step(double delta, Vector3 gravity, Vector3 angular_accel)
{
    _body_shift = Vector3();
    _support_normal = Vector3();
    _move_speed = 0.0;
    if (delta <= 0.0 || _segments <= 0)
        return;
    if (_pin_row < 0)
        recover_body_contacts();
    _patch_index.build_3d(_patches, SKIN);
    _weights.assign(_positions.size(), 1.0 / _mass);
    if (_pin_row >= 0) {
        _weights[2 * _pin_row] = 0.0;
        _weights[2 * _pin_row + 1] = 0.0;
    }
    std::vector<Vector3> before = _positions;
    double simulated = gmin(delta, MAX_STEP * MAX_SUBSTEPS);
    int steps = (int)gmax(1, std::ceil(simulated / MAX_STEP));
    double h = simulated / steps;
    for (int s = 0; s < steps; s++)
        substep(h, gravity, angular_accel);
    _move_speed = 0.0;
    for (size_t i = 0; i < _positions.size(); i++)
        _move_speed = gmax(_move_speed, (double)_positions[i].distance_to(before[i]) / simulated);
}

void PaperRibbonSolver::substep(double h, Vector3 gravity, Vector3 angular_accel)
{
    const size_t count = _positions.size();
    std::vector<Vector3> before = _positions;
    _contact_normals.assign(count, Vector3());
    double ds = _length / _segments;
    std::vector<Vector3> lambda_bend(count);
    const real_t drag = (real_t)_trig.exp(-DRAG * h);
    for (size_t i = 0; i < count; i++) {
        if (_weights[i] == 0.0)
            continue;
        _velocities[i] = (_velocities[i] * drag + (gravity - angular_accel.cross(_positions[i])) * (real_t)h)
                             .limit_length((real_t)MAX_SPEED);
        _positions[i] += _velocities[i] * (real_t)h;
    }
    double alpha = (ds * ds * ds / EI) / (h * h);
    double bend = 2.0 * ds * _trig.sin(ds / CURL_RADIUS * 0.5);
    for (int iteration = 0; iteration < ITERATIONS; iteration++) {
        for (int row = 1; row < _segments; row++) {
            Vector3 transverse = (_positions[row * 2] - _positions[row * 2 + 1]).normalized();
            for (int side = 0; side < 2; side++) {
                int b = row * 2 + side;
                int a = b - 2;
                int c = b + 2;
                Vector3 normal = (_positions[c] - _positions[a]).normalized().cross(transverse).normalized();
                Vector3 error = _positions[a] - (real_t)2.0 * _positions[b] + _positions[c] - normal * (real_t)bend;
                double wa = _weights[a];
                double wb = _weights[b];
                double wc = _weights[c];
                Vector3 change = (-error - (real_t)alpha * lambda_bend[b]) / (real_t)(wa + 4.0 * wb + wc + alpha);
                lambda_bend[b] += change;
                _positions[a] += (real_t)wa * change;
                _positions[b] -= (real_t)(2.0 * wb) * change;
                _positions[c] += (real_t)wc * change;
            }
        }
        for (size_t e = 0; e < _edges.size(); e++) {
            int a = _edges[e].first;
            int b = _edges[e].second;
            Vector3 d = _positions[b] - _positions[a];
            double distance = d.length();
            double wa = _weights[a];
            double wb = _weights[b];
            if (distance < 1e-9 || wa + wb == 0.0)
                continue;
            double change = -(distance - _rest[e]) / (wa + wb);
            _positions[a] -= d / (real_t)distance * (real_t)change * (real_t)wa;
            _positions[b] += d / (real_t)distance * (real_t)change * (real_t)wb;
        }
        surface_contacts();
        if (_pin_row >= 0) {
            _positions[2 * _pin_row] = _pin_positions[0];
            _positions[2 * _pin_row + 1] = _pin_positions[1];
        }
    }
    self_contacts(before);
    Vector3 shift;
    if (_pin_row < 0) {
        shift = mean(_positions) - mean(before);
        for (size_t i = 0; i < count; i++)
            _positions[i] -= shift;
    }
    double farthest = 0.0;
    for (size_t i = 0; i < count; i++)
        farthest = gmax(farthest, (double)_positions[i].distance_to(before[i]));
    double fraction = gmin(1.0, MAX_SPEED * h / gmax(farthest, 1e-9));
    for (size_t i = 0; i < count; i++) {
        _positions[i] = before[i].lerp(_positions[i], (real_t)fraction);
        _velocities[i] = (_positions[i] - before[i]) / (real_t)h;
        Vector3 normal = _contact_normals[i].normalized();
        _velocities[i] -= normal * normal.dot(_velocities[i]);
        _support_normal += normal;
    }
    if (_pin_row < 0 && !_patches.empty()) {
        shift *= (real_t)fraction;
        _body_shift += shift;
        shift_patches(shift);
    }
}

void PaperRibbonSolver::shift_patches(Vector3 shift)
{
    _patch_index.shift_frame(shift);
    for (Patch3 &patch : _patches) {
        patch.offset -= (double)patch.normal.dot(shift);
        patch.center -= shift;
    }
}

void PaperRibbonSolver::recover_body_contacts()
{
    for (size_t k = 0; k < _patches.size(); k++) {
        Vector3 normal = _patches[k].normal;
        double depth = 0.0;
        for (const Vector3 &p : _positions) {
            const Patch3 &patch = _patches[k];
            double u = patch.offset + SKIN - (double)normal.dot(p);
            Vector3 d = p - patch.center;
            if (u > depth && u < patch.depth && (double)(d - normal * normal.dot(d)).length() < patch.reach)
                depth = u;
        }
        if (depth > 0.0) {
            Vector3 shift = normal * (real_t)depth;
            _body_shift += shift;
            _support_normal += normal;
            shift_patches(shift);
        }
    }
}

void PaperRibbonSolver::surface_contacts()
{
    if (_patches.empty())
        return;
    for (size_t i = 0; i < _positions.size(); i++) {
        if (_weights[i] == 0.0)
            continue;
        std::vector<int> candidates = _patch_index.query(_positions[i]);
        size_t next = 0;
        int last = -1;
        while (next < candidates.size()) {
            int index = candidates[next];
            next++;
            if (index <= last)
                continue;
            last = index;
            const Patch3 &patch = _patches[index];
            Vector3 normal = patch.normal;
            Vector3 p = _positions[i];
            double u = patch.offset + SKIN - (double)normal.dot(p);
            Vector3 d = p - patch.center;
            if (u > 0.0 && u < patch.depth && (double)(d - normal * normal.dot(d)).length() < patch.reach) {
                _positions[i] += normal * (real_t)u;
                _contact_normals[i] += normal;
                candidates = _patch_index.query(_positions[i]);
                next = 0;
            }
        }
    }
}

void PaperRibbonSolver::self_contacts(const std::vector<Vector3> &before)
{
    std::vector<Vector3> mid(_segments + 1);
    for (int row = 0; row < _segments + 1; row++)
        mid[row] = (_positions[2 * row] + _positions[2 * row + 1]) * (real_t)0.5;
    _self_bounds.resize(_segments);
    for (int row = 0; row < _segments; row++)
        _self_bounds[row] = AABB(mid[row], Vector3()).expand(mid[row + 1]).grow((real_t)SKIN);
    for (int row = 0; row < _segments; row++) {
        AABB box = AABB(mid[row], Vector3()).expand(mid[row + 1]).grow((real_t)(SKIN * 2.0));
        for (int other = row + 2; other < _segments; other++) {
            if (!box.intersects(_self_bounds[other]))
                continue;
            Vector3 ps, qt;
            closest_points_between_segments(mid[row], mid[row + 1], mid[other], mid[other + 1], ps, qt);
            Vector3 d = ps - qt;
            if ((double)d.length_squared() >= SKIN * SKIN * 4.0)
                continue;
            Vector3 normal = d.normalized();
            if ((double)d.length_squared() < 1e-14) {
                Vector3 old = (before[2 * row] + before[2 * row + 1]) * (real_t)0.5;
                normal = (old - closest_point_to_segment(old, mid[other], mid[other + 1])).normalized();
            }
            Vector3 push = normal * (real_t)(SKIN * 2.0 - (double)d.length()) * (real_t)0.5;
            for (int i : {row * 2, row * 2 + 1, row * 2 + 2, row * 2 + 3})
                if (_weights[i] > 0.0)
                    _positions[i] += push;
            for (int i : {other * 2, other * 2 + 1, other * 2 + 2, other * 2 + 3})
                if (_weights[i] > 0.0)
                    _positions[i] -= push;
        }
    }
}

Vector3 PaperRibbonSolver::mean(const std::vector<Vector3> &points)
{
    Vector3 sum;
    for (const Vector3 &p : points)
        sum += p;
    return div(sum, (int)gmax(1, (double)points.size()));
}
} // namespace Xenu
