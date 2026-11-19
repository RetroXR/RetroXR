#include "PaperSheetSolver.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>

using namespace godot;
using namespace Xenu::Paper;

namespace Xenu
{
namespace
{
// Bending stiffness, N m^2: E about 3 GPa over a 38 x 0.15 mm section (sticker
// paper on its backing), and kg per meter of a 38 mm strip (about 150 g/m^2).
// Together they put the length the paper bends over under its own weight,
// (EI / (m g))^(1/3), at 8 cm: rows must be a good deal shorter than that or
// the sheet cannot draw a curve at all.
double EI = 3.2e-5;
constexpr double MASS_PER_M = 0.0057;
constexpr double REF_WIDTH = 0.038;
// Torsional stiffness of the same section, N m^2: G J with G = E / 2.6 and
// J = w t^3 / 3, which is 1.54 E I.
double GJ = 4.9e-5;
// Half the width of bend()'s band: a rail's bend reaches two rows each way.
constexpr int BAND = 4;
// No more steps a call than this, whatever is asked: below 30 FPS the paper
// advances more slowly rather than taking more of them.
constexpr int MAX_SUBSTEPS = 8;
int ITERATIONS = 4;
// Half the paper's thickness and a little: how far off a surface it lies.
double SKIN = 0.0004;
// How far apart two layers of the sheet's own midline are kept, meters.
double SELF_GAP = 0.0012;
// Air, 1/s, and the fastest any particle moves against its frame, m/s: about a
// strip of paper's speed falling flat.
double DRAG = 6.0;
double MAX_SPEED = 0.8;
// The tightest the paper bends, meters (fold_limit).
double MIN_RADIUS = 0.008;
// Paper on a desk, a console's plastic or other paper: static and kinetic.
double MU_STATIC = 0.45;
double MU_KINETIC = 0.35;
// How far under each of the body's boxes counts as the box, meters: under the
// printer is never where paper goes. It stands a hair off the table; paper crept
// into that gap and was pinched there when the printer was set down again.
constexpr double UNDER_BOX = 1.0;
} // namespace

void PaperSheetSolver::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("solve", "steps", "step_seconds", "gravity", "angular_accel", "origin", "frame_velocity",
                             "frame_spin", "ds", "width", "curl", "positions", "velocities", "pin_rows",
                             "pin_positions", "patches", "boxes", "box_free_rows", "fingers"),
        &PaperSheetSolver::solve);
    ClassDB::bind_static_method("PaperSheetSolver", D_METHOD("tune", "what", "value"), &PaperSheetSolver::tune);
}

// A probe's knob on the paper's constants, process-wide. Nothing shipped calls it.
void PaperSheetSolver::tune(const String &what, double value)
{
    if (what == "iterations") ITERATIONS = (int)value;
    else if (what == "self_gap") SELF_GAP = value;
    else if (what == "drag") DRAG = value;
    else if (what == "max_speed") MAX_SPEED = value;
    else if (what == "mu_static") MU_STATIC = value;
    else if (what == "mu_kinetic") MU_KINETIC = value;
    else if (what == "ei") EI = value;
    else if (what == "gj") GJ = value;
    else if (what == "min_radius") MIN_RADIUS = value;
}

