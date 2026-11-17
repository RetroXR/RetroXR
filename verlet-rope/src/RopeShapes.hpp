#pragma once

// The shapes near a cord, as plain data (docs/dev/rope-collision-plan.md).
//
// A cord asks the engine ONE question a tick, "which bodies are near me", and
// reads each one's shape and transform out of the physics server. What it
// keeps is this: a flat list a solve can test its segments against on any
// thread, with no engine call and no Dictionary.

#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace Xenu
{

struct RopeShape
{
    enum Type : uint8_t
    {
        BOX,      // size = half extents
        SPHERE,   // size.x = radius
        CAPSULE,  // size.x = radius, size.y = half the height between the cap centres
        CYLINDER, // size.x = radius, size.y = half height
        CONVEX,   // hull = its faces' planes
        CONCAVE,  // seen, not tested against yet (plan, stage 2)
        OTHER,    // seen, not tested against (a height map, a world boundary)
        TYPE_COUNT
    };

    Type type = OTHER;
    // The shape's own frame in the world, WITHOUT its scale: `scale` is that,
    // and the sizes and planes are in the shape's own unscaled units.
    godot::Transform3D to_world;
    godot::Transform3D to_local;
    double scale = 1.0;
    godot::Vector3 size;
    // Its bounds in the world, grown by what a contact can reach.
    godot::Vector3 lo;
    godot::Vector3 hi;
    // A convex shape's faces, in its own frame, pointing out. Owned by the
    // cache in VerletRopeShapes.cpp, which outlives every cord's list.
    const std::vector<godot::Plane> *hull = nullptr;
    // Which body it belongs to, and which shape resource it is.
    uint64_t body = 0;
    int64_t shape = 0;
    // How many triangles a concave shape has (for the census).
    int triangles = 0;
    // The cord bore on it in the last solve: what a sleeping cord watches.
    bool touched = false;
};

// Where a point is against a shape: how far outside its surface (negative
// inside), the nearest point of the surface, and the way out, all in the world.
struct RopeNearest
{
    double distance = 0.0;
    godot::Vector3 point;
    godot::Vector3 normal;
};

bool rope_nearest_on_shape(const RopeShape &p_shape, const godot::Vector3 &p_world, RopeNearest &r_out);
// The point of segment a-b nearest the shape (r_t along it), and where that is
// against the shape.
bool rope_segment_nearest_on_shape(const RopeShape &p_shape, const godot::Vector3 &p_a,
                                   const godot::Vector3 &p_b, double &r_t, RopeNearest &r_out);

bool rope_way_in(const RopeShape &p_shape, const godot::Vector3 &p_from, const godot::Vector3 &p_to,
                 double p_step, double p_touch, RopeNearest &r_out);

} // namespace Xenu
