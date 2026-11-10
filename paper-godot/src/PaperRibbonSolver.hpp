#pragma once

// GbThermalRibbon.step(), ported: a torn-off print as a sheet of two rails,
// position-based (stretch, shear and signed bending constraints), in the print
// body's frame. The script keeps the ribbon (configure, pinning, snapshots) and
// hands one step at a time here; the reasoning behind every rule is in
// gb_thermal_ribbon.gd, beside the code this follows line for line.

#include "PaperContacts.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace Xenu
{
class PaperRibbonSolver : public godot::RefCounted
{
    GDCLASS(PaperRibbonSolver, godot::RefCounted)

public:
    // One step of `delta` seconds. Returns [positions, velocities, move_speed,
    // body_shift, support_normal, patches]: patches (nx, ny, nz, offset, cx, cy,
    // cz, reach, depth) come back moved into the recovered body's frame.
    godot::Array solve(double delta, godot::Vector3 gravity, godot::Vector3 angular_accel,
        double length, double width, godot::PackedVector3Array positions, godot::PackedVector3Array velocities,
        int pin_row, godot::PackedVector3Array pin_positions, godot::PackedFloat64Array patches);

    // Transcendentals from the engine (Paper::Trig): for a check to the bit.
    void set_engine_math(bool engine) { _trig.engine = engine; }
    bool get_engine_math() const { return _trig.engine; }

protected:
    static void _bind_methods();

private:
    void constraints();
    void step(double delta, godot::Vector3 gravity, godot::Vector3 angular_accel);
    void substep(double h, godot::Vector3 gravity, godot::Vector3 angular_accel);
    void shift_patches(godot::Vector3 shift);
    void recover_body_contacts();
    void surface_contacts();
    void self_contacts(const std::vector<godot::Vector3> &before);
    static godot::Vector3 mean(const std::vector<godot::Vector3> &points);

    double _length = 0.0;
    double _width = 0.0;
    int _segments = 0;
    std::vector<godot::Vector3> _positions;
    std::vector<godot::Vector3> _velocities;
    int _pin_row = -1;
    std::vector<godot::Vector3> _pin_positions;
    std::vector<Paper::Patch3> _patches;
    double _move_speed = 0.0;
    godot::Vector3 _body_shift;
    godot::Vector3 _support_normal;
    std::vector<std::pair<int, int>> _edges;
    std::vector<double> _rest;
    double _mass = 0.0;
    std::vector<godot::Vector3> _contact_normals;
    std::vector<double> _weights;
    Paper::Contacts _patch_index;
    Paper::Trig _trig;
    std::vector<godot::AABB> _self_bounds;
};
} // namespace Xenu