Array PaperSheetSolver::solve(int steps, double step_seconds, Vector3 gravity, Vector3 angular_accel, Vector3 origin,
    Vector3 frame_velocity, Vector3 frame_spin, double ds, double width, double curl,
    PackedVector3Array positions, PackedVector3Array velocities,
    PackedInt32Array pin_rows, PackedVector3Array pin_positions,
    PackedFloat64Array patches, PackedVector3Array boxes, int box_free_rows,
    PackedFloat64Array fingers)
{
    _gravity = gravity;
    _angular_accel = angular_accel;
    _origin = origin;
    _frame_velocity = frame_velocity;
    _frame_spin = frame_spin;
    _ds = ds;
    _width = width;
    _curl = curl;
    _positions.assign(positions.ptr(), positions.ptr() + positions.size());
    _velocities.assign(velocities.ptr(), velocities.ptr() + velocities.size());
    _velocities.resize(_positions.size());
    _rows = (int)_positions.size() / 2;
    _box_free_rows = box_free_rows;

    _pin_particles.clear();
    _pin_targets.clear();
    _anchor.assign(_rows, -1);
    for (int64_t k = 0; k < pin_rows.size() && 2 * k + 1 < pin_positions.size(); k++) {
        int row = pin_rows[k];
        if (row < 0 || row >= _rows)
            continue;
        _pin_particles.push_back(2 * row);
        _pin_particles.push_back(2 * row + 1);
        _pin_targets.push_back(pin_positions[2 * k]);
        _pin_targets.push_back(pin_positions[2 * k + 1]);
        _anchor[row] = row;
    }
    _loose = _pin_particles.empty();
    if (!_loose) {
        // The nearest pinned row each way along the sheet.
        int last = -1;
        for (int row = 0; row < _rows; row++) {
            if (_anchor[row] == row)
                last = row;
            else
                _anchor[row] = last;
        }
        last = -1;
        for (int row = _rows - 1; row >= 0; row--) {
            if (_anchor[row] == row)
                last = row;
            else if (last >= 0 && (_anchor[row] < 0 || last - row < row - _anchor[row]))
                _anchor[row] = last;
        }
    }

    _patches.clear();
    for (int64_t i = 0; i + 8 < patches.size(); i += 9)
        _patches.push_back(Patch3{Vector3((real_t)patches[i], (real_t)patches[i + 1], (real_t)patches[i + 2]),
            patches[i + 3], Vector3((real_t)patches[i + 4], (real_t)patches[i + 5], (real_t)patches[i + 6]),
            patches[i + 7], patches[i + 8]});
    _solids.clear();
    for (int64_t i = 0; i + 1 < boxes.size(); i += 2) {
        AABB r = AABB(boxes[i], boxes[i + 1]).grow((real_t)SKIN);
        r.position.y -= (real_t)UNDER_BOX;
        r.size.y += (real_t)UNDER_BOX;
        _solids.push_back(r);
    }
    _fingers.clear();
    for (int64_t i = 0; i + 3 < fingers.size(); i += 4)
        _fingers.push_back(Finger{Vector3((real_t)fingers[i], (real_t)fingers[i + 1], (real_t)fingers[i + 2]), fingers[i + 3]});

    constraints();
    step(steps, step_seconds);

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

void PaperSheetSolver::constraints()
{
    // Each row's rung and each quad's two diagonals, solved one at a time. The
    // two rails are solved whole (rails()).
    _edges.clear();
    _rest.clear();
    _mass = gmax(MASS_PER_M * _ds * 0.5 * _width / REF_WIDTH, 1e-7);
    double diagonal = std::sqrt(_ds * _ds + _width * _width);
    for (int row = 0; row < _rows; row++) {
        _edges.emplace_back(2 * row, 2 * row + 1);
        _rest.push_back(_width);
        if (row + 1 < _rows) {
            _edges.emplace_back(2 * row, 2 * row + 3);
            _rest.push_back(diagonal);
            _edges.emplace_back(2 * row + 1, 2 * row + 2);
            _rest.push_back(diagonal);
        }
    }
}

// Both rails to their length, each as one chain: every gap's error at once, as
// one Newton step on all of a rail's lengths together (a symmetric tridiagonal
// system, solved exactly in O(rows)).
//
// Taken a gap at a time a correction crosses one row an iteration, and paper
// hanging from the slot carries its whole weight on every gap above: 25 cm of
// it read 27 cm long, and a metre across a table 96 cm.
void PaperSheetSolver::rails()
{
    const int gaps = _rows - 1;
    if (gaps < 1)
        return;
    _rail_dir.resize(gaps);
    _rail_diag.resize(gaps);
    _rail_off.resize(gaps);
    _rail_rhs.resize(gaps);
    for (int side = 0; side < 2; side++) {
        for (int i = 0; i < gaps; i++) {
            Vector3 d = _positions[2 * i + 2 + side] - _positions[2 * i + side];
            double length = d.length();
            _rail_dir[i] = length > 1e-9 ? d / (real_t)length : Vector3();
            double w = _weights[2 * i + side] + _weights[2 * i + 2 + side];
            _rail_diag[i] = w > 0.0 ? w : 1.0;
            _rail_rhs[i] = w > 0.0 ? -(length - _ds) : 0.0;
        }
        for (int i = 0; i + 1 < gaps; i++)
            _rail_off[i] = -_weights[2 * i + 2 + side] * (double)_rail_dir[i].dot(_rail_dir[i + 1]);
        // Thomas: forward elimination, then back.
        for (int i = 1; i < gaps; i++) {
            double m = _rail_off[i - 1] / _rail_diag[i - 1];
            _rail_diag[i] -= m * _rail_off[i - 1];
            _rail_rhs[i] -= m * _rail_rhs[i - 1];
        }
        _rail_rhs[gaps - 1] /= _rail_diag[gaps - 1];
        for (int i = gaps - 2; i >= 0; i--)
            _rail_rhs[i] = (_rail_rhs[i] - _rail_off[i] * _rail_rhs[i + 1]) / _rail_diag[i];
        for (int i = 0; i < gaps; i++) {
            Vector3 push = _rail_dir[i] * (real_t)_rail_rhs[i];
            _positions[2 * i + side] -= push * (real_t)_weights[2 * i + side];
            _positions[2 * i + 2 + side] += push * (real_t)_weights[2 * i + 2 + side];
        }
    }
}

void PaperSheetSolver::step(int steps, double h)
{
    _body_shift = Vector3();
    _support_normal = Vector3();
    _move_speed = 0.0;
    if (steps > MAX_SUBSTEPS)
        steps = MAX_SUBSTEPS;
    if (steps <= 0 || h <= 0.0 || _rows < 2 || _ds <= 0.0)
        return;
    if (_loose)
        recover_body_contacts();
    _patch_index.build_3d(_patches, SKIN);
    _weights.assign(_positions.size(), 1.0 / _mass);
    for (size_t k = 0; k < _pin_particles.size(); k++) {
        _weights[_pin_particles[k]] = 0.0;
        _positions[_pin_particles[k]] = _pin_targets[k];
        _velocities[_pin_particles[k]] = Vector3();
    }
    std::vector<Vector3> before = _positions;
    for (int s = 0; s < steps; s++)
        substep(h);
    for (size_t i = 0; i < _positions.size(); i++)
        _move_speed = gmax(_move_speed, (double)_positions[i].distance_to(before[i]) / (steps * h));
}

void PaperSheetSolver::substep(double h)
{
    const size_t count = _positions.size();
    std::vector<Vector3> before = _positions;
    _pressed_room.assign(count, Vector3());
    _pressed_body.assign(count, Vector3());
    _pressed_other.assign(count, Vector3());
    const real_t drag = (real_t)std::exp(-DRAG * h);
    for (size_t i = 0; i < count; i++) {
        if (_weights[i] == 0.0)
            continue;
        _velocities[i] = (_velocities[i] * drag
                             + (_gravity - _angular_accel.cross(_positions[i] - _origin)) * (real_t)h)
                             .limit_length((real_t)MAX_SPEED);
        _positions[i] += _velocities[i] * (real_t)h;
    }
    bend(h);
    for (int iteration = 0; iteration < ITERATIONS; iteration++) {
        rails();
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
            _positions[a] -= d / (real_t)distance * (real_t)(change * wa);
            _positions[b] += d / (real_t)distance * (real_t)(change * wb);
        }
        fold_limit(before);
        // The tether: no row farther from the nearest pinned row than the paper
        // between them is long, whatever the rest has not yet agreed.
        if (!_loose) {
            for (int row = 0; row < _rows; row++) {
                int anchor = _anchor[row];
                if (anchor < 0 || anchor == row)
                    continue;
                double reach = std::abs(row - anchor) * _ds;
                for (int side = 0; side < 2; side++) {
                    Vector3 from = _positions[2 * anchor + side];
                    Vector3 d = _positions[2 * row + side] - from;
                    double distance = d.length();
                    if (distance > reach)
                        _positions[2 * row + side] = from + d * (real_t)(reach / distance);
                }
            }
        }
        // The sheet against itself BEFORE the room: a layer lying on another on a
        // table was pushed into the table by the one above it after the table had
        // had its say, and the pair buzzed 0.3 mm a step for ever.
        self_contacts(before, 2.0 * MAX_SPEED * h);
        box_contacts();
        surface_contacts();
        finger_contacts();
        for (size_t k = 0; k < _pin_particles.size(); k++)
            _positions[_pin_particles[k]] = _pin_targets[k];
    }
    friction(before, h);
    // No point of the paper moves faster than MAX_SPEED, whatever pushed it.
    const real_t farthest = (real_t)(MAX_SPEED * h);
    for (size_t i = 0; i < count; i++)
        if (_weights[i] != 0.0)
            _positions[i] = before[i] + (_positions[i] - before[i]).limit_length(farthest);
    // A loose sheet keeps its local coordinates centered and hands what moved
    // the whole of it (contact) to its body. Discarding it drove the recovered
    // sheet straight back into the floor.
    Vector3 shift;
    if (_loose) {
        Vector3 now, then;
        for (size_t i = 0; i < count; i++) {
            now += _positions[i];
            then += before[i];
        }
        shift = (now - then) / (real_t)count;
        for (size_t i = 0; i < count; i++)
            _positions[i] -= shift;
    }
    for (size_t i = 0; i < count; i++) {
        if (_weights[i] == 0.0) {
            _velocities[i] = Vector3();
            continue;
        }
        _velocities[i] = (_positions[i] - before[i]) / (real_t)h;
        // Depenetration is positional repair, not a new bounce or bending impulse.
        Vector3 normal = (_pressed_room[i] + _pressed_body[i] + _pressed_other[i]).normalized();
        _velocities[i] -= normal * normal.dot(_velocities[i]);
        _support_normal += normal;
    }
    if (_loose && !_patches.empty()) {
        _body_shift += shift;
        shift_patches(shift);
    }
}

