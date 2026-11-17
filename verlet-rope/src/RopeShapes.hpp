#pragma once

// The shapes near a cord, as plain data (docs/dev/rope-collision-plan.md).
//
// A cord asks the engine ONE question a tick, "which bodies are near me", and
// reads each one's shape and transform out of the physics server. What it
// keeps is this: a flat list a solve can test its segments against on any
// thread, with no engine call and no Dictionary.

#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>

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
        CONVEX,   // data = index of its hull
        CONCAVE,  // data = index of its mesh
        OTHER,    // seen, not tested against (a height map, a world boundary)
        TYPE_COUNT
    };

    Type type = OTHER;
    // The shape's own frame in the world: the body's transform times the
    // shape's transform on the body. Scale, if any, is left in the basis.
    godot::Transform3D to_world;
    godot::Vector3 size;
    // Which body it belongs to, and which shape resource it is: a contact
    // belongs to the body, and a shape's data is read once per resource.
    uint64_t body = 0;
    int64_t shape = 0;
    int data = -1;
    // How many triangles a concave shape has (for the census).
    int triangles = 0;
};

} // namespace Xenu
