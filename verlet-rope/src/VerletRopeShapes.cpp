// Gathering the shapes near a cord (docs/dev/rope-collision-plan.md, stage 1).
//
// Main thread only: everything here asks the engine. What it leaves behind,
// m_near, is plain data.

#include "VerletRope.hpp"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

namespace Xenu
{

namespace
{
// More bodies than this near one cord and the rest are left out (said once).
constexpr int GATHER_MAX = 48;
// The box asked about reaches this far past the cord, on top of its jacket.
constexpr double GATHER_MARGIN = 0.05;

const char *const TYPE_NAME[RopeShape::TYPE_COUNT] = {"box", "sphere", "capsule", "cylinder",
                                                      "convex", "concave", "other"};
} // namespace

// The bodies whose bounds meet a box round the whole cord, each shape read out
// of the physics server into m_near. One query, however long the cord is.
void VerletRope::GatherShapes(PhysicsDirectSpaceState3D *p_space)
{
    m_near.clear();
    PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
    if (ps == nullptr || p_space == nullptr || m_points.empty() || m_surface_collision_mask == 0)
        return;
    if (!m_gather_box.is_valid())
        m_gather_box = ps->box_shape_create();
    if (m_gather_query.is_null())
    {
        m_gather_query.instantiate();
        m_gather_query->set_shape_rid(m_gather_box);
        m_gather_query->set_collision_mask(m_surface_collision_mask);
        if (m_ray_query.is_valid())
            m_gather_query->set_exclude(m_ray_query->get_exclude());
    }

    Vector3 lo = m_points[0];
    Vector3 hi = m_points[0];
    for (const Vector3 &p : m_points)
    {
        lo = lo.min(p);
        hi = hi.max(p);
    }
    const double pad = m_collision_radius + GATHER_MARGIN;
    const Vector3 half = (hi - lo) * 0.5 + Vector3(pad, pad, pad);
    ps->shape_set_data(m_gather_box, half);
    m_gather_query->set_transform(Transform3D(Basis(), (lo + hi) * 0.5));

    const TypedArray<Dictionary> found = p_space->intersect_shape(m_gather_query, GATHER_MAX);
    const int count = static_cast<int>(found.size());
    if (count >= GATHER_MAX && !m_gather_full_logged)
    {
        m_gather_full_logged = true;
        UtilityFunctions::print("[Rope] ", get_path(), ": ", GATHER_MAX,
                                " or more shapes near this cord; the rest are not seen");
    }
    m_near.reserve(count);
    for (int k = 0; k < count; ++k)
    {
        const Dictionary hit = found[k];
        const RID body = hit["rid"];
        const int index = hit["shape"];
        if (!body.is_valid())
            continue;
        const RID shape = ps->body_get_shape(body, index);
        if (!shape.is_valid())
            continue;
        RopeShape s;
        s.body = static_cast<uint64_t>(body.get_id());
        s.shape = shape.get_id();
        const Transform3D body_xf = ps->body_get_state(body, PhysicsServer3D::BODY_STATE_TRANSFORM);
        s.to_world = body_xf * ps->body_get_shape_transform(body, index);
        const Variant data = ps->shape_get_data(shape);
        switch (ps->shape_get_type(shape))
        {
        case PhysicsServer3D::SHAPE_BOX:
            s.type = RopeShape::BOX;
            s.size = data;
            break;
        case PhysicsServer3D::SHAPE_SPHERE:
            s.type = RopeShape::SPHERE;
            s.size.x = static_cast<double>(data);
            break;
        case PhysicsServer3D::SHAPE_CAPSULE:
        case PhysicsServer3D::SHAPE_CYLINDER:
        {
            const Dictionary d = data;
            const double radius = d.get("radius", 0.0);
            const double height = d.get("height", 0.0);
            const bool capsule = ps->shape_get_type(shape) == PhysicsServer3D::SHAPE_CAPSULE;
            s.type = capsule ? RopeShape::CAPSULE : RopeShape::CYLINDER;
            s.size.x = radius;
            // A capsule's height is tip to tip: its axis runs between cap centres.
            s.size.y = capsule ? std::max(0.0, height * 0.5 - radius) : height * 0.5;
            break;
        }
        case PhysicsServer3D::SHAPE_CONVEX_POLYGON:
            s.type = RopeShape::CONVEX;
            break;
        case PhysicsServer3D::SHAPE_CONCAVE_POLYGON:
        {
            s.type = RopeShape::CONCAVE;
            const Dictionary d = data;
            const PackedVector3Array faces = d.get("faces", PackedVector3Array());
            s.triangles = static_cast<int>(faces.size() / 3);
            break;
        }
        default:
            s.type = RopeShape::OTHER;
            break;
        }
        m_near.push_back(s);
    }
}

// XENU_ROPE_CENSUS=1: what each cord has near it, by kind of shape, said when
// it changes. The count the collision plan's choices rest on.
void VerletRope::CensusShapes(PhysicsDirectSpaceState3D *p_space)
{
    if (++m_census_tick < 90)
        return;
    m_census_tick = 0;
    GatherShapes(p_space);
    int kinds[RopeShape::TYPE_COUNT] = {};
    int triangles = 0;
    for (const RopeShape &s : m_near)
    {
        kinds[s.type] += 1;
        triangles += s.triangles;
    }
    String line;
    for (int t = 0; t < RopeShape::TYPE_COUNT; ++t)
        if (kinds[t] > 0)
            line += String::num_int64(kinds[t]) + " " + TYPE_NAME[t] + " ";
    if (triangles > 0)
        line += "(" + String::num_int64(triangles) + " triangles) ";
    if (line.is_empty())
        line = "nothing ";
    if (line == m_census_last)
        return;
    m_census_last = line;
    UtilityFunctions::print("[Rope] census ", get_path(), ": ", line, "near ",
                            static_cast<int>(m_points.size()), " particles");
}

void VerletRope::FreeGatherShape()
{
    if (!m_gather_box.is_valid())
        return;
    if (PhysicsServer3D *ps = PhysicsServer3D::get_singleton())
        ps->free_rid(m_gather_box);
    m_gather_box = RID();
}

} // namespace Xenu