// One quadratic term of bend()'s energy: weight * |sum coef[k] x[index[k]] - target|^2.
// Pinned particles are where they are, so their part goes over to the target.
void PaperSheetSolver::add_term(const int *index, const double *coef, int count, double weight, Vector3 target)
{
    for (int a = 0; a < count; a++)
        if (_weights[index[a]] == 0.0)
            target -= _positions[index[a]] * (real_t)coef[a];
    for (int a = 0; a < count; a++) {
        int i = index[a];
        if (_weights[i] == 0.0)
            continue;
        _rhs[3 * i] += weight * coef[a] * target.x;
        _rhs[3 * i + 1] += weight * coef[a] * target.y;
        _rhs[3 * i + 2] += weight * coef[a] * target.z;
        for (int b = 0; b < count; b++) {
            int j = index[b];
            if (j < i || _weights[j] == 0.0)
                continue;
            _band[(size_t)i * (BAND + 1) + (j - i)] += weight * coef[a] * coef[b];
        }
    }
}

// Bending and twist, implicitly and exactly: the positions that minimize
//   sum m/h^2 |x - predicted|^2
//   + EI/2/ds^3 sum over each rail |x[b-1] - 2 x[b] + x[b+1] - r[b]|^2
//   + GJ/(w^2 ds) sum |(R - L)[i+1] - (R - L)[i]|^2
// where r[b] is what a rail's second difference is on the roll's curl, out of
// the sheet's face, and R - L is a row's rung: turning it from one row to the
// next is twist. One symmetric banded system over the particles, the same for
// all three axes, factored and solved in O(rows).
//
// Bent row by row instead (Gauss-Seidel, as the sheet first was), a correction
// crosses one row an iteration: at 6 mm rows eight iterations left the paper a
// third as stiff as EI says, a fold on a table closed to a 7 mm hairpin, and
// thirty-two iterations to get it right cost 3 ms a step. And with no twist term
// the rails only resist twist at second order: fed onto a table the strip
// wandered 13 cm sideways off a perfectly straight start.
void PaperSheetSolver::bend(double h)
{
    const int n = _rows;
    const int unknowns = 2 * n;
    if (n < 3)
        return;
    const double share = _width / REF_WIDTH;
    const double k_bend = EI * share * 0.5 / (_ds * _ds * _ds);
    const double k_twist = GJ * share / (_width * _width * _ds);
    const double inertia = _mass / (h * h);
    const double rest = 2.0 * _ds * std::sin(_ds * _curl * 0.5);
    _band.assign((size_t)unknowns * (BAND + 1), 0.0);
    _rhs.assign((size_t)unknowns * 3, 0.0);
    for (int i = 0; i < unknowns; i++) {
        const Vector3 &p = _positions[i];
        double scale = _weights[i] == 0.0 ? 1.0 : inertia;
        _band[(size_t)i * (BAND + 1)] = scale;
        _rhs[3 * i] = scale * p.x;
        _rhs[3 * i + 1] = scale * p.y;
        _rhs[3 * i + 2] = scale * p.z;
    }
    // Targets are read off the predicted sheet before any of it is solved.
    _targets.resize(unknowns);
    for (int b = 1; b < n - 1; b++) {
        // The local transverse axis follows the sheet, allowing twist instead of
        // locking the curl to a world plane.
        Vector3 transverse = (_positions[2 * b] - _positions[2 * b + 1]).normalized();
        for (int side = 0; side < 2; side++) {
            Vector3 along = (_positions[2 * b + 2 + side] - _positions[2 * b - 2 + side]).normalized();
            // A pinned row is held flat (the slot's lips, a hand): the curl
            // starts past it, not a row inside the slot.
            _targets[2 * b + side] = _weights[2 * b + side] == 0.0
                ? Vector3() : along.cross(transverse).normalized() * (real_t)rest;
        }
    }
    const double second[3] = {1.0, -2.0, 1.0};
    const double turn[4] = {-1.0, 1.0, 1.0, -1.0};
    for (int b = 1; b < n - 1; b++)
        for (int side = 0; side < 2; side++) {
            const int index[3] = {2 * b - 2 + side, 2 * b + side, 2 * b + 2 + side};
            add_term(index, second, 3, k_bend, _targets[2 * b + side]);
        }
    for (int row = 0; row < n - 1; row++) {
        const int index[4] = {2 * row, 2 * row + 1, 2 * row + 2, 2 * row + 3};
        add_term(index, turn, 4, k_twist, Vector3());
    }
    // L D L^T in the band: the diagonal becomes D, the rest of each row L's column.
    for (int i = 0; i < unknowns; i++) {
        double *row = &_band[(size_t)i * (BAND + 1)];
        double d = row[0];
        for (int j = 1; j <= BAND && i + j < unknowns; j++) {
            double l = row[j] / d;
            if (l != 0.0) {
                double *below = &_band[(size_t)(i + j) * (BAND + 1)];
                for (int k = j; k <= BAND && i + k < unknowns; k++)
                    below[k - j] -= l * row[k];
            }
            row[j] = l;
        }
    }
    for (int axis = 0; axis < 3; axis++) {
        for (int i = 0; i < unknowns; i++) {
            const double *row = &_band[(size_t)i * (BAND + 1)];
            double v = _rhs[3 * i + axis];
            for (int j = 1; j <= BAND && i + j < unknowns; j++)
                _rhs[3 * (i + j) + axis] -= row[j] * v;
        }
        for (int i = unknowns - 1; i >= 0; i--) {
            const double *row = &_band[(size_t)i * (BAND + 1)];
            double v = _rhs[3 * i + axis] / row[0];
            for (int j = 1; j <= BAND && i + j < unknowns; j++)
                v -= row[j] * _rhs[3 * (i + j) + axis];
            _rhs[3 * i + axis] = v;
        }
    }
    for (int i = 0; i < unknowns; i++)
        if (_weights[i] != 0.0)
            _positions[i] = Vector3((real_t)_rhs[3 * i], (real_t)_rhs[3 * i + 1], (real_t)_rhs[3 * i + 2]);
}

