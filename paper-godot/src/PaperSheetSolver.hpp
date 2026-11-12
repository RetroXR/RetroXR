#pragma once

// PaperSheetSolver: one step of a strip of thermal paper, for GbThermalRibbon.
//
// The Game Boy Printer's paper is ONE model wherever it is: standing out of the
// printer's slot (rows pinned inside the slot, the rest free), held in a hand (the
// row in the hand pinned) or loose (nothing pinned, its rigid body owning the
// fall). A sheet of two rails, a particle on each edge of every row, in the frame
// of the body it belongs to:
//
//   stretch + shear   each rail keeps its length, solved as a whole chain
//                     (rails()), and every quad between two rows its rungs and
//                     diagonals, so the paper neither stretches nor shears;
//   bend + twist      signed, per rail, toward the roll's curl, and each row's
//                     rung against turning from the last, with the paper's own
//                     stiffnesses: implicit, one banded solve (bend());
//   tether            no row is farther from the nearest pinned row than the paper
//                     between them is long: what keeps a metre of it hanging from
//                     the slot from stretching while the stretch rows converge;
//   contact           per particle against patches of the room, the body's own
//                     boxes (the printer) and fingertips (per rung, so a finger
//                     between the rails still meets paper), then the sheet against
//                     itself, midline to midline;
//   friction          Coulomb, against what a particle was pressed on by how hard
//                     it was pressed: paper lying on a table stays where it lies,
//                     and paper fed onto it slides or buckles into a loop.
//
// It was two solvers (a 2D hinge chain on the printer, this sheet for a torn
// print), each with a GDScript twin kept to the bit. The chain loaded every hinge
// with all the paper past it whether or not that paper lay on a table, and its
// contact could fold it to any angle: long strips zig-zagged (docs/dev/gb-printer.md).

#include "PaperContacts.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace Xenu
{
class PaperSheetSolver : public godot::RefCounted
{
    GDCLASS(PaperSheetSolver, godot::RefCounted)

public:
    // `steps` steps of `step_seconds` each of a sheet whose rows are `ds` apart,
    // two particles a row (+across, -across). The caller keeps the step ONE
    // length (GbThermalRibbon.STEP): where the sheet comes to rest depends a
    // little on it, and cut to fit each frame the paper never came to rest in a
    // window whose frames were not all alike.
    //   gravity, angular_accel   the frame's apparent gravity and angular
    //                            acceleration, the latter about `origin`;
    //   frame_velocity, frame_spin  how the frame itself moves (its own axes), so
    //                            friction on the room is against the ROOM;
    //   curl                     the bend the roll left in it, rad/m;
    //   pin_rows, pin_positions  rows held where they are told, two positions each;
    //   patches                  nine numbers each (nx ny nz offset cx cy cz reach depth);
    //   boxes                    the body's own boxes, position then size, which
    //                            rows before `box_free_rows` do not meet (the slot
    //                            is inside one);
    //   fingers                  four numbers each (x y z radius).
    // Returns [positions, velocities, move_speed, body_shift, support_normal,
    // patches]; the patches come back moved into a loose sheet's recovered frame.
    godot::Array solve(int steps, double step_seconds, godot::Vector3 gravity, godot::Vector3 angular_accel, godot::Vector3 origin,
        godot::Vector3 frame_velocity, godot::Vector3 frame_spin, double ds, double width, double curl,
        godot::PackedVector3Array positions, godot::PackedVector3Array velocities,
        godot::PackedInt32Array pin_rows, godot::PackedVector3Array pin_positions,
        godot::PackedFloat64Array patches, godot::PackedVector3Array boxes, int box_free_rows,
        godot::PackedFloat64Array fingers);

    static void tune(const godot::String &what, double value);

protected:
    static void _bind_methods();

private:
    struct Finger
    {
        godot::Vector3 center;
        double radius = 0.0;
    };

    void constraints();
    void step(int steps, double h);
    void substep(double h);
    void rails();
    void bend(double h);
    void add_term(const int *index, const double *coef, int count, double weight, godot::Vector3 target);
    void fold_limit(const std::vector<godot::Vector3> &before);
    void shift_patches(godot::Vector3 shift);
    void recover_body_contacts();
    void surface_contacts();
    void box_contacts();
    void finger_contacts();
    void self_contacts(const std::vector<godot::Vector3> &before, double reach);
    void friction(const std::vector<godot::Vector3> &before, double h);
    double under(const godot::Vector3 &p);
    bool in_solid(const godot::Vector3 &p) const;
    godot::Vector3 box_push(const godot::Vector3 &p);

    godot::Vector3 _gravity;
    godot::Vector3 _angular_accel;
    godot::Vector3 _origin;
    godot::Vector3 _frame_velocity;
    godot::Vector3 _frame_spin;
    double _ds = 0.0;
    double _width = 0.0;
    double _curl = 0.0;
    int _rows = 0;
    int _box_free_rows = 0;
    bool _loose = true;
    std::vector<godot::Vector3> _positions;
    std::vector<godot::Vector3> _velocities;
    std::vector<godot::Vector3> _pin_targets;
    std::vector<int> _pin_particles;
    // Per row: the nearest pinned row, or -1.
    std::vector<int> _anchor;
    std::vector<Paper::Patch3> _patches;
    std::vector<godot::AABB> _solids;
    std::vector<Finger> _fingers;
    double _move_speed = 0.0;
    godot::Vector3 _body_shift;
    godot::Vector3 _support_normal;
    std::vector<std::pair<int, int>> _edges;
    std::vector<double> _rest;
    double _mass = 0.0;
    std::vector<double> _weights;
    // What pressed each particle this substep, summed: the room, and the body's
    // own boxes. Their lengths are how hard, for friction.
    std::vector<godot::Vector3> _pressed_room;
    std::vector<godot::Vector3> _pressed_body;
    std::vector<godot::Vector3> _pressed_other;
    Paper::Contacts _patch_index;
    std::vector<godot::AABB> _self_bounds;
    std::vector<int> _self_order;
    std::vector<godot::Vector3> _self_mid, _self_was;
    // bend()'s banded system and its right-hand sides.
    std::vector<double> _band, _rhs;
    std::vector<godot::Vector3> _targets;
    // rails()'s tridiagonal system.
    std::vector<godot::Vector3> _rail_dir;
    std::vector<double> _rail_diag, _rail_off, _rail_rhs;
};
} // namespace Xenu
