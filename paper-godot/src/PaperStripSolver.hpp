#pragma once

// GbPrinterStrip.step(), ported: the paper standing out of the Game Boy
// Printer's slot, a 2D elastica of hinges in the printer's (Y, Z). The script
// keeps the strip (its state, its API, set_length and the rest) and hands one
// step at a time here; the reasoning behind every rule is in
// gb_printer_strip.gd, beside the code this follows line for line.

#include "PaperContacts.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace Xenu
{
class PaperStripSolver : public godot::RefCounted
{
    GDCLASS(PaperStripSolver, godot::RefCounted)

public:
    // One step of `dt` seconds. The state goes in and comes back as
    // [angles, speeds, points, sway, sway_speed, contact_motion]. boxes are
    // Rect2s as (position, size) pairs; planes (nx, ny, offset); patches (nx, ny,
    // offset, cx, cy, reach, depth); fingers (cx, cy, radius).
    godot::Array solve(double dt, godot::Vector2 gravity, double spin_accel, godot::Vector2 shove,
        double length, godot::Vector2 root, double root_angle,
        godot::PackedFloat64Array angles, godot::PackedFloat64Array speeds, godot::PackedVector2Array points,
        double sway, double sway_speed,
        godot::PackedVector2Array boxes, godot::PackedFloat64Array planes, godot::PackedFloat64Array patches,
        godot::PackedFloat64Array fingers, godot::PackedVector2Array other_paper, godot::Rect2 other_bounds);

    // Transcendentals from the engine (Paper::Trig): for a check to the bit.
    void set_engine_math(bool engine) { _trig.engine = engine; }
    bool get_engine_math() const { return _trig.engine; }

protected:
    static void _bind_methods();

private:
    struct Plane
    {
        godot::Vector2 normal;
        double offset;
    };
    struct Finger
    {
        godot::Vector2 center;
        double radius;
    };

    void step(double dt, godot::Vector2 gravity, double spin_accel, godot::Vector2 shove);
    void swing(double h, godot::Vector2 shove, double spin_accel);
    void substep(double h, godot::Vector2 gravity, double spin_accel);
    void lay_points();
    void limit_move(const std::vector<double> &before, const std::vector<godot::Vector2> &was, double limit);
    void contact();
    godot::Vector2 self_push(godot::Vector2 p, const std::vector<godot::Vector2> &out, int j);
    godot::Vector2 segment_push(godot::Vector2 start, godot::Vector2 end, godot::Vector2 a, godot::Vector2 b) const;
    godot::Vector2 push_out(godot::Vector2 p);
    godot::Vector2 off_surface(godot::Vector2 p);
    static double in_patch(const Paper::Patch2 &piece, godot::Vector2 p);
    static godot::Rect2 solid(const godot::Rect2 &box);
    bool in_solid(godot::Vector2 p) const;
    double under(godot::Vector2 p);
    double skin() const;

    double _length = 0.0;
    int _segments = 0;
    std::vector<double> _angles;
    std::vector<double> _speeds;
    double _sway = 0.0;
    double _sway_speed = 0.0;
    double _contact_motion = 0.0;
    godot::Vector2 _root;
    double _root_angle = 0.0;
    std::vector<godot::Vector2> _points;

    std::vector<godot::Rect2> _boxes;
    std::vector<Plane> _planes;
    std::vector<Paper::Patch2> _patches;
    std::vector<Finger> _fingers;
    std::vector<godot::Vector2> _other_paper;
    godot::Rect2 _other_bounds;
    Paper::Contacts _patch_index;
    Paper::Trig _trig;
    std::vector<godot::Rect2> _self_bounds;
};
} // namespace Xenu