// Paper bends no tighter than MIN_RADIUS without creasing, and this paper does
// not crease: the rows either side of a row are kept at least the chord of that
// bend apart. The bend energy is a second difference, whose pull back falls off
// past a right angle and is nothing at all on a fold laid flat, so without this
// a loop falling over on a table could snap shut into a crease and stay.
void PaperSheetSolver::fold_limit(const std::vector<Vector3> &before)
{
    double sharpest = gmin(_ds / MIN_RADIUS, 1.2);
    double chord = 2.0 * _ds * std::cos(sharpest * 0.5);
    for (int row = 1; row < _rows - 1; row++)
        for (int side = 0; side < 2; side++) {
            int a = 2 * row - 2 + side;
            int c = 2 * row + 2 + side;
            double wa = _weights[a];
            double wc = _weights[c];
            if (wa + wc == 0.0)
                continue;
            Vector3 d = _positions[c] - _positions[a];
            double distance = d.length();
            if (distance >= chord)
                continue;
            if (distance < 1e-7) {
                d = before[c] - before[a];
                distance = d.length();
                if (distance < 1e-7)
                    continue;
                d *= (real_t)(1e-7 / distance);
                distance = 1e-7;
            }
            Vector3 push = d * (real_t)((chord - distance) / distance / (wa + wc));
            _positions[a] -= push * (real_t)wa;
            _positions[c] += push * (real_t)wc;
        }
}

void PaperSheetSolver::shift_patches(Vector3 shift)
{
    _patch_index.shift_frame(shift);
    for (Patch3 &patch : _patches) {
        patch.offset -= (double)patch.normal.dot(shift);
        patch.center -= shift;
    }
}

// First recover penetration caused by the body's fall as a whole. Letting the
// individual rails do this buckled the print around its fixed centroid.
// Subsequent bending still meets the surface in surface_contacts().
void PaperSheetSolver::recover_body_contacts()
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

void PaperSheetSolver::surface_contacts()
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
                _pressed_room[i] += normal * (real_t)u;
                // A push can enter another cell. Continue from this patch in the
                // original ordering, including any later patches newly in reach.
                candidates = _patch_index.query(_positions[i]);
                next = 0;
            }
        }
    }
}

// How far `p` is into the patch of surface it is deepest in, or 0.
double PaperSheetSolver::under(const Vector3 &p)
{
    double deepest = 0.0;
    for (int index : _patch_index.query(p)) {
        const Patch3 &patch = _patches[index];
        double u = patch.offset + SKIN - (double)patch.normal.dot(p);
        Vector3 d = p - patch.center;
        if (u > deepest && u < patch.depth && (double)(d - patch.normal * patch.normal.dot(d)).length() < patch.reach)
            deepest = u;
    }
    return deepest;
}

bool PaperSheetSolver::in_solid(const Vector3 &p) const
{
    for (const AABB &box : _solids)
        if (box.has_point(p))
            return true;
    return false;
}

// How far, and which way, `p` has to go to be out of the body's boxes: the
// nearest face of the box it is in that the rules below allow.
//
// The boxes are one solid: a way out of one is taken only if it is clear of all
// of them. Each box on its own sent a point under the roll cover's hump up out of
// the body's top, into the hump, and the hump sent it back down; the two pushes
// cancelled and the paper stayed inside the printer. Nor is a way out taken that
// goes deeper into a surface than the point already is. Deeper, not into at all:
// paper lying ON the table touches it, and a rule against any touch shut it out
// of its way out sideways.
Vector3 PaperSheetSolver::box_push(const Vector3 &p)
{
    Vector3 best;
    Vector3 fallback;
    bool inside = false;
    double now_under = -1.0;
    for (const AABB &r : _solids) {
        if (!r.has_point(p))
            continue;
        inside = true;
        if (now_under < 0.0)
            now_under = under(p);
        Vector3 end = r.get_end();
        const Vector3 ways[6] = {
            Vector3(r.position.x - p.x, 0, 0),
            Vector3(end.x - p.x, 0, 0),
            Vector3(0, r.position.y - p.y, 0),
            Vector3(0, end.y - p.y, 0),
            Vector3(0, 0, r.position.z - p.z),
            Vector3(0, 0, end.z - p.z),
        };
        for (const Vector3 &o : ways) {
            if (fallback == Vector3() || o.length_squared() < fallback.length_squared())
                fallback = o;
            if (best != Vector3() && o.length_squared() >= best.length_squared())
                continue;
            // Just past the face, so the box it leaves does not count it in.
            Vector3 to = p + o + o.normalized() * (real_t)1e-5;
            if (under(to) > now_under + SKIN * 0.5 || in_solid(to))
                continue;
            best = o;
        }
    }
    if (inside && best == Vector3())
        best = fallback;
    return best;
}

void PaperSheetSolver::box_contacts()
{
    if (_solids.empty())
        return;
    for (int i = (_box_free_rows > 0 ? _box_free_rows : 0) * 2; i < (int)_positions.size(); i++) {
        if (_weights[i] == 0.0)
            continue;
        Vector3 push = box_push(_positions[i]);
        if (push == Vector3())
            continue;
        _positions[i] += push;
        _pressed_body[i] += push;
    }
}

// A fingertip against each rung, not each particle: the rails are 38 mm apart
// and a finger between them would touch neither.
void PaperSheetSolver::finger_contacts()
{
    for (const Finger &finger : _fingers) {
        double reach = finger.radius + SKIN;
        for (int row = 0; row < _rows; row++) {
            int a = 2 * row;
            int b = a + 1;
            double wa = _weights[a] > 0.0 ? 1.0 : 0.0;
            double wb = _weights[b] > 0.0 ? 1.0 : 0.0;
            if (wa + wb == 0.0)
                continue;
            Vector3 rung = _positions[b] - _positions[a];
            double l2 = rung.length_squared();
            double t = l2 > 1e-12 ? gclamp((double)rung.dot(finger.center - _positions[a]) / l2, 0.0, 1.0) : 0.0;
            Vector3 d = _positions[a] + rung * (real_t)t - finger.center;
            double distance = d.length();
            if (distance >= reach)
                continue;
            // Straight through the middle of a finger: out along the sheet's face.
            Vector3 normal = distance > 1e-6 ? d / (real_t)distance : Vector3(0, 1, 0);
            Vector3 push = normal * (real_t)(reach - distance);
            // Moving a by (1-t) k and b by t k moves the touched point by
            // ((1-t)^2 + t^2) k.
            double ka = (1.0 - t) * wa;
            double kb = t * wb;
            double scale = ka * (1.0 - t) + kb * t;
            if (scale < 1e-6)
                continue;
            _positions[a] += push * (real_t)(ka / scale);
            _positions[b] += push * (real_t)(kb / scale);
            _pressed_other[a] += push * (real_t)(ka / scale);
            _pressed_other[b] += push * (real_t)(kb / scale);
        }
    }
}

// The sheet against itself, midline to midline: two stretches of it closer than
// SELF_GAP are pushed apart. Neighbors share a row and are left out; the next but
// one are not, which is also what keeps a fold forced by contact from closing
// tighter than a row. Swept along the sheet's longest axis so a long strip does
// not test every stretch against every other.
//
// A stretch can move 3 mm in a step and the gap is 1.2: two that were apart and
// are now PAST each other (on the far side of where they faced one another at
// the step's start) went through, and are put back on their own sides. Judged by
// distance alone, a strip curling up weightless coiled through itself.
void PaperSheetSolver::self_contacts(const std::vector<Vector3> &before, double reach)
{
    int segments = _rows - 1;
    if (segments < 3)
        return;
    _self_mid.resize(_rows);
    _self_was.resize(_rows);
    AABB all;
    for (int row = 0; row < _rows; row++) {
        _self_mid[row] = (_positions[2 * row] + _positions[2 * row + 1]) * (real_t)0.5;
        _self_was[row] = (before[2 * row] + before[2 * row + 1]) * (real_t)0.5;
        if (row == 0)
            all = AABB(_self_mid[0], Vector3());
        else
            all.expand_to(_self_mid[row]);
    }
    const std::vector<Vector3> &mid = _self_mid;
    const std::vector<Vector3> &was = _self_was;
    int axis = all.get_longest_axis_index();
    _self_bounds.resize(segments);
    _self_order.resize(segments);
    for (int row = 0; row < segments; row++) {
        AABB box(mid[row], Vector3());
        box.expand_to(mid[row + 1]);
        box.expand_to(was[row]);
        box.expand_to(was[row + 1]);
        _self_bounds[row] = box.grow((real_t)(SELF_GAP * 0.5));
        _self_order[row] = row;
    }
    std::sort(_self_order.begin(), _self_order.end(), [&](int a, int b) {
        return _self_bounds[a].position[axis] < _self_bounds[b].position[axis];
    });
    for (int i = 0; i < segments; i++) {
        int first = _self_order[i];
        real_t end = _self_bounds[first].position[axis] + _self_bounds[first].size[axis];
        for (int j = i + 1; j < segments; j++) {
            int second = _self_order[j];
            if (_self_bounds[second].position[axis] > end)
                break;
            int row = first < second ? first : second;
            int other = first < second ? second : first;
            if (other - row < 2 || !_self_bounds[row].intersects(_self_bounds[other]))
                continue;
            Vector3 ps, qt;
            closest_points_between_segments(mid[row], mid[row + 1], mid[other], mid[other + 1], ps, qt);
            Vector3 d = ps - qt;
            double distance = d.length();
            if (distance >= SELF_GAP + reach)
                continue;
            // Which side of each other they were on as the step began.
            Vector3 ps0, qt0;
            closest_points_between_segments(was[row], was[row + 1], was[other], was[other + 1], ps0, qt0);
            Vector3 d0 = ps0 - qt0;
            double distance0 = d0.length();
            Vector3 normal;
            double depth;
            if (distance0 > 1e-7 && distance0 < SELF_GAP + reach && (double)d.dot(d0) < 0.0) {
                normal = d0 / (real_t)distance0;
                depth = SELF_GAP - (double)d.dot(normal);
            } else if (distance >= SELF_GAP) {
                continue;
            } else if (distance > 1e-7) {
                normal = d / (real_t)distance;
                depth = SELF_GAP - distance;
            } else if (distance0 > 1e-7) {
                normal = d0 / (real_t)distance0;
                depth = SELF_GAP;
            } else {
                continue;
            }
            const int mine[4] = {row * 2, row * 2 + 1, row * 2 + 2, row * 2 + 3};
            const int theirs[4] = {other * 2, other * 2 + 1, other * 2 + 2, other * 2 + 3};
            bool free_mine = false, free_theirs = false;
            for (int k : mine)
                free_mine = free_mine || _weights[k] > 0.0;
            for (int k : theirs)
                free_theirs = free_theirs || _weights[k] > 0.0;
            if (!free_mine && !free_theirs)
                continue;
            real_t share = free_mine && free_theirs ? (real_t)0.5 : (real_t)1.0;
            Vector3 push = normal * (real_t)depth * share;
            // Paper on paper rubs as paper on a table does: what the two did
            // ALONG each other this step, against how hard this pressed them.
            // Without it a loop lying on its own strip slid off it at any tilt.
            Vector3 slid;
            for (int k = 0; k < 4; k++)
                slid += (_positions[mine[k]] - before[mine[k]]) - (_positions[theirs[k]] - before[theirs[k]]);
            slid *= (real_t)0.25;
            slid -= normal * normal.dot(slid);
            double slide = slid.length();
            if (slide > 1e-12)
                push -= slid * (real_t)(share * (slide <= MU_STATIC * depth ? 1.0 : MU_KINETIC * depth / slide));
            for (int k : mine)
                if (_weights[k] > 0.0) {
                    _positions[k] += push;
                    _pressed_other[k] += push;
                }
            for (int k : theirs)
                if (_weights[k] > 0.0) {
                    _positions[k] -= push;
                    _pressed_other[k] -= push;
                }
        }
    }
}

// Coulomb, on what each particle did this substep ALONG what it was pressed on,
// against how hard it was pressed (the push that kept it out, which is the
// normal force's work over the step): held still under the static limit, slowed
// by the kinetic one past it. The room stands still in the room, so in a moving
// frame its surface moves the other way; the body's own boxes move with the frame.
void PaperSheetSolver::friction(const std::vector<Vector3> &before, double h)
{
    for (size_t i = 0; i < _positions.size(); i++) {
        if (_weights[i] == 0.0)
            continue;
        for (int kind = 0; kind < 2; kind++) {
            const Vector3 &pressed = kind == 0 ? _pressed_room[i] : _pressed_body[i];
            double force = pressed.length();
            if (force < 1e-9)
                continue;
            Vector3 normal = pressed / (real_t)force;
            Vector3 surface;
            if (kind == 0)
                surface = -(_frame_velocity + _frame_spin.cross(_positions[i] - _origin)) * (real_t)h;
            Vector3 slid = _positions[i] - before[i] - surface;
            slid -= normal * normal.dot(slid);
            double distance = slid.length();
            if (distance < 1e-12)
                continue;
            if (distance <= MU_STATIC * force)
                _positions[i] -= slid;
            else
                _positions[i] -= slid * (real_t)(MU_KINETIC * force / distance);
        }
    }
}
} // namespace Xenu
